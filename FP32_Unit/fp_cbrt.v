`timescale 1ns / 1ps

module fp_cbrt #(
    parameter STAGES = 26
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output wire        out_valid,
    output wire [31:0] out_result
);
    // T = 0 -> 1: Tiền xử lý và Đọc ROM
    wire signed [9:0] e_diff = $signed({2'b00, in_operand_A[30:23]}) - 10'sd127;
    wire signed [9:0] k_signed = (e_diff >= 0) ? (e_diff / 3) : ((e_diff - 2) / 3);
    wire [1:0] r = e_diff - k_signed * 3;
    wire [7:0] k_exp = k_signed + 8'd127;
    wire [31:0] w_fp = {1'b0, 8'd127 + {6'd0, r}, in_operand_A[22:0]};
    wire sign_res = in_operand_A[31];
    
    wire [31:0] y0_rom;
    pade_cbrt_rom u_rom (
        .clk(clk), 
        .addr(w_fp[22:15]), 
        .data_out(y0_rom)
    );

    reg [31:0] w_d1; reg [7:0] k_d1; reg v_d1; reg s_d1;
    reg [1:0] r_d1; // PHẢI CÓ THANH GHI NÀY ĐỂ TRÁNH RACE CONDITION
    always @(posedge clk) begin 
        w_d1 <= w_fp; k_d1 <= k_exp;
        v_d1 <= in_valid; s_d1 <= sign_res; 
        r_d1 <= r; 
    end

    // --- LOGIC SCALE CHUẨN HOÁ GIÁ TRỊ TỪ ROM ---
    wire [25:0] m_y0 = {1'b1, y0_rom[22:0], 2'b0};
    
    // Nếu r=1: nhân hệ số ~0.7937
    wire [25:0] y0_r1 = (m_y0 >> 1) + (m_y0 >> 2) + (m_y0 >> 5) + (m_y0 >> 7) + (m_y0 >> 8) + (m_y0 >> 11) + (m_y0 >> 13);
    // Nếu r=2: nhân hệ số ~0.6299
    wire [25:0] y0_r2 = (m_y0 >> 1) + (m_y0 >> 3) + (m_y0 >> 8) + (m_y0 >> 10) + (m_y0 >> 12) + (m_y0 >> 14);
    
    wire [25:0] y0_scaled = (r_d1 == 2) ? y0_r2 : ((r_d1 == 1) ? y0_r1 : m_y0);
    
    wire shift_req = ~y0_scaled[25]; 
    wire [22:0] final_y0_mant = shift_req ? y0_scaled[23:1] : y0_scaled[24:2];
    wire [7:0]  final_y0_exp  = y0_rom[30:23] - shift_req;
    
    wire [31:0] y0 = (r_d1 == 0) ? y0_rom : {y0_rom[31], final_y0_exp, final_y0_mant};

    // T = 1 -> 5: MUL1 (t1 = y0*y0)
    wire [31:0] t1;
    wire v_t1;
    fp_mul u_mul1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_d1), 
        .in_operand_A(y0), .in_operand_B(y0), 
        .out_valid(v_t1), .out_result(t1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] w_d5, y0_d5; wire [7:0] k_d5; wire s_d5;
    shift_reg #(.W(32), .D(4)) dw5 (.clk(clk), .in(w_d1), .out(w_d5));
    shift_reg #(.W(32), .D(4)) dy5 (.clk(clk), .in(y0), .out(y0_d5));
    shift_reg #(.W(8),  .D(4)) dk5 (.clk(clk), .in(k_d1), .out(k_d5));
    shift_reg #(.W(1),  .D(4)) ds5 (.clk(clk), .in(s_d1), .out(s_d5));
    
    // T = 5 -> 9: MUL2 (t2 = y0*t1)
    wire [31:0] t2;
    wire v_t2;
    fp_mul u_mul2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t1), 
        .in_operand_A(y0_d5), .in_operand_B(t1), 
        .out_valid(v_t2), .out_result(t2),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] w_d9, y0_d9; wire [7:0] k_d9; wire s_d9;
    shift_reg #(.W(32), .D(4)) dw9 (.clk(clk), .in(w_d5), .out(w_d9));
    shift_reg #(.W(32), .D(4)) dy9 (.clk(clk), .in(y0_d5), .out(y0_d9));
    shift_reg #(.W(8),  .D(4)) dk9 (.clk(clk), .in(k_d5), .out(k_d9));
    shift_reg #(.W(1),  .D(4)) ds9 (.clk(clk), .in(s_d5), .out(s_d9));
    
    // T = 9 -> 14: FMA (t3 = 4/3 - (w/3)*t2)
    wire [25:0] m_w = {1'b1, w_d9[22:0], 2'b0};
    wire [25:0] m_w3 = (m_w>>2) + (m_w>>4) + (m_w>>6) + (m_w>>8);
    wire [31:0] neg_w_third = {1'b1, w_d9[30:23] - 8'd2, m_w3[22:0]};

    wire [31:0] t3; wire v_t3;
    fp_fma u_fma1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t2), 
        .in_operand_A(neg_w_third), .in_operand_B(t2), .in_operand_C(32'h3FAAAAAB), 
        .out_valid(v_t3), .out_result(t3),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] w_d14, y0_d14; wire [7:0] k_d14; wire s_d14;
    shift_reg #(.W(32), .D(5)) dw14 (.clk(clk), .in(w_d9), .out(w_d14));
    shift_reg #(.W(32), .D(5)) dy14 (.clk(clk), .in(y0_d9), .out(y0_d14));
    shift_reg #(.W(8),  .D(5)) dk14 (.clk(clk), .in(k_d9), .out(k_d14));
    shift_reg #(.W(1),  .D(5)) ds14 (.clk(clk), .in(s_d9), .out(s_d14));
    
    // T = 14 -> 18: MUL3 (y1 = y0*t3)
    wire [31:0] y1;
    wire v_t4;
    fp_mul u_mul3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t3), 
        .in_operand_A(y0_d14), .in_operand_B(t3), 
        .out_valid(v_t4), .out_result(y1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] w_d18; wire [7:0] k_d18; wire s_d18;
    shift_reg #(.W(32), .D(4)) dw18 (.clk(clk), .in(w_d14), .out(w_d18));
    shift_reg #(.W(8),  .D(4)) dk18 (.clk(clk), .in(k_d14), .out(k_d18)); 
    shift_reg #(.W(1),  .D(4)) ds18 (.clk(clk), .in(s_d14), .out(s_d18));

    // T = 18 -> 22: MUL4 (t4 = y1*y1)
    wire [31:0] t4; wire v_t5;
    fp_mul u_mul4 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t4), 
        .in_operand_A(y1), .in_operand_B(y1), 
        .out_valid(v_t5), .out_result(t4),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] w_d22; wire [7:0] k_d22; wire s_d22;
    shift_reg #(.W(32), .D(4)) dw22 (.clk(clk), .in(w_d18), .out(w_d22));
    shift_reg #(.W(8),  .D(4)) dk22 (.clk(clk), .in(k_d18), .out(k_d22)); 
    shift_reg #(.W(1),  .D(4)) ds22 (.clk(clk), .in(s_d18), .out(s_d22));

    // T = 22 -> 26: MUL5 (out_raw = w*t4)
    wire [31:0] raw; wire v_out;
    fp_mul u_mul5 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t5), 
        .in_operand_A(w_d22), .in_operand_B(t4), 
        .out_valid(v_out), .out_result(raw),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [7:0] k_d26; wire s_d26;
    shift_reg #(.W(8), .D(4)) dk26 (.clk(clk), .in(k_d22), .out(k_d26));
    shift_reg #(.W(1), .D(4)) ds26 (.clk(clk), .in(s_d22), .out(s_d26));

    wire in_is_zero_d26;
    shift_reg #(.W(1), .D(26)) d_zero (.clk(clk), .in(~|in_operand_A[30:23]), .out(in_is_zero_d26));

    assign out_valid = v_out;
    assign out_result = in_is_zero_d26 ? 32'd0 : {s_d26, raw[30:23] + k_d26 - 8'd127, raw[22:0]};
endmodule