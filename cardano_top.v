`timescale 1ns / 1ps

module cardano_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [31:0] a, b, c, d,
    
    output wire        valid_out,
    output wire [1:0]  num_roots,
    output wire [31:0] x1, x2, x3
);
    // 1. Phân loại cấu hình từ đầu vào
    wire is_quad = (a == 32'h00000000);

    // -------------------------------------------------------------
    // KHỐI TIỀN XỬ LÝ (Pre-processing: Tính p, q, Delta, offset)
    // Pipeline dài 52 Chu kỳ (Đồng bộ mọi tín hiệu về T=52)
    // -------------------------------------------------------------
    wire v52;
    shift_reg #(1, 52) dly_v (.clk(clk), .in(valid_in), .out(v52));
    
    wire is_quad_52;
    shift_reg #(1, 52) dly_q (.clk(clk), .in(is_quad), .out(is_quad_52));
    
    wire [31:0] b_52, c_52, d_52;
    shift_reg #(32, 52) dly_b52 (.clk(clk), .in(b), .out(b_52));
    shift_reg #(32, 52) dly_c52 (.clk(clk), .in(c), .out(c_52));
    shift_reg #(32, 52) dly_d52 (.clk(clk), .in(d), .out(d_52));

    // T=0 -> T=14: inv_a = 1.0 / a
    wire [31:0] inv_a; wire v14;
    fp_div u_div_a (.clk(clk), .rst_n(rst_n), .in_valid(valid_in), .in_operand_A(32'h3F800000), .in_operand_B(a), .out_valid(v14), .out_result(inv_a));
    
    wire [31:0] b14, c14, d14;
    shift_reg #(32, 14) d14_b (.clk(clk), .in(b), .out(b14));
    shift_reg #(32, 14) d14_c (.clk(clk), .in(c), .out(c14));
    shift_reg #(32, 14) d14_d (.clk(clk), .in(d), .out(d14));

    // T=14 -> T=18: A = b/a, B = c/a, C = d/a
    wire [31:0] A_coef, B_coef, C_coef; wire v18;
    fp_mul u_mul_A (.clk(clk), .rst_n(rst_n), .in_valid(v14), .in_operand_A(b14), .in_operand_B(inv_a), .out_valid(v18), .out_result(A_coef));
    fp_mul u_mul_B (.clk(clk), .rst_n(rst_n), .in_valid(v14), .in_operand_A(c14), .in_operand_B(inv_a), .out_valid(), .out_result(B_coef));
    fp_mul u_mul_C (.clk(clk), .rst_n(rst_n), .in_valid(v14), .in_operand_A(d14), .in_operand_B(inv_a), .out_valid(), .out_result(C_coef));

    // T=18 -> T=20: S = A / 3 (offset)
    wire [31:0] S_val; wire v20;
    fp_mul_const_one_third u_mul_S (.clk(clk), .rst_n(rst_n), .in_valid(v18), .in_operand_A(A_coef), .out_valid(v20), .out_result(S_val));
    
    wire [31:0] B20, C20;
    shift_reg #(32, 2) d20_B (.clk(clk), .in(B_coef), .out(B20));
    shift_reg #(32, 2) d20_C (.clk(clk), .in(C_coef), .out(C20));

    // T=20 -> T=24: S2 = S*S, SB = S*B
    wire [31:0] S2, SB; wire v24;
    fp_mul u_mul_S2 (.clk(clk), .rst_n(rst_n), .in_valid(v20), .in_operand_A(S_val), .in_operand_B(S_val), .out_valid(v24), .out_result(S2));
    fp_mul u_mul_SB (.clk(clk), .rst_n(rst_n), .in_valid(v20), .in_operand_A(S_val), .in_operand_B(B20), .out_valid(), .out_result(SB));
    
    wire [31:0] S24, B24, C24;
    shift_reg #(32, 4) d24_S (.clk(clk), .in(S_val), .out(S24));
    shift_reg #(32, 4) d24_B (.clk(clk), .in(B20), .out(B24));
    shift_reg #(32, 4) d24_C (.clk(clk), .in(C20), .out(C24));

    // T=24 -> T=28: S3 = S2*S, mul_3S2 = S2*3.0, C_minus_SB = C - SB
    wire [31:0] S3, mul_3S2, C_minus_SB; wire v28;
    fp_mul u_mul_S3 (.clk(clk), .rst_n(rst_n), .in_valid(v24), .in_operand_A(S2), .in_operand_B(S24), .out_valid(v28), .out_result(S3));
    fp_mul u_mul_3S2 (.clk(clk), .rst_n(rst_n), .in_valid(v24), .in_operand_A(S2), .in_operand_B(32'h40400000), .out_valid(), .out_result(mul_3S2));
    fp_add_sub u_sub_C_SB (.clk(clk), .rst_n(rst_n), .in_valid(v24), .in_is_sub(1'b1), .in_operand_A(C24), .in_operand_B(SB), .out_valid(), .out_result(C_minus_SB));
    
    wire [31:0] B28;
    shift_reg #(32, 4) d28_B (.clk(clk), .in(B24), .out(B28));

    // T=28 -> T=32: p_val_int = B - 3S2, mul_2S3 = S3*2.0
    wire [31:0] p_val_int, mul_2S3; wire v32;
    fp_add_sub u_sub_p (.clk(clk), .rst_n(rst_n), .in_valid(v28), .in_is_sub(1'b1), .in_operand_A(B28), .in_operand_B(mul_3S2), .out_valid(v32), .out_result(p_val_int));
    fp_mul u_mul_2S3 (.clk(clk), .rst_n(rst_n), .in_valid(v28), .in_operand_A(S3), .in_operand_B(32'h40000000), .out_valid(), .out_result(mul_2S3));
    
    wire [31:0] C_minus_SB32;
    shift_reg #(32, 4) d32_C_SB (.clk(clk), .in(C_minus_SB), .out(C_minus_SB32));

    // T=32 -> T=36: q_val_int = 2S3 + C_minus_SB
    wire [31:0] q_val_int; wire v36;
    fp_add_sub u_add_q (.clk(clk), .rst_n(rst_n), .in_valid(v32), .in_is_sub(1'b0), .in_operand_A(mul_2S3), .in_operand_B(C_minus_SB32), .out_valid(v36), .out_result(q_val_int));
    
    // T=32 -> T=34: p_3 = p / 3
    wire [31:0] p_3; wire v34;
    fp_mul_const_one_third u_mul_p3 (.clk(clk), .rst_n(rst_n), .in_valid(v32), .in_operand_A(p_val_int), .out_valid(v34), .out_result(p_3));
    
    wire [31:0] p_3_36;
    shift_reg #(32, 2) d36_p3 (.clk(clk), .in(p_3), .out(p_3_36));

    // T=36 -> T=40: q_2 = q * 0.5
    wire [31:0] q_2; wire v40;
    fp_mul u_mul_q2 (.clk(clk), .rst_n(rst_n), .in_valid(v36), .in_operand_A(q_val_int), .in_operand_B(32'h3F000000), .out_valid(v40), .out_result(q_2));
    
    wire [31:0] p_3_40;
    shift_reg #(32, 4) d40_p3 (.clk(clk), .in(p_3_36), .out(p_3_40));

    // T=40 -> T=44: q_2_sq = q_2^2, p_3_sq = p_3^2
    wire [31:0] q_2_sq, p_3_sq; wire v44;
    fp_mul u_mul_q2_sq (.clk(clk), .rst_n(rst_n), .in_valid(v40), .in_operand_A(q_2), .in_operand_B(q_2), .out_valid(v44), .out_result(q_2_sq));
    fp_mul u_mul_p3_sq (.clk(clk), .rst_n(rst_n), .in_valid(v40), .in_operand_A(p_3_40), .in_operand_B(p_3_40), .out_valid(), .out_result(p_3_sq));
    
    wire [31:0] p_3_44;
    shift_reg #(32, 4) d44_p3 (.clk(clk), .in(p_3_40), .out(p_3_44));

    // T=44 -> T=48: p_3_cb = p_3_sq * p_3
    wire [31:0] p_3_cb; wire v48;
    fp_mul u_mul_p3_cb (.clk(clk), .rst_n(rst_n), .in_valid(v44), .in_operand_A(p_3_sq), .in_operand_B(p_3_44), .out_valid(v48), .out_result(p_3_cb));
    
    wire [31:0] q_2_sq_48;
    shift_reg #(32, 4) d48_q2_sq (.clk(clk), .in(q_2_sq), .out(q_2_sq_48));

    // T=48 -> T=52: delta_val_int = q_2_sq + p_3_cb
    wire [31:0] delta_val_int; wire v52_delta;
    fp_add_sub u_add_delta (.clk(clk), .rst_n(rst_n), .in_valid(v48), .in_is_sub(1'b0), .in_operand_A(q_2_sq_48), .in_operand_B(p_3_cb), .out_valid(v52_delta), .out_result(delta_val_int));
    
    // Assign ra kết quả sau cùng tại T=52
    wire pre_valid_out = v52;
    wire [31:0] p_val, q_val, delta_val, offset_val;
    
    shift_reg #(32, 20) d52_p (.clk(clk), .in(p_val_int), .out(p_val));
    shift_reg #(32, 16) d52_q (.clk(clk), .in(q_val_int), .out(q_val));
    shift_reg #(32, 32) d52_off (.clk(clk), .in(S_val), .out(offset_val));
    
    assign delta_val = delta_val_int;
    wire delta_is_pos = (delta_val[31] == 1'b0);

    // -------------------------------------------------------------
    // SYNC FIFO BYPASS
    // -------------------------------------------------------------
    wire fifo_push = pre_valid_out;
    wire fifo_pop; 
    wire [1:0] meta_in = {is_quad_52, delta_is_pos};
    wire [1:0] meta_out;

    sync_fifo_bypass #(.DATA_WIDTH(2), .DEPTH_LOG2(5)) u_bypass_fifo (
        .clk(clk), .rst_n(rst_n),
        .push(fifo_push), .pop(fifo_pop),
        .data_in(meta_in), .data_out(meta_out),
        .empty(), .full()
    );

    wire out_is_quad      = meta_out[1];
    wire out_delta_is_pos = meta_out[0];

    // -------------------------------------------------------------
    // ĐỊNH TUYẾN SANG CÁC NHÁNH
    // -------------------------------------------------------------
    wire en_quad   = pre_valid_out & is_quad_52;
    wire en_radic  = pre_valid_out & ~is_quad_52 & delta_is_pos;
    wire en_trigon = pre_valid_out & ~is_quad_52 & ~delta_is_pos;

    // Nhánh 1: Bậc 2
    wire v_quad; wire [31:0] q_x1, q_x2;
    quad_path U_QUAD (
        .clk(clk), .rst_n(rst_n), .in_valid(en_quad),
        .b(b_52), .c(c_52), .d(d_52),
        .out_valid(v_quad), .x1(q_x1), .x2(q_x2)
    );

    // Nhánh 2: Bậc 3 (Delta > 0)
    wire v_radic; wire [31:0] r_x1;
    radic_path U_RADI (
        .clk(clk), .rst_n(rst_n), .in_valid(en_radic),
        .p(p_val), .q(q_val), .delta(delta_val), .offset(offset_val),
        .out_valid(v_radic), .x1(r_x1)
    );

    // Nhánh 3: Bậc 3 (Delta <= 0)
    wire v_trigon; wire [31:0] t_x1, t_x2, t_x3;
    trigon_path U_TRIG (
        .clk(clk), .rst_n(rst_n), .in_valid(en_trigon),
        .p(p_val), .q(q_val), .offset(offset_val),
        .out_valid(v_trigon), .x1(t_x1), .x2(t_x2), .x3(t_x3)
    );

    // -------------------------------------------------------------
    // GOM NGHIỆM VÀ POP FIFO
    // -------------------------------------------------------------
    assign valid_out = v_quad | v_radic | v_trigon;
    assign fifo_pop  = valid_out; 

    assign num_roots = out_is_quad ? 2'd2 : (out_delta_is_pos ? 2'd1 : 2'd3);

    assign x1 = out_is_quad ? q_x1 : (out_delta_is_pos ? r_x1 : t_x1);
    assign x2 = out_is_quad ? q_x2 : (out_delta_is_pos ? 32'h0 : t_x2);
    assign x3 = out_is_quad ? 32'h0 : (out_delta_is_pos ? 32'h0 : t_x3);

endmodule