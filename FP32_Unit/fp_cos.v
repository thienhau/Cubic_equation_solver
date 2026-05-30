`timescale 1ns / 1ps

module fp_cos (
    input clk, rst_n, in_valid,
    input [31:0] in_operand_A,
    output out_valid, output [31:0] out_result
);
    localparam N3 = 32'hB5000000; localparam N2 = 32'h39000000; localparam N1 = 32'hBF000000; localparam N0 = 32'h3F800000;
    localparam D3 = 32'h33000000; localparam D2 = 32'h38000000; localparam D1 = 32'h3D000000; localparam D0 = 32'h3F800000;

    // T = 0 -> 4: z = x*x
    wire [31:0] z; wire v_z;
    fp_mul mul_z (.clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_operand_A(in_operand_A), .in_operand_B(in_operand_A), .out_valid(v_z), .out_result(z));

    wire [31:0] z_d5, z_d10;
    shift_reg #(32, 5) dz1(clk, z, z_d5);
    shift_reg #(32, 5) dz2(clk, z_d5, z_d10);

    // T = 4 -> 9: FMA1 (Horner)
    wire [31:0] tn1, td1; wire v_s1;
    fp_fma fma_n1(clk, rst_n, v_z, N3, z, N2, v_s1, tn1);
    fp_fma fma_d1(clk, rst_n, v_z, D3, z, D2, , td1);

    // T = 9 -> 14: FMA2
    wire [31:0] tn2, td2; wire v_s2;
    fp_fma fma_n2(clk, rst_n, v_s1, tn1, z_d5, N1, v_s2, tn2);
    fp_fma fma_d2(clk, rst_n, v_s1, td1, z_d5, D1, , td2);

    // T = 14 -> 19: FMA3
    wire [31:0] n_fin, d_fin; wire v_s3;
    fp_fma fma_n3(clk, rst_n, v_s2, tn2, z_d10, N0, v_s3, n_fin);
    fp_fma fma_d3(clk, rst_n, v_s2, td2, z_d10, D0, , d_fin);

    // T = 19 -> 33: DIV
    fp_div div_out(clk, rst_n, v_s3, n_fin, d_fin, out_valid, out_result);
endmodule