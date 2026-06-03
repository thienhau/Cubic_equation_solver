`timescale 1ns / 1ps

module fp_atan #(
    // LƯU Ý: Latency đã tăng từ 28 lên 49. 
    // Bạn bắt buộc phải cập nhật tham số độ trễ tương ứng bên trong trigon_path.v
    parameter STAGES = 49
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output wire        out_valid, 
    output wire [31:0] out_result
);
    // ==============================================================================
    // KHAI BÁO HẰNG SỐ (Floating-Point 32-bit Hex)
    // ==============================================================================
    localparam CONST_ONE        = 32'h3F800000; // 1.0
    localparam CONST_BREAKPOINT = 32'h3ED413CD; // Sqrt(2) - 1 ~ 0.41421356
    localparam CONST_PI_4       = 32'h3F490FDB; // Pi/4 ~ 0.78539816
    
    // HỆ SỐ MỚI TỐI ƯU CHO DẢI [0, 0.4142]
    localparam C1 = 32'h3F800000; // 1.0 (Giữ nguyên)
    localparam C2 = 32'h3E888889; // 4/15 ~ 0.26666668
    localparam C3 = 32'h3F19999A; // 3/5  = 0.60000000

    // ==============================================================================
    // T = 0: XỬ LÝ DẤU & TRỊ TUYỆT ĐỐI
    // ==============================================================================
    wire [31:0] abs_x = {1'b0, in_operand_A[30:0]}; // Lấy trị tuyệt đối
    wire        sign_x = in_operand_A[31];          // Lưu dấu để phục hồi ở T=49
    
    // Delay dấu đến cuối pipeline (49 chu kỳ)
    wire sign_x_t49;
    shift_reg #(.W(1), .D(49)) dly_sign_49 (.clk(clk), .in(sign_x), .out(sign_x_t49));

    // ==============================================================================
    // T = 0 -> 1: SO SÁNH DẢI (Breakpoint)
    // ==============================================================================
    wire is_upper_t1;
    fp_cmp u_cmp (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .in_operand_A(abs_x), .in_operand_B(CONST_BREAKPOINT),
        .out_valid(), .cmp_eq(), .cmp_gt(is_upper_t1), .cmp_lt(), .status_invalid()
    );
    
    // Delay cờ rẽ nhánh đến T=18 (để ghép MUX Z) và T=49 (để ghép MUX Out)
    wire is_upper_t18, is_upper_t49;
    shift_reg #(.W(1), .D(17)) dly_upper_18 (.clk(clk), .in(is_upper_t1), .out(is_upper_t18));
    shift_reg #(.W(1), .D(48)) dly_upper_49 (.clk(clk), .in(is_upper_t1), .out(is_upper_t49));

    // ==============================================================================
    // T = 0 -> 4: TÍNH (1 - |x|) VÀ (1 + |x|)
    // ==============================================================================
    wire [31:0] num_reduced_t4, den_reduced_t4;
    wire v_add_t4;
    
    fp_add_sub u_add_1_minus_x (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_is_sub(1'b1),
        .in_operand_A(CONST_ONE), .in_operand_B(abs_x),
        .out_valid(v_add_t4), .out_result(num_reduced_t4),
        .status_overflow(), .status_zero(), .status_invalid()
    );
    
    fp_add_sub u_add_1_plus_x (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_is_sub(1'b0),
        .in_operand_A(CONST_ONE), .in_operand_B(abs_x),
        .out_valid(), .out_result(den_reduced_t4),
        .status_overflow(), .status_zero(), .status_invalid()
    );

    // Delay abs_x và in_valid nguyên thủy đến T=18
    wire [31:0] abs_x_t18;
    wire        v_orig_t18;
    shift_reg #(.W(32), .D(18)) dly_abs_x_18 (.clk(clk), .in(abs_x), .out(abs_x_t18));
    shift_reg #(.W(1),  .D(18)) dly_valid_18 (.clk(clk), .in(in_valid), .out(v_orig_t18));

    // ==============================================================================
    // T = 4 -> 18: CHIA DẢI z_reduced = (1 - |x|) / (1 + |x|)
    // ==============================================================================
    wire [31:0] z_reduced_t18;
    wire v_div_reduced_t18;
    
    fp_div u_div_reduced (
        .clk(clk), .rst_n(rst_n), .in_valid(v_add_t4),
        .in_operand_A(num_reduced_t4), .in_operand_B(den_reduced_t4),
        .out_valid(v_div_reduced_t18), .out_result(z_reduced_t18),
        .status_zero(), .status_invalid()
    );

    // MUX Chọn luồng tại T=18
    wire [31:0] z_in_t18 = is_upper_t18 ? z_reduced_t18 : abs_x_t18;
    wire        v_zin_t18 = is_upper_t18 ? v_div_reduced_t18 : v_orig_t18;

    // ==============================================================================
    // T = 18 -> 45: TÍNH ĐA THỨC PADÉ (Tái sử dụng Datapath Cũ)
    // ==============================================================================
    // T = 18 -> 22: z^2
    wire [31:0] z2_t22; wire v_z2_t22;
    fp_mul u_mul_z2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_zin_t18),
        .in_operand_A(z_in_t18), .in_operand_B(z_in_t18),
        .out_valid(v_z2_t22), .out_result(z2_t22),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] z_in_t27;
    shift_reg #(.W(32), .D(9)) dly_z_in_27 (.clk(clk), .in(z_in_t18), .out(z_in_t27));

    // T = 22 -> 27: FMA Tử số và Mẫu số
    wire [31:0] n_part_t27, d_part_t27; wire v_fma_t27;
    fp_fma u_fma_n (
        .clk(clk), .rst_n(rst_n), .in_valid(v_z2_t22),
        .in_operand_A(C2), .in_operand_B(z2_t22), .in_operand_C(C1),
        .out_valid(v_fma_t27), .out_result(n_part_t27),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    fp_fma u_fma_d (
        .clk(clk), .rst_n(rst_n), .in_valid(v_z2_t22),
        .in_operand_A(C3), .in_operand_B(z2_t22), .in_operand_C(CONST_ONE),
        .out_valid(), .out_result(d_part_t27),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 27 -> 31: Ghép Tử số (n_part * z)
    wire [31:0] n_fin_t31; wire v_n_t31;
    fp_mul u_mul_n (
        .clk(clk), .rst_n(rst_n), .in_valid(v_fma_t27),
        .in_operand_A(n_part_t27), .in_operand_B(z_in_t27),
        .out_valid(v_n_t31), .out_result(n_fin_t31),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] d_part_t31;
    shift_reg #(.W(32), .D(4)) dly_d_part_31 (.clk(clk), .in(d_part_t27), .out(d_part_t31));

    // T = 31 -> 45: Phép chia cuối cùng của Đa thức
    wire [31:0] poly_out_t45; wire v_poly_t45;
    fp_div u_div_poly (
        .clk(clk), .rst_n(rst_n), .in_valid(v_n_t31),
        .in_operand_A(n_fin_t31), .in_operand_B(d_part_t31),
        .out_valid(v_poly_t45), .out_result(poly_out_t45),
        .status_zero(), .status_invalid()
    );

    // ==============================================================================
    // T = 45 -> 49: HẬU XỬ LÝ (Pi/4 - poly_out) VÀ CHỐT KẾT QUẢ
    // ==============================================================================
    wire [31:0] y_upper_t49; wire v_final_t49;
    
    fp_add_sub u_add_sub_pi4 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_poly_t45), .in_is_sub(1'b1),
        .in_operand_A(CONST_PI_4), .in_operand_B(poly_out_t45),
        .out_valid(v_final_t49), .out_result(y_upper_t49),
        .status_overflow(), .status_zero(), .status_invalid()
    );

    wire [31:0] poly_out_t49;
    shift_reg #(.W(32), .D(4)) dly_poly_out_49 (.clk(clk), .in(poly_out_t45), .out(poly_out_t49));

    // MUX Chọn đầu ra dựa trên cờ is_upper
    wire [31:0] y_abs_t49 = is_upper_t49 ? y_upper_t49 : poly_out_t49;

    // Gán kết quả: Phục hồi lại dấu ban đầu (Do atan(-x) = -atan(x))
    assign out_valid = v_final_t49; 
    assign out_result = {sign_x_t49, y_abs_t49[30:0]};

endmodule