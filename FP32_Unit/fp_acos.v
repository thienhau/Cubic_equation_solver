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
    // BỘ HỆ SỐ ĐA THỨC P(x) CHO ACOS CỰC KỲ CHÍNH XÁC
    localparam N3 = 32'hBC996C25; // -0.0187293
    localparam N2 = 32'h3D9814C4; // 0.0742610
    localparam N1 = 32'hBE593452; // -0.2121144
    localparam N0 = 32'h3FC90E2A; // 1.5707288

    // T = 0 -> 1: Lưu giá trị tuyệt đối |x|
    wire [31:0] x_abs = {1'b0, in_operand_A[30:0]};
    reg [31:0] x_d1; reg s_d1; reg v_d1;
    always @(posedge clk) begin 
        x_d1 <= x_abs; s_d1 <= in_operand_A[31]; v_d1 <= in_valid; 
    end

    // T = 1 -> 5: Tính sub_x = 1.0 - |x|
    wire [31:0] sub_x; wire v_sub;
    fp_add_sub u_sub (
        .clk(clk), .rst_n(rst_n), .in_valid(v_d1), .in_is_sub(1'b1),
        .in_operand_A(32'h3F800000), .in_operand_B(x_d1),
        .out_valid(v_sub), .out_result(sub_x),
        .status_overflow(), .status_zero()
    );

    // T = 5 -> 23: Tính sqrt_x = sqrt(1.0 - |x|)
    wire [31:0] sqrt_x; wire v_sqrt;
    fp_sqrt u_sqrt (
        .clk(clk), .rst_n(rst_n), .in_valid(v_sub),
        .in_operand_A(sub_x[31] ? 32'd0 : sub_x), // Clamp an toàn
        .out_valid(v_sqrt), .out_result(sqrt_x)
    );

    // SONG SONG T = 1 -> 16: Tính P(x) = ((N3*x + N2)*x + N1)*x + N0
    wire [31:0] tn1; wire v_n1;
    fp_fma u_fma1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_d1),
        .in_operand_A(N3), .in_operand_B(x_d1), .in_operand_C(N2),
        .out_valid(v_n1), .out_result(tn1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    wire [31:0] x_d6; shift_reg #(.W(32), .D(5)) dx6 (.clk(clk), .in(x_d1), .out(x_d6));

    wire [31:0] tn2; wire v_n2;
    fp_fma u_fma2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_n1),
        .in_operand_A(tn1), .in_operand_B(x_d6), .in_operand_C(N1),
        .out_valid(v_n2), .out_result(tn2),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    wire [31:0] x_d11; shift_reg #(.W(32), .D(5)) dx11 (.clk(clk), .in(x_d6), .out(x_d11));

    wire [31:0] px; wire v_px;
    fp_fma u_fma3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_n2),
        .in_operand_A(tn2), .in_operand_B(x_d11), .in_operand_C(N0),
        .out_valid(v_px), .out_result(px),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 16 -> 23: Delay P(x) chờ SQRT tính xong
    wire [31:0] px_d23;
    shift_reg #(.W(32), .D(7)) dpx (.clk(clk), .in(px), .out(px_d23));

    // T = 23 -> 27: Nhân acos_abs = sqrt_x * P(x)
    wire [31:0] acos_abs; wire v_acos;
    fp_mul u_mul_acos (
        .clk(clk), .rst_n(rst_n), .in_valid(v_sqrt),
        .in_operand_A(sqrt_x), .in_operand_B(px_d23),
        .out_valid(v_acos), .out_result(acos_abs),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 27 -> 30: Delay đồng bộ để khớp chu kỳ FMA bù góc
    wire [31:0] acos_abs_d30; wire v_d30;
    shift_reg #(.W(32), .D(3)) dacos (.clk(clk), .in(acos_abs), .out(acos_abs_d30));
    shift_reg #(.W(1), .D(3)) dv30 (.clk(clk), .in(v_acos), .out(v_d30));

    // T = 30 -> 35: Tính góc bù (pi - acos_abs) nếu đầu vào là số âm
    wire [31:0] fma_adjust; wire v_fma;
    fp_fma u_fma_quad (
        .clk(clk), .rst_n(rst_n), .in_valid(v_d30), 
        .in_operand_A(32'hBF800000), .in_operand_B(acos_abs_d30), .in_operand_C(32'h40490FDB), 
        .out_valid(v_fma), .out_result(fma_adjust),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Delay các tín hiệu cần thiết đến T = 35
    wire [31:0] acos_dly35;
    shift_reg #(.W(32), .D(5)) d_fin_acos (.clk(clk), .in(acos_abs_d30), .out(acos_dly35));
    
    wire s_d35;
    shift_reg #(.W(1), .D(34)) ds35 (.clk(clk), .in(s_d1), .out(s_d35));

    assign out_valid = v_fma;
    assign out_result = s_d35 ? fma_adjust : acos_dly35;
endmodule