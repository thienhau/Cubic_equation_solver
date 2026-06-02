`timescale 1ns / 1ps

module fp_sqrt #(
    parameter STAGES = 18
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output wire        out_valid,
    output wire [31:0] out_result,
    output wire        status_invalid 
);
    // ==========================================
    // T = 0: EXCEPTION DETECT
    // ==========================================
    wire is_nan = (&in_operand_A[30:23]) && (|in_operand_A[22:0]);
    wire is_inf = (&in_operand_A[30:23]) && (~|in_operand_A[22:0]);
    wire is_zero = ~|in_operand_A[30:23];
    wire is_invalid_input = is_nan || (in_operand_A[31] && !is_zero); 
    
    wire invalid_d18, inf_d18;
    shift_reg #(.W(1), .D(18)) dly_inv (.clk(clk), .in(is_invalid_input), .out(invalid_d18));
    shift_reg #(.W(1), .D(18)) dly_inf (.clk(clk), .in(is_inf && !in_operand_A[31]), .out(inf_d18));

    // ==========================================
    // T = 0 -> 1: Tiền xử lý và Đọc ROM (12-bit)
    // ==========================================
    wire signed [8:0] e_diff = $signed({1'b0, in_operand_A[30:23]}) - 9'sd127;
    wire [7:0] k_exp = e_diff >>> 1;
    wire [31:0] w_fp = (e_diff[0]) ? {1'b0, 8'd128, in_operand_A[22:0]} : {1'b0, 8'd127, in_operand_A[22:0]};
    
    wire [31:0] y0_rom;
    pade_sqrt_rom u_rom (
        .clk(clk), 
        .addr(w_fp[22:11]),  // Truy cập 12-bit MSB của mantissa
        .data_out(y0_rom)
    );

    reg [31:0] w_d1; reg [7:0] k_d1; reg v_d1; reg e_odd_d1;
    always @(posedge clk) begin 
        w_d1 <= w_fp;
        k_d1 <= k_exp;
        v_d1 <= in_valid; 
        e_odd_d1 <= e_diff[0];
    end

    // ==========================================
    // T = 1: SCALE INITIAL GUESS VỚI GRS ROUNDING
    // ==========================================
    // Padding thêm 12-bit zero để nới rộng phân giải (Total: 36-bit)
    wire [35:0] m_y0_ext = {1'b1, y0_rom[22:0], 12'b0}; 
    
    // Hệ số ~1/sqrt(2) được nâng số hạng cho độ chính xác cao nhất
    wire [35:0] y0_scaled_odd_ext = (m_y0_ext >> 1) + (m_y0_ext >> 3) + (m_y0_ext >> 4) + 
                                    (m_y0_ext >> 6) + (m_y0_ext >> 8) + (m_y0_ext >> 14) + (m_y0_ext >> 17);
                                    
    wire [35:0] y0_scaled_ext = e_odd_d1 ? y0_scaled_odd_ext : m_y0_ext;
    
    wire shift_req = ~y0_scaled_ext[35]; // Bit 35 là phần nguyên
    
    // Trích xuất 25-bit gồm Hidden bit và 24 bit phần lẻ để làm tròn
    wire [24:0] y0_mant_raw = shift_req ? y0_scaled_ext[34:10] : y0_scaled_ext[35:11];
    
    // Trích xuất G, R, S từ các bit bị đẩy ra ngoài
    wire y0_G = shift_req ? y0_scaled_ext[9] : y0_scaled_ext[10];
    wire y0_R = shift_req ? y0_scaled_ext[8] : y0_scaled_ext[9];
    wire y0_S = shift_req ? (|y0_scaled_ext[7:0]) : (|y0_scaled_ext[8:0]);
    
    // Làm tròn RNE (Round to Nearest, ties to Even)
    wire y0_rnd = y0_G & (y0_R | y0_S | y0_mant_raw[0]);
    wire [23:0] y0_mant_final = y0_mant_raw[24:1] + y0_rnd;
    
    wire [7:0]  final_y0_exp  = y0_rom[30:23] - shift_req;
    wire [31:0] y0 = {y0_rom[31], final_y0_exp, y0_mant_final[22:0]};

    // ==========================================
    // CÁC KHỐI PIPELINE MUL/FMA GIỮ NGUYÊN (18 Stages)
    // ==========================================
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

    wire [31:0] sqrt_raw; wire v_out;
    fp_mul u_mul3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t3), 
        .in_operand_A(w_d14), .in_operand_B(y1), 
        .out_valid(v_out), .out_result(sqrt_raw),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [7:0] k_d18;
    shift_reg #(.W(8), .D(4)) dly_k18 (.clk(clk), .in(k_d14), .out(k_d18));

    wire sign_d18, z_d18;
    shift_reg #(.W(1), .D(18)) dly_sign (.clk(clk), .in(in_operand_A[31]), .out(sign_d18));
    shift_reg #(.W(1), .D(18)) dly_z (.clk(clk), .in(is_zero), .out(z_d18));

    assign out_valid = v_out;
    assign status_invalid = invalid_d18;

    assign out_result = invalid_d18 ? 32'h7FC00000 : 
                        inf_d18     ? 32'h7F800000 : 
                        z_d18       ? {sign_d18, 31'd0} : 
                                      {1'b0, sqrt_raw[30:23] + k_d18, sqrt_raw[22:0]};

endmodule