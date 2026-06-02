`timescale 1ns / 1ps

module radic_path #(
    parameter STAGES = 102
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] p, q, delta, offset,
    
    output wire        out_valid,
    output wire [31:0] x1_real,
    output wire [31:0] x2_real,
    output wire [31:0] x2_imag,
    output wire [31:0] x2_mag,
    output wire [31:0] x2_phase
);
    // T = 0 -> 4: Tính -q/2
    wire [31:0] neg_q = {~q[31], q[30:0]};
    wire [31:0] neg_q_half; wire v_t4;
    fp_mul u_mul_half (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), 
        .in_operand_A(neg_q), .in_operand_B(32'h3F000000), 
        .out_valid(v_t4), .out_result(neg_q_half),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 0 -> 18: Tính căn bậc 2 Delta
    wire [31:0] sqrt_d; wire v_t18;
    fp_sqrt u_sqrt_d (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), 
        .in_operand_A(delta), .out_valid(v_t18), .out_result(sqrt_d), .status_invalid()
    );

    wire [31:0] q_half_dly18;
    shift_reg #(.W(32), .D(14)) dly_q (.clk(clk), .in(neg_q_half), .out(q_half_dly18));
    wire [31:0] offset_dly52;
    shift_reg #(.W(32), .D(52)) dly_off (.clk(clk), .in(offset), .out(offset_dly52));

    // T = 18 -> 22: u_in và v_in
    wire [31:0] u_in, v_in; wire v_t22;
    fp_add_sub u_add_u (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t18), .in_is_sub(1'b0), 
        .in_operand_A(q_half_dly18), .in_operand_B(sqrt_d), 
        .out_valid(v_t22), .out_result(u_in), .status_overflow(), .status_invalid(), .status_zero()
    );
    fp_add_sub u_sub_v (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t18), .in_is_sub(1'b1), 
        .in_operand_A(q_half_dly18), .in_operand_B(sqrt_d), 
        .out_valid(), .out_result(v_in), .status_overflow(), .status_invalid(), .status_zero()
    );

    // T = 22 -> 48: Căn bậc ba u và v
    wire [31:0] u_out, v_out; wire v_t48;
    fp_cbrt u_cbrt_u (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t22), .in_operand_A(u_in), 
        .out_valid(v_t48), .out_result(u_out)
    );
    fp_cbrt u_cbrt_v (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t22), .in_operand_A(v_in), 
        .out_valid(), .out_result(v_out)
    );

    // T = 48 -> 52: Tổng và hiệu của u, v
    wire [31:0] uv_sum, uv_diff; wire v_t52;
    fp_add_sub u_add_uv (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t48), .in_is_sub(1'b0), 
        .in_operand_A(u_out), .in_operand_B(v_out), 
        .out_valid(v_t52), .out_result(uv_sum), .status_overflow(), .status_invalid(), .status_zero()
    );
    fp_add_sub u_sub_uv (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t48), .in_is_sub(1'b1), 
        .in_operand_A(u_out), .in_operand_B(v_out), 
        .out_valid(), .out_result(uv_diff), .status_overflow(), .status_invalid(), .status_zero()
    );

    // ---------------------------------------------------------
    // T = 52 -> 56: TOẠ ĐỘ ĐỀ CÁC (Real & Imaginary)
    // ---------------------------------------------------------
    wire [31:0] x1; wire v_t56;
    fp_add_sub u_add_x1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t52), .in_is_sub(1'b1), 
        .in_operand_A(uv_sum), .in_operand_B(offset_dly52), 
        .out_valid(v_t56), .out_result(x1), .status_overflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] neg_half_uv = (uv_sum == 32'd0) ? 32'd0 : {~uv_sum[31], uv_sum[30:23] - 8'd1, uv_sum[22:0]};
    wire [31:0] Re, Im;
    fp_add_sub u_add_re (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t52), .in_is_sub(1'b1), 
        .in_operand_A(neg_half_uv), .in_operand_B(offset_dly52), 
        .out_valid(), .out_result(Re), .status_overflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] abs_uv_diff = {1'b0, uv_diff[30:0]};
    fp_mul u_mul_im (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t52), 
        .in_operand_A(abs_uv_diff), .in_operand_B(32'h3F5DB3D7), // sqrt(3)/2
        .out_valid(), .out_result(Im), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // ---------------------------------------------------------
    // T = 56 -> 82: TOẠ ĐỘ CỰC - BÁN KÍNH (Magnitude)
    // ---------------------------------------------------------
    wire [31:0] re_sq, im_sq; wire v_t60;
    fp_mul u_mul_re_sq (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t56), 
        .in_operand_A(Re), .in_operand_B(Re), 
        .out_valid(v_t60), .out_result(re_sq), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    fp_mul u_mul_im_sq (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t56), 
        .in_operand_A(Im), .in_operand_B(Im), 
        .out_valid(), .out_result(im_sq), .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] sum_sq; wire v_t64;
    fp_add_sub u_add_sumsq (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t60), .in_is_sub(1'b0), 
        .in_operand_A(re_sq), .in_operand_B(im_sq), 
        .out_valid(v_t64), .out_result(sum_sq), .status_overflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] Mag_raw; wire v_t82;
    fp_sqrt u_sqrt_mag (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t64), 
        .in_operand_A(sum_sq), .out_valid(v_t82), .out_result(Mag_raw), .status_invalid()
    );

    // ---------------------------------------------------------
    // T = 56 -> 102: TOẠ ĐỘ CỰC - GÓC (Phase)
    // ---------------------------------------------------------
    wire [31:0] abs_Re = {1'b0, Re[30:0]};
    wire is_gt = (Im[30:0] > abs_Re[30:0]); // Tránh tràn số chia atan
    
    wire [31:0] div_num = is_gt ? abs_Re : Im;
    wire [31:0] div_den = is_gt ? Im : abs_Re;
    wire [31:0] ratio; wire v_t70;
    fp_div u_div_ratio (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t56), 
        .in_operand_A(div_num), .in_operand_B(div_den), 
        .out_valid(v_t70), .out_result(ratio), .status_zero(), .status_invalid()
    );

    wire [31:0] atan_val; wire v_t98;
    fp_atan u_atan_phase (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t70), 
        .in_operand_A(ratio), .out_valid(v_t98), .out_result(atan_val)
    );

    wire is_gt_d98, re_sign_d98;
    shift_reg #(.W(1), .D(42)) dly_is_gt (.clk(clk), .in(is_gt), .out(is_gt_d98));
    shift_reg #(.W(1), .D(42)) dly_re_sign (.clk(clk), .in(Re[31]), .out(re_sign_d98));

    // Bộ ánh xạ tự động góc Phase theo đúng Quadrant
    wire [31:0] phase_A = is_gt_d98 ? 32'h3FC90FDB : (re_sign_d98 ? 32'h40490FDB : 32'd0); // PI/2 hoặc PI
    wire phase_is_sub = is_gt_d98 ^ re_sign_d98;
    wire [31:0] Phase_out; wire v_t102;
    fp_add_sub u_add_phase (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t98), .in_is_sub(phase_is_sub), 
        .in_operand_A(phase_A), .in_operand_B(atan_val), 
        .out_valid(v_t102), .out_result(Phase_out), .status_overflow(), .status_invalid(), .status_zero()
    );

    // ---------------------------------------------------------
    // ĐỒNG BỘ HOÁ ĐẦU RA TẠI T = 102
    // ---------------------------------------------------------
    shift_reg #(.W(32), .D(46)) dly_x1 (.clk(clk), .in(x1), .out(x1_real));
    shift_reg #(.W(32), .D(46)) dly_re (.clk(clk), .in(Re), .out(x2_real));
    shift_reg #(.W(32), .D(46)) dly_im (.clk(clk), .in(Im), .out(x2_imag));
    shift_reg #(.W(32), .D(20)) dly_mag (.clk(clk), .in(Mag_raw), .out(x2_mag));

    assign x2_phase  = Phase_out;
    assign out_valid = v_t102;

endmodule