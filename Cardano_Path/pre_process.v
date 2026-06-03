`timescale 1ns / 1ps

module pre_process #(
    parameter STAGES = 52
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [7:0]  trans_id_in,
    input  wire [31:0] a, b, c, d,
    
    output wire        valid_out,
    output wire [7:0]  trans_id_out,
    output wire        is_quad_out,
    output wire        delta_is_pos_out,
    
    output wire [31:0] b_out, c_out, d_out,
    output wire [31:0] p_out, q_out, delta_out, offset_out
);

    // T = 0 -> 0: Phân loại hệ số
    wire is_quad = (a == 32'h00000000);

    // T = 0 -> 52: Delay cờ điều khiển valid_in và is_quad
    shift_reg #(.W(1), .D(52)) dly_v (.clk(clk), .in(valid_in), .out(valid_out));
    shift_reg #(.W(1), .D(52)) dly_q (.clk(clk), .in(is_quad), .out(is_quad_out));
    
    // T = 0 -> 52: Trượt thẻ ID theo khối Pre-process
    shift_reg #(.W(8), .D(52)) dly_id_pre (.clk(clk), .in(trans_id_in), .out(trans_id_out));
    
    // T = 0 -> 52: Delay hệ số b, c, d
    shift_reg #(.W(32), .D(52)) dly_b52 (.clk(clk), .in(b), .out(b_out));
    shift_reg #(.W(32), .D(52)) dly_c52 (.clk(clk), .in(c), .out(c_out));
    shift_reg #(.W(32), .D(52)) dly_d52 (.clk(clk), .in(d), .out(d_out));

    // T = 0 -> 14: Khối tính 1/a
    wire [31:0] inv_a; wire v14;
    fp_div u_div_a (.clk(clk), .rst_n(rst_n), .in_valid(valid_in), .in_operand_A(32'h3F800000), .in_operand_B(a), .out_valid(v14), .out_result(inv_a), .status_zero(), .status_invalid());

    // T = 0 -> 14: Delay hệ số chờ chia
    wire [31:0] b14, c14, d14;
    shift_reg #(.W(32), .D(14)) d14_b (.clk(clk), .in(b), .out(b14));
    shift_reg #(.W(32), .D(14)) d14_c (.clk(clk), .in(c), .out(c14));
    shift_reg #(.W(32), .D(14)) d14_d (.clk(clk), .in(d), .out(d14));

    // T = 14 -> 18: Khối A, B, C
    wire [31:0] A_coef, B_coef, C_coef; wire v18;
    fp_mul u_mul_A (.clk(clk), .rst_n(rst_n), .in_valid(v14), .in_operand_A(b14), .in_operand_B(inv_a), .out_valid(v18), .out_result(A_coef), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero());
    fp_mul u_mul_B (.clk(clk), .rst_n(rst_n), .in_valid(v14), .in_operand_A(c14), .in_operand_B(inv_a), .out_valid(), .out_result(B_coef), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero());
    fp_mul u_mul_C (.clk(clk), .rst_n(rst_n), .in_valid(v14), .in_operand_A(d14), .in_operand_B(inv_a), .out_valid(), .out_result(C_coef), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero());

    // T = 18 -> 20: Khối S
    wire [31:0] S_val; wire v20;
    fp_mul_const_one_third u_mul_S (.clk(clk), .rst_n(rst_n), .in_valid(v18), .in_operand_A(A_coef), .out_valid(v20), .out_result(S_val));

    // T = 18 -> 20: Delay B, C
    wire [31:0] B20, C20;
    shift_reg #(.W(32), .D(2)) d20_B (.clk(clk), .in(B_coef), .out(B20));
    shift_reg #(.W(32), .D(2)) d20_C (.clk(clk), .in(C_coef), .out(C20));

    // T = 20 -> 24: Khối S2, SB
    wire [31:0] S2, SB; wire v24;
    fp_mul u_mul_S2 (.clk(clk), .rst_n(rst_n), .in_valid(v20), .in_operand_A(S_val), .in_operand_B(S_val), .out_valid(v24), .out_result(S2), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero());
    fp_mul u_mul_SB (.clk(clk), .rst_n(rst_n), .in_valid(v20), .in_operand_A(S_val), .in_operand_B(B20), .out_valid(), .out_result(SB), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero());

    // T = 20 -> 24: Delay S, B, C
    wire [31:0] S24, B24, C24;
    shift_reg #(.W(32), .D(4)) d24_S (.clk(clk), .in(S_val), .out(S24));
    shift_reg #(.W(32), .D(4)) d24_B (.clk(clk), .in(B20), .out(B24));
    shift_reg #(.W(32), .D(4)) d24_C (.clk(clk), .in(C20), .out(C24));

    // T = 24 -> 28: Khối S3, 3S2, C-SB
    wire [31:0] S3, mul_3S2, C_minus_SB; wire v28;
    fp_mul u_mul_S3 (.clk(clk), .rst_n(rst_n), .in_valid(v24), .in_operand_A(S2), .in_operand_B(S24), .out_valid(v28), .out_result(S3), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero());
    fp_mul u_mul_3S2 (.clk(clk), .rst_n(rst_n), .in_valid(v24), .in_operand_A(S2), .in_operand_B(32'h40400000), .out_valid(), .out_result(mul_3S2), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero());
    fp_add_sub u_sub_C_SB (.clk(clk), .rst_n(rst_n), .in_valid(v24), .in_is_sub(1'b1), .in_operand_A(C24), .in_operand_B(SB), .out_valid(), .out_result(C_minus_SB), .status_overflow(), .status_invalid(), .status_zero());

    // T = 24 -> 28: Delay B
    wire [31:0] B28;
    shift_reg #(.W(32), .D(4)) d28_B (.clk(clk), .in(B24), .out(B28));

    // T = 28 -> 32: Khối p, 2S3
    wire [31:0] p_val_int, mul_2S3; wire v32;
    fp_add_sub u_sub_p (.clk(clk), .rst_n(rst_n), .in_valid(v28), .in_is_sub(1'b1), .in_operand_A(B28), .in_operand_B(mul_3S2), .out_valid(v32), .out_result(p_val_int), .status_overflow(), .status_invalid(), .status_zero());
    fp_mul u_mul_2S3 (.clk(clk), .rst_n(rst_n), .in_valid(v28), .in_operand_A(S3), .in_operand_B(32'h40000000), .out_valid(), .out_result(mul_2S3), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero());
    
    // T = 28 -> 32: Delay C_minus_SB
    wire [31:0] C_minus_SB32;
    shift_reg #(.W(32), .D(4)) d32_C_SB (.clk(clk), .in(C_minus_SB), .out(C_minus_SB32));

    // T = 32 -> 36: Khối q
    wire [31:0] q_val_int; wire v36;
    fp_add_sub u_add_q (.clk(clk), .rst_n(rst_n), .in_valid(v32), .in_is_sub(1'b0), .in_operand_A(mul_2S3), .in_operand_B(C_minus_SB32), .out_valid(v36), .out_result(q_val_int), .status_overflow(), .status_invalid(), .status_zero());

    // T = 32 -> 34: Khối p/3
    wire [31:0] p_3; wire v34;
    fp_mul_const_one_third u_mul_p3 (.clk(clk), .rst_n(rst_n), .in_valid(v32), .in_operand_A(p_val_int), .out_valid(v34), .out_result(p_3));
    
    // T = 34 -> 36: Delay p/3
    wire [31:0] p_3_36;
    shift_reg #(.W(32), .D(2)) d36_p3 (.clk(clk), .in(p_3), .out(p_3_36));

    // T = 36 -> 40: Khối q/2
    wire [31:0] q_2; wire v40;
    fp_mul u_mul_q2 (.clk(clk), .rst_n(rst_n), .in_valid(v36), .in_operand_A(q_val_int), .in_operand_B(32'h3F000000), .out_valid(v40), .out_result(q_2), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero());

    // T = 36 -> 40: Delay p/3
    wire [31:0] p_3_40;
    shift_reg #(.W(32), .D(4)) d40_p3 (.clk(clk), .in(p_3_36), .out(p_3_40));

    // T = 40 -> 44: Khối (q/2)^2 và (p/3)^2
    wire [31:0] q_2_sq, p_3_sq; wire v44;
    fp_mul u_mul_q2_sq (.clk(clk), .rst_n(rst_n), .in_valid(v40), .in_operand_A(q_2), .in_operand_B(q_2), .out_valid(v44), .out_result(q_2_sq), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero());
    fp_mul u_mul_p3_sq (.clk(clk), .rst_n(rst_n), .in_valid(v40), .in_operand_A(p_3_40), .in_operand_B(p_3_40), .out_valid(), .out_result(p_3_sq), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero());

    // T = 40 -> 44: Delay p/3
    wire [31:0] p_3_44;
    shift_reg #(.W(32), .D(4)) d44_p3 (.clk(clk), .in(p_3_40), .out(p_3_44));

    // T = 44 -> 48: Khối (p/3)^3
    wire [31:0] p_3_cb; wire v48;
    fp_mul u_mul_p3_cb (.clk(clk), .rst_n(rst_n), .in_valid(v44), .in_operand_A(p_3_sq), .in_operand_B(p_3_44), .out_valid(v48), .out_result(p_3_cb), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero());

    // T = 44 -> 48: Delay (q/2)^2
    wire [31:0] q_2_sq_48;
    shift_reg #(.W(32), .D(4)) d48_q2_sq (.clk(clk), .in(q_2_sq), .out(q_2_sq_48));

    // T = 48 -> 52: Khối Delta
    wire [31:0] delta_val_int; wire v52_delta;
    fp_add_sub u_add_delta (.clk(clk), .rst_n(rst_n), .in_valid(v48), .in_is_sub(1'b0), .in_operand_A(q_2_sq_48), .in_operand_B(p_3_cb), .out_valid(v52_delta), .out_result(delta_val_int), .status_overflow(), .status_invalid(), .status_zero());

    // T = 32 -> 52: Delay p
    shift_reg #(.W(32), .D(20)) d52_p (.clk(clk), .in(p_val_int), .out(p_out));
    
    // T = 36 -> 52: Delay q
    shift_reg #(.W(32), .D(16)) d52_q (.clk(clk), .in(q_val_int), .out(q_out));
    
    // T = 20 -> 52: Delay offset
    shift_reg #(.W(32), .D(32)) d52_off (.clk(clk), .in(S_val), .out(offset_out));
    
    // T = 52 -> 52: Xác định dấu của Delta
    assign delta_out = delta_val_int;
    wire delta_is_zero = (delta_val_int[30:0] == 31'd0);
    assign delta_is_pos_out = (delta_val_int[31] == 1'b0) & ~delta_is_zero;

endmodule