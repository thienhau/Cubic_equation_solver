`timescale 1ns / 1ps

module trigon_path #(
    parameter STAGES = 121
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
        .out_valid(v_v2), .out_result(val_2)
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
    
    // T = 40 -> 75: acos
    wire [31:0] theta; wire v_th;
    fp_acos u_acos (
        .clk(clk), .rst_n(rst_n), .in_valid(v_arg), 
        .in_operand_A(arg_val), 
        .out_valid(v_th), .out_result(theta)
    );

    // T = 75 -> 79: t1 = theta / 3
    wire [31:0] t1; wire v_t1;
    fp_mul u_mul_t1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_th), 
        .in_operand_A(theta), .in_operand_B(32'h3EAAAAAB), 
        .out_valid(v_t1), .out_result(t1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 79 -> 83: Phân tán pha (-2PI/3 và -4PI/3)
    wire [31:0] t2, t3; wire v_t2;
    fp_add_sub u_add_t2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t1), .in_is_sub(1'b0), 
        .in_operand_A(t1), .in_operand_B(32'hC0060A92), 
        .out_valid(v_t2), .out_result(t2),
        .status_overflow(), .status_zero()
    );
    
    fp_add_sub u_add_t3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t1), .in_is_sub(1'b0), 
        .in_operand_A(t1), .in_operand_B(32'hC0860A92), 
        .out_valid(), .out_result(t3),
        .status_overflow(), .status_zero()
    );
    
    // T = 79 -> 112: c1
    wire [31:0] c1; wire v_c1;
    fp_cos u_cos1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t1), 
        .in_operand_A(t1), 
        .out_valid(v_c1), .out_result(c1)
    );

    // T = 83 -> 116: c2 và c3
    wire [31:0] c2, c3; wire v_c2;
    fp_cos u_cos2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t2), 
        .in_operand_A(t2), 
        .out_valid(v_c2), .out_result(c2)
    );
    
    fp_cos u_cos3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t2), 
        .in_operand_A(t3), 
        .out_valid(), .out_result(c3)
    );

    // Đồng bộ chờ FMA ở chu kỳ T = 116
    wire [31:0] c1_dly4;
    shift_reg #(.W(32), .D(4)) dc1 (.clk(clk), .in(c1), .out(c1_dly4));

    wire [31:0] r = {val_2[31], val_2[30:23] + 8'd1, val_2[22:0]};
    wire [31:0] r_dly94; 
    shift_reg #(.W(32), .D(94)) dr94 (.clk(clk), .in(r), .out(r_dly94));
    
    wire [31:0] off_dly116;
    shift_reg #(.W(32), .D(116)) doff (.clk(clk), .in(offset), .out(off_dly116));
    wire [31:0] neg_off = {~off_dly116[31], off_dly116[30:0]};
    
    // T = 116 -> 121: Ghép r*cos - offset
    fp_fma u_fma_x1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_c2), 
        .in_operand_A(r_dly94), .in_operand_B(c1_dly4), .in_operand_C(neg_off), 
        .out_valid(out_valid), .out_result(x1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    fp_fma u_fma_x2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_c2), 
        .in_operand_A(r_dly94), .in_operand_B(c2), .in_operand_C(neg_off), 
        .out_valid(), .out_result(x2),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    fp_fma u_fma_x3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_c2), 
        .in_operand_A(r_dly94), .in_operand_B(c3), .in_operand_C(neg_off), 
        .out_valid(), .out_result(x3),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
endmodule