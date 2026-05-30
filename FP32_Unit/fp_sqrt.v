`timescale 1ns / 1ps

module fp_sqrt #(
    parameter STAGES = 18
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output wire        out_valid,
    output wire [31:0] out_result
);
    // T = 0 -> 1: Tiền xử lý và Đọc ROM
    wire signed [8:0] e_diff = $signed({1'b0, in_operand_A[30:23]}) - 9'sd127;
    wire [7:0] k_exp = e_diff >>> 1;
    wire [31:0] w_fp = (e_diff[0]) ? {1'b0, 8'd128, in_operand_A[22:0]} : {1'b0, 8'd127, in_operand_A[22:0]};
    
    wire [31:0] y0_rom;
    pade_sqrt_rom u_rom (
        .clk(clk), 
        .addr(w_fp[22:15]), 
        .data_out(y0_rom)
    );
    
    reg [31:0] w_d1; reg [7:0] k_d1; reg v_d1;
    reg e_odd_d1; // THÊM BIẾN LƯU TRẠNG THÁI MŨ LẺ
    always @(posedge clk) begin 
        w_d1 <= w_fp;
        k_d1 <= k_exp;
        v_d1 <= in_valid; 
        e_odd_d1 <= e_diff[0];
    end

    // --- SCALE INITIAL GUESS CHO MŨ LẺ ---
    wire [25:0] m_y0 = {1'b1, y0_rom[22:0], 2'b0};
    
    // Hệ số 0.70703125 (Xấp xỉ 1/sqrt(2) = 1/2 + 1/8 + 1/16 + 1/64 + 1/256)
    wire [25:0] y0_scaled_odd = (m_y0 >> 1) + (m_y0 >> 3) + (m_y0 >> 4) + (m_y0 >> 6) + (m_y0 >> 8);
    wire [25:0] y0_scaled = e_odd_d1 ? y0_scaled_odd : m_y0;
    
    // Chuẩn hóa lại dạng Float 32
    wire shift_req = ~y0_scaled[25];
    wire [22:0] final_y0_mant = shift_req ? y0_scaled[23:1] : y0_scaled[24:2];
    wire [7:0]  final_y0_exp  = y0_rom[30:23] - shift_req;
    
    wire [31:0] y0 = {y0_rom[31], final_y0_exp, final_y0_mant};

    // T = 1 -> 5: MUL1 (t1 = y0 * y0)
    wire [31:0] t1; wire v_t1;
    fp_mul u_mul1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_d1), 
        .in_operand_A(y0), .in_operand_B(y0), 
        .out_valid(v_t1), .out_result(t1), 
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] w_d5, y0_d5; wire [7:0] k_d5;
    shift_reg #(.W(32), .D(4)) dly_w5 (.clk(clk), .in(w_d1), .out(w_d5));
    shift_reg #(.W(32), .D(4)) dly_y5 (.clk(clk), .in(y0), .out(y0_d5));
    shift_reg #(.W(8),  .D(4)) dly_k5 (.clk(clk), .in(k_d1), .out(k_d5));

    // T = 5 -> 10: FMA1 (t2 = 1.5 - 0.5 * w * t1)
    wire [31:0] neg_half_w = {~w_d5[31], w_d5[30:23] - 8'd1, w_d5[22:0]};
    wire [31:0] t2; wire v_t2;
    fp_fma u_fma1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t1), 
        .in_operand_A(neg_half_w), .in_operand_B(t1), .in_operand_C(32'h3FC00000), 
        .out_valid(v_t2), .out_result(t2),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] w_d10, y0_d10; wire [7:0] k_d10;
    shift_reg #(.W(32), .D(5)) dly_w10 (.clk(clk), .in(w_d5), .out(w_d10));
    shift_reg #(.W(32), .D(5)) dly_y10 (.clk(clk), .in(y0_d5), .out(y0_d10));
    shift_reg #(.W(8),  .D(5)) dly_k10 (.clk(clk), .in(k_d5), .out(k_d10));

    // T = 10 -> 14: MUL2 (y1 = y0 * t2)
    wire [31:0] y1; wire v_t3;
    fp_mul u_mul2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t2), 
        .in_operand_A(y0_d10), .in_operand_B(t2), 
        .out_valid(v_t3), .out_result(y1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] w_d14; wire [7:0] k_d14;
    shift_reg #(.W(32), .D(4)) dly_w14 (.clk(clk), .in(w_d10), .out(w_d14));
    shift_reg #(.W(8),  .D(4)) dly_k14 (.clk(clk), .in(k_d10), .out(k_d14));

    // T = 14 -> 18: MUL3 (out_raw = w * y1)
    wire [31:0] sqrt_raw; wire v_out;
    fp_mul u_mul3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t3), 
        .in_operand_A(w_d14), .in_operand_B(y1), 
        .out_valid(v_out), .out_result(sqrt_raw),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [7:0] k_d18;
    shift_reg #(.W(8), .D(4)) dly_k18 (.clk(clk), .in(k_d14), .out(k_d18));

    // BYPASS số 0 để tránh văng rác
    wire z_d18;
    shift_reg #(.W(1), .D(18)) dly_z (.clk(clk), .in(~|in_operand_A[30:23]), .out(z_d18));

    assign out_valid = v_out;
    assign out_result = z_d18 ? 32'd0 : {1'b0, sqrt_raw[30:23] + k_d18, sqrt_raw[22:0]};
endmodule