`timescale 1ns / 1ps

module fp_neg #(
    parameter STAGES = 0
)(
    input  wire [31:0] in_operand_A,
    output wire [31:0] out_result
);
    // Cực kỳ tối ưu: Chỉ dùng đúng 1 cổng NOT cho bit 31
    assign out_result = {~in_operand_A[31], in_operand_A[30:0]};
endmodule