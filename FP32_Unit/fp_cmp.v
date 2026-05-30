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
    output reg         cmp_eq,
    output reg         cmp_gt,
    output reg         cmp_lt,
    output reg         status_invalid
);
    // T = 0 -> 1: Quét ngoại lệ, so sánh dấu và so sánh độ lớn
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
                if ((&in_operand_A[30:23] && in_operand_A[22:0] != 0) || 
                    (&in_operand_B[30:23] && in_operand_B[22:0] != 0)) begin
                    cmp_eq <= 1'b0;
                    cmp_gt <= 1'b0; cmp_lt <= 1'b0;
                    status_invalid <= 1'b1;
                end 
                else if (in_operand_A[30:0] == 0 && in_operand_B[30:0] == 0) begin
                    cmp_eq <= 1'b1;
                    cmp_gt <= 1'b0; cmp_lt <= 1'b0;
                    status_invalid <= 1'b0;
                end 
                else if (in_operand_A[31] != in_operand_B[31]) begin
                    cmp_eq <= 1'b0;
                    cmp_gt <= ~in_operand_A[31];
                    cmp_lt <= in_operand_A[31];
                    status_invalid <= 1'b0;
                end 
                else begin
                    if (in_operand_A[30:0] == in_operand_B[30:0]) begin
                        cmp_eq <= 1'b1;
                        cmp_gt <= 1'b0; cmp_lt <= 1'b0;
                    end else if (in_operand_A[30:0] > in_operand_B[30:0]) begin
                        cmp_eq <= 1'b0;
                        cmp_gt <= ~in_operand_A[31];
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