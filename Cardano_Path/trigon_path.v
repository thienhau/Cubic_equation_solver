`timescale 1ns / 1ps

module trigon_path #(
    parameter STAGES = 147
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] p, q, offset,
    
    output wire        out_valid,
    output wire [31:0] x1, x2, x3
);
    // T = 0 -> 4: Tính p_third và num
    wire [31:0] p_third; wire v_p3;
    fp_mul u_mul_p3 (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), 
        .in_operand_A(p), .in_operand_B(32'hBEAAAAAB), 
        .out_valid(v_p3), .out_result(p_third),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] num; wire v_num;
    fp_mul u_mul_num (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), 
        .in_operand_A(q), .in_operand_B(32'h3FC00000), 
        .out_valid(v_num), .out_result(num),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 4 -> 22: Căn val_2
    wire [31:0] val_2; wire v_v2;
    fp_sqrt u_sq_v2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_p3), 
        .in_operand_A(p_third), 
        .out_valid(v_v2), .out_result(val_2), .status_invalid()
    );

    wire [31:0] p_dly22, num_dly22;
    shift_reg #(.W(32), .D(22)) dp22 (.clk(clk), .in(p), .out(p_dly22));
    shift_reg #(.W(32), .D(22)) dn22 (.clk(clk), .in(num), .out(num_dly22));

    // T = 22 -> 26: denom = p * val_2
    wire [31:0] denom; wire v_den;
    fp_mul u_mul_den (
        .clk(clk), .rst_n(rst_n), .in_valid(v_v2), 
        .in_operand_A(p_dly22), .in_operand_B(val_2), 
        .out_valid(v_den), .out_result(denom),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 26 -> 40: arg_val
    wire [31:0] arg_val; wire v_arg;
    fp_div u_div_arg (
        .clk(clk), .rst_n(rst_n), .in_valid(v_den), 
        .in_operand_A(num_dly22), .in_operand_B(denom), 
        .out_valid(v_arg), .out_result(arg_val),
        .status_zero(), .status_invalid()
    );

    // T = 40 -> 98: acos
    wire [31:0] theta; wire v_th;
    fp_acos u_acos (
        .clk(clk), .rst_n(rst_n), .in_valid(v_arg), 
        .in_operand_A(arg_val), 
        .out_valid(v_th), .out_result(theta)
    );

    // T = 98 -> 102: t1 = theta / 3
    wire [31:0] t1; wire v_t1;
    fp_mul u_mul_t1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_th), 
        .in_operand_A(theta), .in_operand_B(32'h3EAAAAAB), 
        .out_valid(v_t1), .out_result(t1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 102 -> 106: Phân tán pha
    wire [31:0] t3;
    wire v_t3;
    fp_add_sub u_add_t3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t1), .in_is_sub(1'b1), 
        .in_operand_A(32'h3F860A92), .in_operand_B(t1), 
        .out_valid(v_t3), .out_result(t3),
        .status_overflow(), .status_invalid(), .status_zero()
    );

    // T = 102 -> 134: Tính c1 = cos(t1)
    wire [31:0] c1; wire v_c1;
    fp_cos u_cos1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t1), 
        .in_operand_A(t1), 
        .out_valid(v_c1), .out_result(c1)
    );

    // T = 106 -> 138: Tính c3 = cos(t3)
    wire [31:0] c3; wire v_c3;
    fp_cos u_cos3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t3), 
        .in_operand_A(t3), 
        .out_valid(v_c3), .out_result(c3)
    );

    // Đồng bộ c1 chờ c3 ở chu kỳ T = 138
    wire [31:0] c1_dly4;
    shift_reg #(.W(32), .D(4)) dc1 (.clk(clk), .in(c1), .out(c1_dly4));

    // T = 138 -> 142: Dùng định lý vi-ét tính c2 = c3 - c1
    wire [31:0] c2; wire v_c2;
    fp_add_sub u_sub_c2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_c3), .in_is_sub(1'b1), 
        .in_operand_A(c3), .in_operand_B(c1_dly4), 
        .out_valid(v_c2), .out_result(c2),
        .status_overflow(), .status_invalid(), .status_zero()
    );

    // Đồng bộ c1 và c3 xuống chu kỳ T = 142 để chờ c2
    wire [31:0] c1_t142, c3_t142;
    shift_reg #(.W(32), .D(4)) dc1_142 (.clk(clk), .in(c1_dly4), .out(c1_t142));
    shift_reg #(.W(32), .D(4)) dc3_142 (.clk(clk), .in(c3), .out(c3_t142));

    // Đồng bộ r và offset ở chu kỳ T = 142
    wire [31:0] r = {val_2[31], val_2[30:23] + 8'd1, val_2[22:0]};
    wire [31:0] r_dly120;
    shift_reg #(.W(32), .D(120)) dr120 (.clk(clk), .in(r), .out(r_dly120)); // 142 - 22 = 120
    
    wire [31:0] off_dly142;
    shift_reg #(.W(32), .D(142)) doff (.clk(clk), .in(offset), .out(off_dly142));
    
    wire [31:0] neg_off = {~off_dly142[31], off_dly142[30:0]};
    
    // T = 142 -> 147: Ghép r*cos - offset
    fp_fma u_fma_x1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_c2), 
        .in_operand_A(r_dly120), .in_operand_B(c1_t142), .in_operand_C(neg_off), 
        .out_valid(out_valid), .out_result(x1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    fp_fma u_fma_x2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_c2), 
        .in_operand_A(r_dly120), .in_operand_B(c2), .in_operand_C(neg_off), 
        .out_valid(), .out_result(x2),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] neg_r_dly120 = {~r_dly120[31], r_dly120[30:0]};
    
    fp_fma u_fma_x3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_c2), 
        .in_operand_A(neg_r_dly120), .in_operand_B(c3_t142), .in_operand_C(neg_off), 
        .out_valid(), .out_result(x3),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

endmodule