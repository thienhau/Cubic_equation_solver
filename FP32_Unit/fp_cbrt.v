`timescale 1ns / 1ps

module pade_cbrt_rom (
    input  wire        clk,
    input  wire [7:0]  addr,
    output reg  [31:0] data_out
);
    (* rom_style = "block" *) reg [31:0] rom_array [0:255];

    initial begin
        $readmemh("pade_cbrt_fp32.mem", rom_array);
    end

    always @(posedge clk) begin
        data_out <= rom_array[addr];
    end
endmodule

module fp_cbrt (
    input clk, rst_n, in_valid,
    input [31:0] in_operand_A,
    output out_valid, output [31:0] out_result
);
    // Tính toán lại Exponent và đưa Mantissa về khoảng chuẩn cho ROM
    wire signed [9:0] e_diff = $signed({2'b00, in_operand_A[30:23]}) - 10'sd127;
    wire signed [9:0] k_signed = (e_diff >= 0) ? (e_diff / 3) : ((e_diff - 2) / 3);
    wire [1:0] r = e_diff - k_signed * 3;
    wire [7:0] k_exp = k_signed + 8'd127;
    
    wire [31:0] w_fp = {1'b0, 8'd127 + {6'd0, r}, in_operand_A[22:0]};
    wire sign_res = in_operand_A[31];
    
    // T = 1: Đọc ROM
    wire [31:0] y0;
    pade_cbrt_rom u_rom (.clk(clk), .addr(w_fp[22:15]), .data_out(y0));
    reg [31:0] w_d1; reg [7:0] k_d1; reg v_d1; reg s_d1;
    always @(posedge clk) begin w_d1<=w_fp; k_d1<=k_exp; v_d1<=in_valid; s_d1<=sign_res; end

    // T = 1 -> 5: MUL1 (t1 = y0*y0)
    wire [31:0] t1; wire v_t1;
    fp_mul mul1 (.clk(clk), .rst_n(rst_n), .in_valid(v_d1), .in_operand_A(y0), .in_operand_B(y0), .out_valid(v_t1), .out_result(t1));
    wire [31:0] w_d5, y0_d5; wire [7:0] k_d5; wire s_d5;
    shift_reg #(32,4) dw5(clk,w_d1,w_d5); shift_reg #(32,4) dy5(clk,y0,y0_d5); 
    shift_reg #(8,4) dk5(clk,k_d1,k_d5);  shift_reg #(1,4) ds5(clk,s_d1,s_d5);
    
    // T = 5 -> 9: MUL2 (t2 = y0*t1)
    wire [31:0] t2; wire v_t2;
    fp_mul mul2 (.clk(clk), .rst_n(rst_n), .in_valid(v_t1), .in_operand_A(y0_d5), .in_operand_B(t1), .out_valid(v_t2), .out_result(t2));
    wire [31:0] w_d9, y0_d9; wire [7:0] k_d9; wire s_d9;
    shift_reg #(32,4) dw9(clk,w_d5,w_d9); shift_reg #(32,4) dy9(clk,y0_d5,y0_d9);
    shift_reg #(8,4) dk9(clk,k_d5,k_d9);  shift_reg #(1,4) ds9(clk,s_d5,s_d9);
    
    // T = 9 -> 14: FMA (t3 = 4/3 - (w/3)*t2)
    wire [25:0] m_w = {1'b1, w_d9[22:0], 2'b0};
    wire [25:0] m_w3 = (m_w>>2) + (m_w>>4) + (m_w>>6) + (m_w>>8);
    wire [31:0] neg_w_third = {1'b1, w_d9[30:23], m_w3[24:2]};
    wire [31:0] t3; wire v_t3;
    fp_fma fma1 (.clk(clk), .rst_n(rst_n), .in_valid(v_t2), .in_operand_A(neg_w_third), .in_operand_B(t2), .in_operand_C(32'h3FAAAAAB), .out_valid(v_t3), .out_result(t3));
    wire [31:0] w_d14, y0_d14; wire [7:0] k_d14; wire s_d14;
    shift_reg #(32,5) dw14(clk,w_d9,w_d14); shift_reg #(32,5) dy14(clk,y0_d9,y0_d14);
    shift_reg #(8,5) dk14(clk,k_d9,k_d14);  shift_reg #(1,5) ds14(clk,s_d9,s_d14);
    
    // T = 14 -> 18: MUL3 (y1 = y0*t3)
    wire [31:0] y1; wire v_t4;
    fp_mul mul3 (.clk(clk), .rst_n(rst_n), .in_valid(v_t3), .in_operand_A(y0_d14), .in_operand_B(t3), .out_valid(v_t4), .out_result(y1));
    wire [31:0] w_d18; wire [7:0] k_d18; wire s_d18;
    shift_reg #(32,4) dw18(clk,w_d14,w_d18);
    shift_reg #(8,4) dk18(clk,k_d14,k_d18); shift_reg #(1,4) ds18(clk,s_d14,s_d18);

    // T = 18 -> 22: MUL4 (t4 = y1*y1)
    wire [31:0] t4; wire v_t5;
    fp_mul mul4 (.clk(clk), .rst_n(rst_n), .in_valid(v_t4), .in_operand_A(y1), .in_operand_B(y1), .out_valid(v_t5), .out_result(t4));
    wire [31:0] w_d22; wire [7:0] k_d22; wire s_d22;
    shift_reg #(32,4) dw22(clk,w_d18,w_d22); shift_reg #(8,4) dk22(clk,k_d18,k_d22); shift_reg #(1,4) ds22(clk,s_d18,s_d22);

    // T = 22 -> 26: MUL5 (out_raw = w*t4)
    wire [31:0] raw; wire v_out;
    fp_mul mul5 (.clk(clk), .rst_n(rst_n), .in_valid(v_t5), .in_operand_A(w_d22), .in_operand_B(t4), .out_valid(v_out), .out_result(raw));
    wire [7:0] k_d26; wire s_d26;
    shift_reg #(8,4) dk26(clk,k_d22,k_d26);
    shift_reg #(1,4) ds26(clk,s_d22,s_d26);

    assign out_valid = v_out;
    assign out_result = {s_d26, raw[30:23] + k_d26, raw[22:0]};
endmodule