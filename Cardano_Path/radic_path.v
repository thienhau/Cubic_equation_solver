`timescale 1ns / 1ps

module radic_path #(
    parameter STAGES = 56
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] p, q, delta, offset,
    
    output wire        out_valid,
    output wire [31:0] x1
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
        .in_operand_A(delta), 
        .out_valid(v_t18), .out_result(sqrt_d)
    );

    wire [31:0] q_half_dly18;
    shift_reg #(.W(32), .D(14)) dly_q (.clk(clk), .in(neg_q_half), .out(q_half_dly18));

    wire [31:0] offset_dly52;
    shift_reg #(.W(32), .D(52)) dly_off (.clk(clk), .in(offset), .out(offset_dly52));

    // T = 18 -> 22: Cộng/Trừ -> u_in và v_in
    wire [31:0] u_in, v_in; wire v_t22;
    fp_add_sub u_add_u (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t18), .in_is_sub(1'b0), 
        .in_operand_A(q_half_dly18), .in_operand_B(sqrt_d), 
        .out_valid(v_t22), .out_result(u_in),
        .status_overflow(), .status_zero()
    );
    
    fp_add_sub u_sub_v (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t18), .in_is_sub(1'b1), 
        .in_operand_A(q_half_dly18), .in_operand_B(sqrt_d), 
        .out_valid(), .out_result(v_in),
        .status_overflow(), .status_zero()
    );

    // T = 22 -> 48: Căn bậc ba u và v
    wire [31:0] u_out, v_out; wire v_t48;
    fp_cbrt u_cbrt_u (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t22), 
        .in_operand_A(u_in), 
        .out_valid(v_t48), .out_result(u_out)
    );
    
    fp_cbrt u_cbrt_v (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t22), 
        .in_operand_A(v_in), 
        .out_valid(), .out_result(v_out)
    );

    // T = 48 -> 52: Cộng uv_sum = u + v
    wire [31:0] uv_sum; wire v_t52;
    fp_add_sub u_add_uv (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t48), .in_is_sub(1'b0), 
        .in_operand_A(u_out), .in_operand_B(v_out), 
        .out_valid(v_t52), .out_result(uv_sum),
        .status_overflow(), .status_zero()
    );

    // T = 52 -> 56: Trừ offset
    fp_add_sub u_sub_off (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t52), .in_is_sub(1'b1), 
        .in_operand_A(uv_sum), .in_operand_B(offset_dly52), 
        .out_valid(out_valid), .out_result(x1),
        .status_overflow(), .status_zero()
    );
endmodule