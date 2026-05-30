`timescale 1ns / 1ps

module fp_neg #(
    parameter STAGES = 0
)(
    input  wire [31:0] in_operand_A,
    output wire [31:0] out_result
);
    // T = 0 -> 0: Đảo dấu bit 31 bằng 1 cổng NOT
    assign out_result = {~in_operand_A[31], in_operand_A[30:0]};
endmodule