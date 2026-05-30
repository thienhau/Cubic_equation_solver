`timescale 1ns / 1ps

module fp_acos #(
    parameter STAGES = 35
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output wire        out_valid, 
    output wire [31:0] out_result
);
    // BỘ HẰNG SỐ RATIONAL [2/2] SIÊU CHÍNH XÁC (Quét sạch sai số)
    localparam A_N3 = 32'h00000000; // 0.0
    localparam A_N2 = 32'h3F9D2F1A; // 1.228
    localparam A_N1 = 32'hC0331F85; // -2.7988
    localparam A_N0 = 32'h3FC90FDB; // 1.5707963 (pi/2)
    localparam A_D3 = 32'h00000000; // 0.0
    localparam A_D2 = 32'h3E64F765; // 0.2236
    localparam A_D1 = 32'hBF995810; // -1.198
    localparam A_D0 = 32'h3F800000; // 1.0

    // T = 0 -> 1: Lưu tạm giá trị tuyệt đối |x|
    wire [31:0] x_abs = {1'b0, in_operand_A[30:0]};
    reg [31:0] x_d1; reg s_d1; reg v_d1;
    always @(posedge clk) begin 
        x_d1 <= x_abs;
        s_d1 <= in_operand_A[31]; v_d1 <= in_valid; 
    end

    wire [31:0] x_d6, x_d11, x_d16; wire s_d6, s_d11, s_d16, s_d30;
    shift_reg #(.W(32), .D(5)) dx1 (.clk(clk), .in(x_d1), .out(x_d6));
    shift_reg #(.W(32), .D(5)) dx2 (.clk(clk), .in(x_d6), .out(x_d11));
    shift_reg #(.W(32), .D(5)) dx3 (.clk(clk), .in(x_d11), .out(x_d16));
    
    shift_reg #(.W(1), .D(5)) ds1 (.clk(clk), .in(s_d1), .out(s_d6));
    shift_reg #(.W(1), .D(5)) ds2 (.clk(clk), .in(s_d6), .out(s_d11)); 
    shift_reg #(.W(1), .D(5)) ds3 (.clk(clk), .in(s_d11), .out(s_d16));
    shift_reg #(.W(1), .D(14)) ds4 (.clk(clk), .in(s_d16), .out(s_d30));
    
    // T = 1 -> 6: FMA1
    wire [31:0] tn1, td1;
    wire v_s1;
    fp_fma u_fma_n1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_d1), 
        .in_operand_A(A_N3), .in_operand_B(x_d1), .in_operand_C(A_N2), 
        .out_valid(v_s1), .out_result(tn1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    fp_fma u_fma_d1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_d1), 
        .in_operand_A(A_D3), .in_operand_B(x_d1), .in_operand_C(A_D2), 
        .out_valid(), .out_result(td1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 6 -> 11: FMA2
    wire [31:0] tn2, td2; wire v_s2;
    fp_fma u_fma_n2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_s1), 
        .in_operand_A(tn1), .in_operand_B(x_d6), .in_operand_C(A_N1), 
        .out_valid(v_s2), .out_result(tn2),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    fp_fma u_fma_d2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_s1), 
        .in_operand_A(td1), .in_operand_B(x_d6), .in_operand_C(A_D1), 
        .out_valid(), .out_result(td2),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 11 -> 16: FMA3
    wire [31:0] n_fin, d_fin; wire v_s3;
    fp_fma u_fma_n3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_s2), 
        .in_operand_A(tn2), .in_operand_B(x_d11), .in_operand_C(A_N0), 
        .out_valid(v_s3), .out_result(n_fin),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    fp_fma u_fma_d3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_s2), 
        .in_operand_A(td2), .in_operand_B(x_d11), .in_operand_C(A_D0), 
        .out_valid(), .out_result(d_fin),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 16 -> 30: DIV
    wire [31:0] div_res; wire v_div;
    fp_div u_div_op (
        .clk(clk), .rst_n(rst_n), .in_valid(v_s3), 
        .in_operand_A(n_fin), .in_operand_B(d_fin), 
        .out_valid(v_div), .out_result(div_res),
        .status_zero(), .status_invalid()
    );

    // T = 30 -> 35: FMA Quad điều chỉnh PI
    wire [31:0] fma_adjust; wire v_fma;
    fp_fma u_fma_quad (
        .clk(clk), .rst_n(rst_n), .in_valid(v_div), 
        .in_operand_A(32'hBF800000), .in_operand_B(div_res), .in_operand_C(32'h40490FDB), 
        .out_valid(v_fma), .out_result(fma_adjust),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] div_dly;
    shift_reg #(.W(32), .D(5)) ddiv (.clk(clk), .in(div_res), .out(div_dly)); 
    
    wire s_d35;
    shift_reg #(.W(1), .D(5)) dfin (.clk(clk), .in(s_d30), .out(s_d35));

    assign out_valid = v_fma;
    assign out_result = s_d35 ? fma_adjust : div_dly;
endmodule