`timescale 1ns / 1ps

module fp_acos (
    input clk, rst_n, in_valid,
    input [31:0] in_operand_A,
    output out_valid, output [31:0] out_result
);
    localparam A_N3 = 32'hB2000000; localparam A_N2 = 32'h35000000; localparam A_N1 = 32'hBE000000; localparam A_N0 = 32'h3FC90FDB;
    localparam A_D3 = 32'h31000000; localparam A_D2 = 32'h34000000; localparam A_D1 = 32'h3B000000; localparam A_D0 = 32'h3F800000;

    wire [31:0] x_abs = {1'b0, in_operand_A[30:0]};
    reg [31:0] x_d1; reg s_d1; reg v_d1;
    always @(posedge clk) begin x_d1<=x_abs; s_d1<=in_operand_A[31]; v_d1<=in_valid; end

    wire [31:0] x_d6, x_d11, x_d16; wire s_d6, s_d11, s_d16, s_d30;
    shift_reg #(32, 5) dx1(clk, x_d1, x_d6);
    shift_reg #(32, 5) dx2(clk, x_d6, x_d11); shift_reg #(32, 5) dx3(clk, x_d11, x_d16);
    shift_reg #(1, 5) ds1(clk, s_d1, s_d6);
    shift_reg #(1, 5) ds2(clk, s_d6, s_d11); shift_reg #(1, 5) ds3(clk, s_d11, s_d16);
    shift_reg #(1, 14) ds4(clk, s_d16, s_d30);
    
    wire [31:0] tn1, td1; wire v_s1;
    fp_fma fma_n1(clk, rst_n, v_d1, A_N3, x_d1, A_N2, v_s1, tn1);
    fp_fma fma_d1(clk, rst_n, v_d1, A_D3, x_d1, A_D2, , td1);

    wire [31:0] tn2, td2; wire v_s2;
    fp_fma fma_n2(clk, rst_n, v_s1, tn1, x_d6, A_N1, v_s2, tn2);
    fp_fma fma_d2(clk, rst_n, v_s1, td1, x_d6, A_D1, , td2);
    
    wire [31:0] n_fin, d_fin; wire v_s3;
    fp_fma fma_n3(clk, rst_n, v_s2, tn2, x_d11, A_N0, v_s3, n_fin);
    fp_fma fma_d3(clk, rst_n, v_s2, td2, x_d11, A_D0, , d_fin);

    wire [31:0] div_res; wire v_div;
    fp_div div_op(clk, rst_n, v_s3, n_fin, d_fin, v_div, div_res);

    // FMA Bù góc PI - acos(|x|) nếu x âm. Dùng MUX để chọn ngõ ra cuối
    wire [31:0] fma_adjust; wire v_fma;
    fp_fma fma_quad(clk, rst_n, v_div, 32'hBF800000, div_res, 32'h40490FDB, v_fma, fma_adjust);

    wire [31:0] div_dly;
    shift_reg #(32, 5) ddiv(clk, div_res, div_dly); wire s_d35;
    shift_reg #(1, 5) dfin(clk, s_d30, s_d35);

    assign out_valid = v_fma;
    assign out_result = s_d35 ? fma_adjust : div_dly;
endmodule