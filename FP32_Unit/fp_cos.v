`timescale 1ns / 1ps

module fp_cos #(
    parameter STAGES = 32
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output wire        out_valid, 
    output wire [31:0] out_result
);
    // ==============================================================================
    // BỘ HỆ SỐ MINIMAX (REMEZ ALGORITHM) TỐI ƯU GẮT CHO DẢI [0, 1.05]
    // Ép phẳng hoàn toàn sai số ULP ở biên giới so với chuỗi Taylor cũ.
    // ==============================================================================
    localparam C0 = 32'h3F800000; // 1.0 (Giữ nguyên để cos(0) = 1 chuẩn xác)
    localparam C1 = 32'hBEFFFFFA; // ~ -0.4999998  (Taylor cũ là -0.5)
    localparam C2 = 32'h3D2AA9F3; // ~  0.0416656  (Taylor cũ là 0.0416667)
    localparam C3 = 32'hBAB9DD59; // ~ -0.0013876  (Taylor cũ là -0.0013889)
    localparam C4 = 32'h38CD9539; // ~  0.0000245  (Taylor cũ là 0.0000248)

    localparam CONST_ONE = 32'h3F800000; // 1.0

    // ==============================================================================
    // T = 0: LẤY TRỊ TUYỆT ĐỐI VÀ CHIA DẢI (RANGE REDUCTION)
    // ==============================================================================
    wire [31:0] abs_x = {1'b0, in_operand_A[30:0]};
    wire        is_upper_t0 = (abs_x > CONST_ONE); 
    
    // Nếu vượt dải > 1.0, z = |x| / 2 (Bằng cách trừ Exponent đi 1)
    // Có thêm kiểm tra 0 ở exponent để tránh underflow.
    wire [31:0] half_x = (abs_x[30:23] == 8'd0) ? 32'd0 : {1'b0, abs_x[30:23] - 8'd1, abs_x[22:0]};
    wire [31:0] z_t0 = is_upper_t0 ? half_x : abs_x;

    // Delay cờ chia dải đến cuối pipeline (T = 32)
    wire is_upper_t32;
    shift_reg #(.W(1), .D(32)) dly_upper_32 (.clk(clk), .in(is_upper_t0), .out(is_upper_t32));

    // ==============================================================================
    // T = 0 -> 4: TÍNH u = z^2 (Dùng cho phương pháp Horner)
    // ==============================================================================
    wire [31:0] u_t4; wire v_u_t4;
    fp_mul u_mul_z2 (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .in_operand_A(z_t0), .in_operand_B(z_t0),
        .out_valid(v_u_t4), .out_result(u_t4),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // ==============================================================================
    // T = 4 -> 24: CHUỖI 4 BỘ FMA TÍNH ĐA THỨC (Horner Method)
    // Tính P(u) = C0 + u * (C1 + u * (C2 + u * (C3 + u * C4)))
    // ==============================================================================
    wire [31:0] f0_t9, f1_t14, f2_t19, poly_t24;
    wire v_f0_t9, v_f1_t14, v_f2_t19, v_poly_t24;

    // f0 = C4 * u + C3
    fp_fma u_fma_0 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_u_t4), 
        .in_operand_A(C4), .in_operand_B(u_t4), .in_operand_C(C3), 
        .out_valid(v_f0_t9), .out_result(f0_t9),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    // f1 = f0 * u + C2
    fp_fma u_fma_1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_f0_t9), 
        .in_operand_A(f0_t9), .in_operand_B(u_t4), .in_operand_C(C2), 
        .out_valid(v_f1_t14), .out_result(f1_t14),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    // f2 = f1 * u + C1
    fp_fma u_fma_2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_f1_t14), 
        .in_operand_A(f1_t14), .in_operand_B(u_t4), .in_operand_C(C1), 
        .out_valid(v_f2_t19), .out_result(f2_t19),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    // poly = f2 * u + C0
    fp_fma u_fma_3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_f2_t19), 
        .in_operand_A(f2_t19), .in_operand_B(u_t4), .in_operand_C(C0), 
        .out_valid(v_poly_t24), .out_result(poly_t24),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Đồng bộ kết quả nhánh dải dưới (không cần nhân đôi góc) tới chu kỳ 32
    wire [31:0] poly_t32;
    shift_reg #(.W(32), .D(8)) dly_poly_8 (.clk(clk), .in(poly_t24), .out(poly_t32));

    // ==============================================================================
    // T = 24 -> 32: HẬU XỬ LÝ CHO NHÁNH VƯỢT DẢI (x > 1.0)
    // Dùng hằng đẳng thức nhân đôi: cos(x) = 2*cos^2(x/2) - 1
    // ==============================================================================
    
    // T = 24 -> 28: Tính poly^2
    wire [31:0] poly2_t28; wire v_poly2_t28;
    fp_mul u_mul_poly2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_poly_t24),
        .in_operand_A(poly_t24), .in_operand_B(poly_t24),
        .out_valid(v_poly2_t28), .out_result(poly2_t28),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Nhân 2 cực nhanh bằng cách cộng 1 vào Exponent (không tốn tài nguyên nhân)
    wire [31:0] double_poly2_t28 = (poly2_t28[30:23] == 8'd0) ? 32'd0 : 
                                   {poly2_t28[31], poly2_t28[30:23] + 8'd1, poly2_t28[22:0]};

    // T = 28 -> 32: Tính (2 * poly^2) - 1.0
    wire [31:0] upper_res_t32; wire v_upper_t32;
    fp_add_sub u_add_sub_upper (
        .clk(clk), .rst_n(rst_n), .in_valid(v_poly2_t28), .in_is_sub(1'b1),
        .in_operand_A(double_poly2_t28), .in_operand_B(CONST_ONE),
        .out_valid(v_upper_t32), .out_result(upper_res_t32),
        .status_overflow(), .status_zero(), .status_invalid()
    );

    // ==============================================================================
    // T = 32: MUX CHỌN KẾT QUẢ CUỐI CÙNG
    // ==============================================================================
    assign out_valid = v_upper_t32; 
    assign out_result = is_upper_t32 ? upper_res_t32 : poly_t32;

endmodule