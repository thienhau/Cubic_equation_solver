`timescale 1ns / 1ps

module fp_cmp #(
    parameter STAGES = 1
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    input  wire [31:0] in_operand_B,
    
    output reg         out_valid,
    output reg         cmp_eq,  // A == B
    output reg         cmp_gt,  // A > B
    output reg         cmp_lt,  // A < B
    output reg         status_invalid // A hoặc B là NaN
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            cmp_eq <= 1'b0;
            cmp_gt <= 1'b0;
            cmp_lt <= 1'b0;
            status_invalid <= 1'b0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                // Quét NaN (Exponent = toàn 1, Mantissa != 0)
                if ((&in_operand_A[30:23] && in_operand_A[22:0] != 0) || 
                    (&in_operand_B[30:23] && in_operand_B[22:0] != 0)) begin
                    cmp_eq <= 1'b0; cmp_gt <= 1'b0; cmp_lt <= 1'b0;
                    status_invalid <= 1'b1;
                end 
                // Quét trường hợp +0.0 == -0.0
                else if (in_operand_A[30:0] == 0 && in_operand_B[30:0] == 0) begin
                    cmp_eq <= 1'b1; cmp_gt <= 1'b0; cmp_lt <= 1'b0;
                    status_invalid <= 1'b0;
                end 
                // So sánh dấu
                else if (in_operand_A[31] != in_operand_B[31]) begin
                    cmp_eq <= 1'b0;
                    cmp_gt <= ~in_operand_A[31]; // Số dương sẽ lớn hơn số âm
                    cmp_lt <= in_operand_A[31];
                    status_invalid <= 1'b0;
                end 
                // Cùng dấu: So sánh độ lớn (Magnitude)
                else begin
                    if (in_operand_A[30:0] == in_operand_B[30:0]) begin
                        cmp_eq <= 1'b1; cmp_gt <= 1'b0; cmp_lt <= 1'b0;
                    end else if (in_operand_A[30:0] > in_operand_B[30:0]) begin
                        cmp_eq <= 1'b0;
                        cmp_gt <= ~in_operand_A[31]; // Cùng dương -> A > B; Cùng âm -> A < B
                        cmp_lt <= in_operand_A[31];
                    end else begin
                        cmp_eq <= 1'b0;
                        cmp_gt <= in_operand_A[31];
                        cmp_lt <= ~in_operand_A[31];
                    end
                    status_invalid <= 1'b0;
                end
            end
        end
    end
endmodule