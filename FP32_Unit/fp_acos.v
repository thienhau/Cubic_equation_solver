`timescale 1ns / 1ps

module fp_acos #(
    parameter STAGES = 58
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output wire        out_valid, 
    output wire [31:0] out_result
);
    // Hệ số khai triển Arcsin dải hẹp cực kỳ phẳng ULP
    localparam C0 = 32'h3F800000; // 1.0
    localparam C1 = 32'h3E2AAAAB; // 1/6 ~ 0.16666667
    localparam C2 = 32'h3D99999A; // 3/40 = 0.075
    localparam C3 = 32'h3D36DB6E; // 5/112 ~ 0.044642857
    localparam C4 = 32'h3CF8E38E; // 35/1152 ~ 0.030381944

    localparam CONST_ONE       = 32'h3F800000;
    localparam CONST_PI        = 32'h40490FDB; // 3.14159265
    localparam CONST_PI_OVER_2 = 32'h3FC90FDB; // 1.57079633

    // T = 0: Trị tuyệt đối và check dải biên
    wire [31:0] abs_x = {1'b0, in_operand_A[30:0]};
    wire sign_x_t0 = in_operand_A[31];
    wire is_upper_t0 = (abs_x > 32'h3F000000); // |x| > 0.5
    
    // Lưu dấu bypass chuẩn ra cuối T=58
    wire sign_x_t58;
    shift_reg #(.W(1), .D(58)) dly_sign_58 (.clk(clk), .in(sign_x_t0), .out(sign_x_t58));

    // T = 0 -> 4: Tính (1.0 - |x|)
    wire [31:0] sub_out_t4; wire v_sub_t4;
    fp_add_sub u_sub_1_minus_x (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_is_sub(1'b1),
        .in_operand_A(CONST_ONE), .in_operand_B(abs_x),
        .out_valid(v_sub_t4), .out_result(sub_out_t4),
        .status_overflow(), .status_zero(), .status_invalid()
    );

    // Tính nhanh dịch bit (1.0 - |x|) / 2 
    wire [31:0] half_sub_t4 = (sub_out_t4[30:23] == 8'd0) ? 32'd0 : 
                              {sub_out_t4[31], sub_out_t4[30:23] - 8'd1, sub_out_t4[22:0]};

    // T = 4 -> 22: Căn bậc hai
    wire [31:0] sqrt_out_t22; wire v_sqrt_t22;
    fp_sqrt u_sqrt (
        .clk(clk), .rst_n(rst_n), .in_valid(v_sub_t4),
        .in_operand_A(half_sub_t4), .out_valid(v_sqrt_t22), 
        .out_result(sqrt_out_t22), .status_invalid()
    );

    // Đồng bộ luồng dải dưới tại T = 22
    wire [31:0] abs_x_t22;
    wire is_upper_t22;
    wire v_orig_t22;
    shift_reg #(.W(32), .D(22)) dly_abs_x_22 (.clk(clk), .in(abs_x), .out(abs_x_t22));
    shift_reg #(.W(1), .D(22)) dly_upper_22 (.clk(clk), .in(is_upper_t0), .out(is_upper_t22));
    shift_reg #(.W(1), .D(22)) dly_valid_22 (.clk(clk), .in(in_valid), .out(v_orig_t22));

    // MUX lựa chọn Z đầu vào cho đa thức tại T = 22
    wire [31:0] z_t22 = is_upper_t22 ? sqrt_out_t22 : abs_x_t22;
    wire        v_z_t22 = is_upper_t22 ? v_sqrt_t22 : v_orig_t22;

    // T = 22 -> 26: Nhân bình phương z^2
    wire [31:0] u_t26; wire v_u_t26;
    fp_mul u_mul_z2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_z_t22),
        .in_operand_A(z_t22), .in_operand_B(z_t22),
        .out_valid(v_u_t26), .out_result(u_t26),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 26 -> 46: Chuỗi FMA tính lõi Arcsin (20 chu kỳ)
    wire [31:0] f0_t31, f1_t36, f2_t41, poly_t46;
    wire v_f0_t31, v_f1_t36, v_f2_t41, v_poly_t46;

    // Đồng bộ biến 'u' đi qua các tầng Pipeline
    wire [31:0] u_t31, u_t36, u_t41;
    shift_reg #(.W(32), .D(5))  dly_u_31 (.clk(clk), .in(u_t26), .out(u_t31));
    shift_reg #(.W(32), .D(10)) dly_u_36 (.clk(clk), .in(u_t26), .out(u_t36));
    shift_reg #(.W(32), .D(15)) dly_u_41 (.clk(clk), .in(u_t26), .out(u_t41));

    fp_fma u_fma_0 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_u_t26), 
        .in_operand_A(C4), .in_operand_B(u_t26), .in_operand_C(C3), 
        .out_valid(v_f0_t31), .out_result(f0_t31), .status_overflow(), 
        .status_underflow(), .status_invalid(), .status_zero()
    );
    
    // Đổi B sang u_t31
    fp_fma u_fma_1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_f0_t31), 
        .in_operand_A(f0_t31), .in_operand_B(u_t31), .in_operand_C(C2), 
        .out_valid(v_f1_t36), .out_result(f1_t36), .status_overflow(), 
        .status_underflow(), .status_invalid(), .status_zero()
    );
    
    // Đổi B sang u_t36
    fp_fma u_fma_2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_f1_t36), 
        .in_operand_A(f1_t36), .in_operand_B(u_t36), .in_operand_C(C1), 
        .out_valid(v_f2_t41), .out_result(f2_t41), .status_overflow(), 
        .status_underflow(), .status_invalid(), .status_zero()
    );
    
    // Đổi B sang u_t41
    fp_fma u_fma_3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_f2_t41), 
        .in_operand_A(f2_t41), .in_operand_B(u_t41), .in_operand_C(C0), 
        .out_valid(v_poly_t46), .out_result(poly_t46), .status_overflow(), 
        .status_underflow(), .status_invalid(), .status_zero()
    );

    // Cân bằng trễ biến z_t22 từ T=22 đến T=46 để thực hiện phép nhân cuối
    wire [31:0] z_t46;
    shift_reg #(.W(32), .D(24)) dly_z_46 (.clk(clk), .in(z_t22), .out(z_t46));

    // T = 46 -> 50: Nhân khôi phục lũy thừa bậc 1: arcsin_z = z * poly_out
    wire [31:0] arcsin_z_t50; wire v_arcsin_t50;
    fp_mul u_mul_arcsin (
        .clk(clk), .rst_n(rst_n), .in_valid(v_poly_t46),
        .in_operand_A(poly_t46), .in_operand_B(z_t46),
        .out_valid(v_arcsin_t50), .out_result(arcsin_z_t50),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 50 -> 58: Hậu xử lý đồng bộ góc kết hợp biên bypass
    wire is_upper_t50;
    shift_reg #(.W(1), .D(28)) dly_upper_50 (.clk(clk), .in(is_upper_t22), .out(is_upper_t50));

    // Nếu vượt dải, góc kết quả thực tế bằng 2 * arcsin(z) (Tăng Exponent thêm 1)
    wire [31:0] double_arcsin = (arcsin_z_t50[30:23] == 8'd0) ? 32'd0 : 
                                {arcsin_z_t50[31], arcsin_z_t50[30:23] + 8'd1, arcsin_z_t50[22:0]};
    
    // Chuẩn bị toán hạng cho bộ cộng/trừ bù góc ở T=50 -> 54
    // - Dải dưới: Pi/2 - arcsin(z)  <=>  CONST_PI_OVER_2 + (-arcsin_z)
    // - Dải trên: 0.0 + 2*arcsin(z) <=>  32'd0 + double_arcsin
    wire [31:0] opA_t50 = is_upper_t50 ? 32'd0 : CONST_PI_OVER_2;
    wire [31:0] opB_t50 = is_upper_t50 ? double_arcsin : {~arcsin_z_t50[31], arcsin_z_t50[30:0]};

    wire [31:0] acos_abs_t54; wire v_acos_abs_t54;
    fp_add_sub u_add_acos_abs (
        .clk(clk), .rst_n(rst_n), .in_valid(v_arcsin_t50), .in_is_sub(1'b0),
        .in_operand_A(opA_t50), .in_operand_B(opB_t50),
        .out_valid(v_acos_abs_t54), .out_result(acos_abs_t54),
        .status_overflow(), .status_zero(), .status_invalid()
    );

    // T = 54 -> 58: Nếu số âm thực tế (x < 0) => Bù góc bằng Pi - acos(|x|)
    wire [31:0] acos_neg_t58; wire v_acos_neg_t58;
    fp_add_sub u_sub_neg_x (
        .clk(clk), .rst_n(rst_n), .in_valid(v_acos_abs_t54), .in_is_sub(1'b1),
        .in_operand_A(CONST_PI), .in_operand_B(acos_abs_t54),
        .out_valid(v_acos_neg_t58), .out_result(acos_neg_t58),
        .status_overflow(), .status_zero(), .status_invalid()
    );

    wire [31:0] acos_abs_t58;
    shift_reg #(.W(32), .D(4)) dly_abs_out_4 (.clk(clk), .in(acos_abs_t54), .out(acos_abs_t58));

    // Đánh giá các điểm kỳ dị biên cứng cố định chốt đầu ra lý tưởng 0 ULP
    wire [31:0] raw_calc_res = sign_x_t58 ? acos_neg_t58 : acos_abs_t58;
    
    // Đồng bộ hóa các tín hiệu check biên đặc biệt từ T=0 xuống T=58
    wire is_p1_t58, is_m1_t58, is_z_t58;
    shift_reg #(.W(1), .D(58)) dp58 (.clk(clk), .in(in_operand_A == 32'h3F800000), .out(is_p1_t58));
    shift_reg #(.W(1), .D(58)) dm58 (.clk(clk), .in(in_operand_A == 32'hBF800000), .out(is_m1_t58));
    shift_reg #(.W(1), .D(58)) dz58 (.clk(clk), .in(abs_x == 32'd0), .out(is_z_t58));

    assign out_valid = v_acos_neg_t58;
    assign out_result = is_p1_t58 ? 32'h00000000 : // acos(1.0) = 0.0
                        is_m1_t58 ? CONST_PI :   // acos(-1.0) = PI
                        is_z_t58  ? CONST_PI_OVER_2 : // acos(0.0) = PI/2
                        raw_calc_res;
endmodule