`timescale 1ns / 1ps

module fp_add_const #(
    parameter STAGES = 2,
    parameter [31:0] FLOAT_CONST = 32'h3F800000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output reg         out_valid,
    output reg  [31:0] out_result
);
    wire        const_sign = FLOAT_CONST[31];
    wire [7:0]  const_exp  = FLOAT_CONST[30:23];
    wire [23:0] const_mant = {1'b1, FLOAT_CONST[22:0]};

    // T = 0 -> 1: Căn lề số nhỏ dựa trên Exponent
    reg s1_valid;
    reg s1_sign_res;
    reg [7:0] s1_exp_max;
    reg [24:0] s1_sum;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
            s1_sign_res <= 1'b0;
            s1_exp_max <= 8'd0;
            s1_sum <= 25'd0;
        end else begin
            s1_valid <= in_valid;
            if (in_valid) begin
                wire in_sign = in_operand_A[31];
                wire [7:0] in_exp = in_operand_A[30:23];
                wire [23:0] in_mant = (|in_exp) ? {1'b1, in_operand_A[22:0]} : 24'd0;
                
                if (in_operand_A[30:0] >= FLOAT_CONST[30:0]) begin
                    s1_sign_res <= in_sign;
                    s1_exp_max  <= in_exp;
                    
                    wire [4:0] shift = ((in_exp - const_exp) > 25) ? 25 : (in_exp - const_exp);
                    wire [23:0] aligned_c = const_mant >> shift;
                    
                    s1_sum <= (in_sign == const_sign) ? (in_mant + aligned_c) : (in_mant - aligned_c);
                end else begin
                    s1_sign_res <= const_sign;
                    s1_exp_max  <= const_exp;
                    
                    wire [4:0] shift = ((const_exp - in_exp) > 25) ? 25 : (const_exp - in_exp);
                    wire [23:0] aligned_in = in_mant >> shift;
                    
                    s1_sum <= (in_sign == const_sign) ? (const_mant + aligned_in) : (const_mant - aligned_in);
                end
            end
        end
    end

    // T = 1 -> 2: LZA Tĩnh và đóng gói
    integer i;
    reg [4:0] lza_shift;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_result <= 32'd0;
        end else begin
            out_valid <= s1_valid;
            if (s1_valid) begin
                if (s1_sum == 0) begin
                    out_result <= 32'd0;
                end else if (s1_sum[24]) begin 
                    out_result <= {s1_sign_res, s1_exp_max + 8'd1, s1_sum[23:1]};
                end else begin
                    lza_shift = 0;
                    for (i = 23; i >= 0; i = i - 1) begin
                        if (s1_sum[i]) begin
                            lza_shift = 23 - i;
                            break;
                        end
                    end
                    wire [23:0] norm_mant = s1_sum[23:0] << lza_shift;
                    out_result <= {s1_sign_res, s1_exp_max - lza_shift, norm_mant[22:0]};
                end
            end
        end
    end
endmodule