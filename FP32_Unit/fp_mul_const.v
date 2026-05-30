`timescale 1ns / 1ps

module fp_mul_const #(
    parameter STAGES = 2
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output reg         out_valid,
    output reg  [31:0] out_result
);
    wire        in_sign = in_operand_A[31];
    wire [7:0]  in_exp  = in_operand_A[30:23];
    wire [23:0] in_mant = {1'b1, in_operand_A[22:0]};

    // T = 0 -> 1: Dịch bit cứng và cộng tầng 1
    reg        s1_valid;
    reg        s1_sign;
    reg [7:0]  s1_exp;
    reg [25:0] s1_sum_A, s1_sum_B, s1_sum_C;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
            s1_sign <= 1'b0; s1_exp <= 8'd0;
            s1_sum_A <= 26'd0; s1_sum_B <= 26'd0; s1_sum_C <= 26'd0;
        end else begin
            s1_valid <= in_valid;
            s1_sign  <= in_sign;
            s1_exp   <= in_exp;
            
            if (in_valid && in_exp != 0) begin
                s1_sum_A <= (in_mant >> 2)  + (in_mant >> 4);
                s1_sum_B <= (in_mant >> 6)  + (in_mant >> 8);
                s1_sum_C <= (in_mant >> 10) + (in_mant >> 12) + (in_mant >> 14);
            end else begin
                {s1_sum_A, s1_sum_B, s1_sum_C} <= 0;
            end
        end
    end

    // T = 1 -> 2: Cộng tầng cuối và đóng gói
    wire [25:0] final_mant_sum = s1_sum_A + s1_sum_B + s1_sum_C;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_result <= 32'd0;
        end else begin
            out_valid <= s1_valid;
            if (s1_valid) begin
                if (s1_exp == 0) begin
                    out_result <= 32'd0;
                end else begin
                    if (final_mant_sum[23]) begin
                        out_result <= {s1_sign, s1_exp - 8'd1, final_mant_sum[22:0]};
                    end else begin
                        out_result <= {s1_sign, s1_exp - 8'd2, final_mant_sum[21:0], 1'b0};
                    end
                end
            end
        end
    end
endmodule