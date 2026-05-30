`timescale 1ns / 1ps

module pade_sqrt_rom (
    input  wire        clk,
    input  wire [7:0]  addr,
    output reg  [31:0] data_out
);
    // Ep trinh tong hop (Vivado) dung Block RAM
    (* rom_style = "block" *) reg [31:0] rom_array [0:255];

    initial begin
        // File mem nay chua 256 ma Hex cua so Float32 (VD: 3F800000)
        $readmemh("pade_sqrt_fp32.mem", rom_array);
    end

    always @(posedge clk) begin
        data_out <= rom_array[addr];
    end
endmodule

module fp_sqrt (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    output wire        out_valid,
    output wire [31:0] out_result
);
    // T = 0: Tiền xử lý
    wire signed [8:0] e_diff = $signed({1'b0, in_operand_A[30:23]}) - 9'sd127;
    wire [7:0] k_exp = e_diff >>> 1;
    wire [31:0] w_fp = (e_diff[0]) ? {1'b0, 8'd128, in_operand_A[22:0]} : {1'b0, 8'd127, in_operand_A[22:0]};
    
    // T = 1: Đọc ROM 
    wire [31:0] y0;
    pade_sqrt_rom u_rom (.clk(clk), .addr(w_fp[22:15]), .data_out(y0));
    
    reg [31:0] w_d1; reg [7:0] k_d1; reg v_d1;
    always @(posedge clk) begin w_d1 <= w_fp; k_d1 <= k_exp; v_d1 <= in_valid; end

    // T = 1 -> 5: MUL1 (t1 = y0 * y0)
    wire [31:0] t1; wire v_t1;
    fp_mul mul1 (.clk(clk), .rst_n(rst_n), .in_valid(v_d1), .in_operand_A(y0), .in_operand_B(y0), .out_valid(v_t1), .out_result(t1));

    wire [31:0] w_d5, y0_d5; wire [7:0] k_d5;
    shift_reg #(32, 4) dly_w5 (.clk(clk), .in(w_d1), .out(w_d5));
    shift_reg #(32, 4) dly_y5 (.clk(clk), .in(y0), .out(y0_d5));
    shift_reg #(8,  4) dly_k5 (.clk(clk), .in(k_d1), .out(k_d5));

    // T = 5 -> 10: FMA1 (t2 = 1.5 - 0.5 * w * t1)
    wire [31:0] neg_half_w = {~w_d5[31], w_d5[30:23] - 8'd1, w_d5[22:0]};
    wire [31:0] t2; wire v_t2;
    fp_fma fma1 (.clk(clk), .rst_n(rst_n), .in_valid(v_t1), .in_operand_A(neg_half_w), .in_operand_B(t1), .in_operand_C(32'h3FC00000), .out_valid(v_t2), .out_result(t2));

    wire [31:0] w_d10, y0_d10; wire [7:0] k_d10;
    shift_reg #(32, 5) dly_w10 (.clk(clk), .in(w_d5), .out(w_d10));
    shift_reg #(32, 5) dly_y10 (.clk(clk), .in(y0_d5), .out(y0_d10));
    shift_reg #(8,  5) dly_k10 (.clk(clk), .in(k_d5), .out(k_d10));

    // T = 10 -> 14: MUL2 (y1 = y0 * t2)
    wire [31:0] y1; wire v_t3;
    fp_mul mul2 (.clk(clk), .rst_n(rst_n), .in_valid(v_t2), .in_operand_A(y0_d10), .in_operand_B(t2), .out_valid(v_t3), .out_result(y1));

    wire [31:0] w_d14; wire [7:0] k_d14;
    shift_reg #(32, 4) dly_w14 (.clk(clk), .in(w_d10), .out(w_d14));
    shift_reg #(8,  4) dly_k14 (.clk(clk), .in(k_d10), .out(k_d14));

    // T = 14 -> 18: MUL3 (out_raw = w * y1)
    wire [31:0] sqrt_raw; wire v_out;
    fp_mul mul3 (.clk(clk), .rst_n(rst_n), .in_valid(v_t3), .in_operand_A(w_d14), .in_operand_B(y1), .out_valid(v_out), .out_result(sqrt_raw));

    wire [7:0] k_d18;
    shift_reg #(8, 4) dly_k18 (.clk(clk), .in(k_d14), .out(k_d18));

    assign out_valid = v_out;
    assign out_result = {1'b0, sqrt_raw[30:23] + k_d18, sqrt_raw[22:0]};
endmodule