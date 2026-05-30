`timescale 1ns / 1ps

module cardano_top #(
    parameter PRE_PROCESS_STAGES = 52
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [7:0]  trans_id_in,
    input  wire [31:0] a, b, c, d,
    
    output wire        valid_out,
    output wire [7:0]  trans_id_out,
    output wire [1:0]  num_roots,
    output wire [31:0] x1, x2, x3,
    // PORT BỔ SUNG CHO NGHIỆM PHỨC
    output wire [31:0] x2_imag, x3_imag,
    output wire [31:0] x2_mag,  x3_mag,
    output wire [31:0] x2_phase, x3_phase
);
    // T = 0 -> 0: Phân loại hệ số
    wire is_quad = (a == 32'h00000000);

    // T = 0 -> 52: Delay cờ điều khiển valid_in và is_quad
    wire v52;
    shift_reg #(.W(1), .D(52)) dly_v (.clk(clk), .in(valid_in), .out(v52));
    wire is_quad_52;
    shift_reg #(.W(1), .D(52)) dly_q (.clk(clk), .in(is_quad), .out(is_quad_52));
    
    // T = 0 -> 52: Trượt thẻ ID theo khối Pre-process
    wire [7:0] id_52;
    shift_reg #(.W(8), .D(52)) dly_id_pre (.clk(clk), .in(trans_id_in), .out(id_52));
    
    // T = 0 -> 52: Delay hệ số b, c, d
    wire [31:0] b_52, c_52, d_52;
    shift_reg #(.W(32), .D(52)) dly_b52 (.clk(clk), .in(b), .out(b_52));
    shift_reg #(.W(32), .D(52)) dly_c52 (.clk(clk), .in(c), .out(c_52));
    shift_reg #(.W(32), .D(52)) dly_d52 (.clk(clk), .in(d), .out(d_52));

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
    fp_mul_const u_mul_S (.clk(clk), .rst_n(rst_n), .in_valid(v18), .in_operand_A(A_coef), .out_valid(v20), .out_result(S_val));

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
    fp_add_sub u_sub_C_SB (.clk(clk), .rst_n(rst_n), .in_valid(v24), .in_is_sub(1'b1), .in_operand_A(C24), .in_operand_B(SB), .out_valid(), .out_result(C_minus_SB), .status_overflow(), .status_zero());

    // T = 24 -> 28: Delay B
    wire [31:0] B28;
    shift_reg #(.W(32), .D(4)) d28_B (.clk(clk), .in(B24), .out(B28));

    // T = 28 -> 32: Khối p, 2S3
    wire [31:0] p_val_int, mul_2S3; wire v32;
    fp_add_sub u_sub_p (.clk(clk), .rst_n(rst_n), .in_valid(v28), .in_is_sub(1'b1), .in_operand_A(B28), .in_operand_B(mul_3S2), .out_valid(v32), .out_result(p_val_int), .status_overflow(), .status_zero());
    fp_mul u_mul_2S3 (.clk(clk), .rst_n(rst_n), .in_valid(v28), .in_operand_A(S3), .in_operand_B(32'h40000000), .out_valid(), .out_result(mul_2S3), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero());
    
    // T = 28 -> 32: Delay C_minus_SB
    wire [31:0] C_minus_SB32;
    shift_reg #(.W(32), .D(4)) d32_C_SB (.clk(clk), .in(C_minus_SB), .out(C_minus_SB32));

    // T = 32 -> 36: Khối q
    wire [31:0] q_val_int; wire v36;
    fp_add_sub u_add_q (.clk(clk), .rst_n(rst_n), .in_valid(v32), .in_is_sub(1'b0), .in_operand_A(mul_2S3), .in_operand_B(C_minus_SB32), .out_valid(v36), .out_result(q_val_int), .status_overflow(), .status_zero());

    // T = 32 -> 34: Khối p/3
    wire [31:0] p_3; wire v34;
    fp_mul_const u_mul_p3 (.clk(clk), .rst_n(rst_n), .in_valid(v32), .in_operand_A(p_val_int), .out_valid(v34), .out_result(p_3));
    
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
    fp_add_sub u_add_delta (.clk(clk), .rst_n(rst_n), .in_valid(v48), .in_is_sub(1'b0), .in_operand_A(q_2_sq_48), .in_operand_B(p_3_cb), .out_valid(v52_delta), .out_result(delta_val_int), .status_overflow(), .status_zero());

    // T = 32 -> 52: Delay p
    wire pre_valid_out = v52;
    wire [31:0] p_val;
    shift_reg #(.W(32), .D(20)) d52_p (.clk(clk), .in(p_val_int), .out(p_val));
    
    // T = 36 -> 52: Delay q
    wire [31:0] q_val;
    shift_reg #(.W(32), .D(16)) d52_q (.clk(clk), .in(q_val_int), .out(q_val));
    
    // T = 20 -> 52: Delay offset
    wire [31:0] offset_val;
    shift_reg #(.W(32), .D(32)) d52_off (.clk(clk), .in(S_val), .out(offset_val));
    
    // T = 52 -> 52: Xác định dấu của Delta
    wire [31:0] delta_val = delta_val_int;
    wire delta_is_zero = (delta_val[30:0] == 31'd0);
    wire delta_is_pos = (delta_val[31] == 1'b0) & ~delta_is_zero;

    // T = 52 -> *: FIFO Bypass Metadata định tuyến nhánh
    wire fifo_push = pre_valid_out;
    wire fifo_pop; 
    wire [1:0] meta_in = {is_quad_52, delta_is_pos};
    wire [1:0] meta_out;

    sync_fifo_bypass #(.DATA_WIDTH(2), .DEPTH_LOG2(5)) u_bypass_fifo (
        .clk(clk), .rst_n(rst_n), .push(fifo_push), .pop(fifo_pop),
        .data_in(meta_in), .data_out(meta_out),
        .empty(), .full()
    );

    wire out_is_quad      = meta_out[1];
    wire out_delta_is_pos = meta_out[0];

    wire en_quad   = pre_valid_out & is_quad_52;
    wire en_radic  = pre_valid_out & ~is_quad_52 & delta_is_pos;
    wire en_trigon = pre_valid_out & ~is_quad_52 & ~delta_is_pos;

    assign fifo_pop = pre_valid_out;
    
    // T = 52 -> 100: Nhánh 1 Bậc 2 (48 Chu kỳ)
    wire v_quad;
    wire [31:0] q_x1, q_x2;
    quad_path u_quad (.clk(clk), .rst_n(rst_n), .in_valid(en_quad), .b(b_52), .c(c_52), .d(d_52), .out_valid(v_quad), .x1(q_x1), .x2(q_x2));
    
    wire [7:0] id_quad_out;
    shift_reg #(.W(8), .D(48)) dly_id_q (.clk(clk), .in(id_52), .out(id_quad_out));

    // T = 52 -> 154: Nhánh 2 Radic NÂNG CẤP TỌA ĐỘ PHỨC (102 Chu kỳ)
    wire v_radic;
    wire [31:0] r_x1, r_x2_real, r_x2_imag, r_x2_mag, r_x2_phase;
    radic_path u_radic (
        .clk(clk), .rst_n(rst_n), .in_valid(en_radic), 
        .p(p_val), .q(q_val), .delta(delta_val), .offset(offset_val), 
        .out_valid(v_radic), 
        .x1_real(r_x1), .x2_real(r_x2_real), .x2_imag(r_x2_imag), 
        .x2_mag(r_x2_mag), .x2_phase(r_x2_phase)
    );
    
    wire [7:0] id_radic_out;
    // CẬP NHẬT TRỄ ID THÀNH 102
    shift_reg #(.W(8), .D(102)) dly_id_r (.clk(clk), .in(id_52), .out(id_radic_out));

    // T = 52 -> 173: Nhánh 3 Trigon (121 Chu kỳ)
    wire v_trigon;
    wire [31:0] t_x1, t_x2, t_x3;
    trigon_path u_trigon (.clk(clk), .rst_n(rst_n), .in_valid(en_trigon), .p(p_val), .q(q_val), .offset(offset_val), .out_valid(v_trigon), .x1(t_x1), .x2(t_x2), .x3(t_x3));
    
    wire [7:0] id_trigon_out;
    shift_reg #(.W(8), .D(121)) dly_id_t (.clk(clk), .in(id_52), .out(id_trigon_out));

    // T = * -> *: Bộ trọng tài Out-of-Order CẬP NHẬT ĐỘ RỘNG THÀNH 202 BITS
    wire quad_empty, radic_empty, trigon_empty;
    wire [201:0] quad_data_out, radic_data_out, trigon_data_out;
    wire pop_quad, pop_radic, pop_trigon;

    sync_fifo_bypass #(.DATA_WIDTH(202), .DEPTH_LOG2(4)) fifo_quad (
        .clk(clk), .rst_n(rst_n), .push(v_quad), .pop(pop_quad),
        .data_in({id_quad_out, 2'd2, q_x1, q_x2, 32'd0, 32'd0, 32'd0, 32'd0}), .data_out(quad_data_out), .empty(quad_empty), .full()
    );
    sync_fifo_bypass #(.DATA_WIDTH(202), .DEPTH_LOG2(4)) fifo_radic (
        .clk(clk), .rst_n(rst_n), .push(v_radic), .pop(pop_radic),
        .data_in({id_radic_out, 2'd1, r_x1, r_x2_real, r_x2_real, r_x2_imag, r_x2_mag, r_x2_phase}), .data_out(radic_data_out), .empty(radic_empty), .full()
    );
    sync_fifo_bypass #(.DATA_WIDTH(202), .DEPTH_LOG2(4)) fifo_trigon (
        .clk(clk), .rst_n(rst_n), .push(v_trigon), .pop(pop_trigon),
        .data_in({id_trigon_out, 2'd3, t_x1, t_x2, t_x3, 32'd0, 32'd0, 32'd0}), .data_out(trigon_data_out), .empty(trigon_empty), .full()
    );

    // Arbiter
    assign pop_quad   = !quad_empty;
    assign pop_radic  = !quad_empty ? 1'b0 : !radic_empty;
    assign pop_trigon = (!quad_empty || !radic_empty) ? 1'b0 : !trigon_empty;

    assign valid_out = pop_quad | pop_radic | pop_trigon;

    wire [201:0] final_data = pop_quad ? quad_data_out : (pop_radic ? radic_data_out : trigon_data_out);

    // MÁP LẠI TÍN HIỆU ĐẦU RA (Un-packing 202 bits)
    assign trans_id_out = final_data[201:194];
    assign num_roots    = final_data[193:192];
    assign x1           = final_data[191:160];
    assign x2           = final_data[159:128];
    assign x3           = final_data[127:96];
    
    wire [31:0] b_img   = final_data[95:64];
    wire [31:0] b_mag   = final_data[63:32];
    wire [31:0] b_phs   = final_data[31:0];

    // Tạo các liên hợp phức nếu là nhánh 1 nghiệm (Radic)
    assign x2_imag  = (num_roots == 2'd1) ? b_img : 32'd0;
    assign x3_imag  = (num_roots == 2'd1) ? {~b_img[31], b_img[30:0]} : 32'd0; // Đảo dấu liên hợp
    assign x2_mag   = (num_roots == 2'd1) ? b_mag : 32'd0;
    assign x3_mag   = (num_roots == 2'd1) ? b_mag : 32'd0; // Bán kính không đổi
    assign x2_phase = (num_roots == 2'd1) ? b_phs : 32'd0;
    assign x3_phase = (num_roots == 2'd1) ? {~b_phs[31], b_phs[30:0]} : 32'd0; // Góc liên hợp âm

endmodule