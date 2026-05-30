`timescale 1ns / 1ps

module fp_atan #(
    parameter STAGES = 28
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output wire        out_valid, 
    output wire [31:0] out_result
);
    // BỘ HỆ SỐ RATIONAL [2/2] TỐI ƯU CỰC ĐẠI CHO KHOẢNG [0, 1]
    localparam C1 = 32'h3F800000; // 1.0
    localparam C2 = 32'h3E613562; // 0.21993
    localparam C3 = 32'h3F0D929A; // 0.55326
    localparam ONE = 32'h3F800000;

    // T = 0 -> 1: Chuẩn bị giá trị |x|
    wire [31:0] x_reg = {1'b0, in_operand_A[30:0]};
    reg [31:0] x_d1;
    reg s_d1, v_d1;
    always @(posedge clk) begin 
        x_d1 <= x_reg;
        s_d1 <= in_operand_A[31]; v_d1 <= in_valid;
    end

    // T = 1 -> 5: Tính x^2
    wire [31:0] x2; wire v_x2;
    fp_mul u_mul_x2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_d1), 
        .in_operand_A(x_d1), .in_operand_B(x_d1), 
        .out_valid(v_x2), .out_result(x2),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] x_d5; wire s_d5; 
    shift_reg #(.W(32), .D(4)) dx5 (.clk(clk), .in(x_d1), .out(x_d5)); 
    shift_reg #(.W(1),  .D(4)) ds5 (.clk(clk), .in(s_d1), .out(s_d5));

    // T = 5 -> 10: FMA song song cho Tử và Mẫu
    wire [31:0] n_part, d_part; wire v_fma;
    fp_fma u_fma_n (
        .clk(clk), .rst_n(rst_n), .in_valid(v_x2), 
        .in_operand_A(C2), .in_operand_B(x2), .in_operand_C(C1), 
        .out_valid(v_fma), .out_result(n_part),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    fp_fma u_fma_d (
        .clk(clk), .rst_n(rst_n), .in_valid(v_x2), 
        .in_operand_A(C3), .in_operand_B(x2), .in_operand_C(ONE), 
        .out_valid(), .out_result(d_part),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] x_d10; wire s_d10;
    shift_reg #(.W(32), .D(5)) dx10 (.clk(clk), .in(x_d5), .out(x_d10)); 
    shift_reg #(.W(1),  .D(5)) ds10 (.clk(clk), .in(s_d5), .out(s_d10));

    // T = 10 -> 14: MUL ghép tử
    wire [31:0] n_fin; wire v_n;
    fp_mul u_mul_n (
        .clk(clk), .rst_n(rst_n), .in_valid(v_fma), 
        .in_operand_A(n_part), .in_operand_B(x_d10), 
        .out_valid(v_n), .out_result(n_fin),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] d_d4; wire s_d14;
    shift_reg #(.W(32), .D(4)) dd4 (.clk(clk), .in(d_part), .out(d_d4)); 
    shift_reg #(.W(1),  .D(4)) ds14 (.clk(clk), .in(s_d10), .out(s_d14));

    // T = 14 -> 28: DIV kết quả
    wire [31:0] div_res; wire v_div;
    fp_div u_div_op (
        .clk(clk), .rst_n(rst_n), .in_valid(v_n), 
        .in_operand_A(n_fin), .in_operand_B(d_d4), 
        .out_valid(v_div), .out_result(div_res),
        .status_zero(), .status_invalid()
    );

    wire s_d28; 
    shift_reg #(.W(1), .D(14)) ds28 (.clk(clk), .in(s_d14), .out(s_d28));
    
    assign out_valid = v_div;
    assign out_result = {s_d28, div_res[30:0]};
endmodule