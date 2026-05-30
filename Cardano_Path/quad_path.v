`timescale 1ns / 1ps

module quad_path #(
    parameter STAGES = 48
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] b, c, d,
    
    output wire        out_valid,
    output wire [31:0] x1,
    output wire [31:0] x2
);
    // T = 0 -> 4: Tính c^2, b*d và 2b
    wire [31:0] c2, bd, b2; wire v_t4;
    fp_mul u_mul_c2 (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), 
        .in_operand_A(c), .in_operand_B(c), 
        .out_valid(v_t4), .out_result(c2),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    fp_mul u_mul_bd (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), 
        .in_operand_A(b), .in_operand_B(d), 
        .out_valid(), .out_result(bd),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    fp_mul u_mul_b2 (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), 
        .in_operand_A(b), .in_operand_B(32'h40000000), 
        .out_valid(), .out_result(b2),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] c_dly30;
    shift_reg #(.W(32), .D(30)) dly_c (.clk(clk), .in(c), .out(c_dly30));
    
    wire [31:0] b2_dly34;
    shift_reg #(.W(32), .D(30)) dly_b2 (.clk(clk), .in(b2), .out(b2_dly34));

    // T = 4 -> 8: Tính 4bd
    wire [31:0] bd4; wire v_t8;
    fp_mul u_mul_4 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t4), 
        .in_operand_A(bd), .in_operand_B(32'h40800000), 
        .out_valid(v_t8), .out_result(bd4),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] c2_dly8;
    shift_reg #(.W(32), .D(4)) dly_c2 (.clk(clk), .in(c2), .out(c2_dly8));

    // T = 8 -> 12: Tính Delta = c^2 - 4bd
    wire [31:0] delta; wire v_t12;
    fp_add_sub u_sub_delta (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t8), .in_is_sub(1'b1), 
        .in_operand_A(c2_dly8), .in_operand_B(bd4), 
        .out_valid(v_t12), .out_result(delta),
        .status_overflow(), .status_zero()
    );

    // T = 12 -> 30: Căn bậc hai Delta
    wire [31:0] sqrt_delta; wire v_t30;
    fp_sqrt u_sqrt (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t12), 
        .in_operand_A(delta), 
        .out_valid(v_t30), .out_result(sqrt_delta)
    );

    // T = 30 -> 34: Tính Tử số (-c + sqrt_D) và (-c - sqrt_D)
    wire [31:0] neg_c = {~c_dly30[31], c_dly30[30:0]};
    wire [31:0] num1, num2; wire v_t34;
    fp_add_sub u_add_num1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t30), .in_is_sub(1'b0), 
        .in_operand_A(neg_c), .in_operand_B(sqrt_delta), 
        .out_valid(v_t34), .out_result(num1),
        .status_overflow(), .status_zero()
    );
    
    fp_add_sub u_sub_num2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t30), .in_is_sub(1'b1), 
        .in_operand_A(neg_c), .in_operand_B(sqrt_delta), 
        .out_valid(), .out_result(num2),
        .status_overflow(), .status_zero()
    );

    // T = 34 -> 48: Chia cho 2b
    fp_div u_div_x1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t34), 
        .in_operand_A(num1), .in_operand_B(b2_dly34), 
        .out_valid(out_valid), .out_result(x1),
        .status_zero(), .status_invalid()
    );
    
    fp_div u_div_x2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t34), 
        .in_operand_A(num2), .in_operand_B(b2_dly34), 
        .out_valid(), .out_result(x2),
        .status_zero(), .status_invalid()
    );
endmodule