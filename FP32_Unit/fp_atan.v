`timescale 1ns / 1ps

module fp_atan (
    input clk, rst_n, in_valid,
    input [31:0] in_operand_A,
    output out_valid, output [31:0] out_result
);
    localparam C1 = 32'h3F800000; localparam C2 = 32'h3EAAAAAB; localparam C3 = 32'h3F19999A; localparam ONE= 32'h3F800000;
    
    wire [31:0] x_reg = {1'b0, in_operand_A[30:0]};
    reg [31:0] x_d1; reg s_d1, v_d1;
    always @(posedge clk) begin x_d1<=x_reg; s_d1<=in_operand_A[31]; v_d1<=in_valid; end

    wire [31:0] x2; wire v_x2;
    fp_mul mul_x2(clk, rst_n, v_d1, x_d1, x_d1, v_x2, x2);
    wire [31:0] x_d5; wire s_d5; 
    shift_reg #(32,4) dx5(clk,x_d1,x_d5); shift_reg #(1,4) ds5(clk,s_d1,s_d5);

    wire [31:0] n_part, d_part; wire v_fma;
    fp_fma fma_n(clk, rst_n, v_x2, C2, x2, C1, v_fma, n_part);
    fp_fma fma_d(clk, rst_n, v_x2, C3, x2, ONE, , d_part);
    wire [31:0] x_d10; wire s_d10;
    shift_reg #(32,5) dx10(clk,x_d5,x_d10); shift_reg #(1,5) ds10(clk,s_d5,s_d10);

    wire [31:0] n_fin; wire v_n;
    fp_mul mul_n(clk, rst_n, v_fma, n_part, x_d10, v_n, n_fin);
    wire [31:0] d_d4; wire s_d14;
    shift_reg #(32,4) dd4(clk,d_part,d_d4); shift_reg #(1,4) ds14(clk,s_d10,s_d14);

    wire [31:0] div_res; wire v_div;
    fp_div div_op(clk, rst_n, v_n, n_fin, d_d4, v_div, div_res);
    wire s_d28; shift_reg #(1,14) ds28(clk,s_d14,s_d28);

    assign out_valid = v_div;
    assign out_result = {s_d28, div_res[30:0]};
endmodule