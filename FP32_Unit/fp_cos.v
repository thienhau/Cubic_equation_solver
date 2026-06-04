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
    
    // Bộ hệ số thuật toán Minimax tối ưu hóa sai số cho dải góc từ 0 đến 1.05
    localparam C0 = 32'h3F800000; // Giá trị hằng số 1.0
    localparam C1 = 32'hBEFFFFFA; // Giá trị xấp xỉ ~ -0.4999998
    localparam C2 = 32'h3D2AA9F3; // Giá trị xấp xỉ ~  0.0416656
    localparam C3 = 32'hBAB9DD59; // Giá trị xấp xỉ ~ -0.0013876
    localparam C4 = 32'h38CD9539; // Giá trị xấp xỉ ~  0.0000245

    localparam CONST_ONE = 32'h3F800000; // Giá trị hằng số 1.0

    // T = 0: Lấy trị tuyệt đối và thực hiện thu hẹp dải toán hạng đầu vào
    wire [31:0] abs_x = {1'b0, in_operand_A[30:0]};
    wire        is_upper_t0 = (abs_x > CONST_ONE); 
    
    // Thu nhỏ một nửa góc bằng cách giảm trường số mũ exponent đi 1 đơn vị
    wire [31:0] half_x = (abs_x[30:23] == 8'd0) ? 32'd0 : {1'b0, abs_x[30:23] - 8'd1, abs_x[22:0]};
    wire [31:0] z_t0 = is_upper_t0 ? half_x : abs_x;

    // Trì hoãn cờ quản lý phân chia dải xuyên suốt 32 tầng pipeline đến ngõ ra
    wire is_upper_t32;
    shift_reg #(.W(1), .D(32)) dly_upper_32 (.clk(clk), .in(is_upper_t0), .out(is_upper_t32));

    // T = 0 -> 4: Tính toán bình phương biến đầu vào u = z * z phục vụ lược đồ Horner
    wire [31:0] u_t4; wire v_u_t4;
    fp_mul u_mul_z2 (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .in_operand_A(z_t0), .in_operand_B(z_t0),
        .out_valid(v_u_t4), .out_result(u_t4),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Định tuyến và trì hoãn biến bình phương u đồng bộ với tiến trình tính đa thức
    wire [31:0] u_t9, u_t14, u_t19;
    shift_reg #(.W(32), .D(5))  dly_u_9  (.clk(clk), .in(u_t4), .out(u_t9));
    shift_reg #(.W(32), .D(10)) dly_u_14 (.clk(clk), .in(u_t4), .out(u_t14));
    shift_reg #(.W(32), .D(15)) dly_u_19 (.clk(clk), .in(u_t4), .out(u_t19));

    // T = 4 -> 9: Thực hiện tính toán tầng đa thức thứ nhất f0 = C4 * u + C3
    wire [31:0] f0_t9; wire v_f0_t9;
    fp_fma u_fma_0 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_u_t4), 
        .in_operand_A(C4), .in_operand_B(u_t4), .in_operand_C(C3), 
        .out_valid(v_f0_t9), .out_result(f0_t9),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 9 -> 14: Thực hiện tính toán tầng đa thức thứ hai f1 = f0 * u + C2
    wire [31:0] f1_t14; wire v_f1_t14;
    fp_fma u_fma_1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_f0_t9), 
        .in_operand_A(f0_t9), .in_operand_B(u_t9), .in_operand_C(C2), 
        .out_valid(v_f1_t14), .out_result(f1_t14),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 14 -> 19: Thực hiện tính toán tầng đa thức thứ ba f2 = f1 * u + C1
    wire [31:0] f2_t19; wire v_f2_t19;
    fp_fma u_fma_2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_f1_t14), 
        .in_operand_A(f1_t14), .in_operand_B(u_t14), .in_operand_C(C1), 
        .out_valid(v_f2_t19), .out_result(f2_t19),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // T = 19 -> 24: Hoàn thành cấu trúc đa thức đa tầng poly = f2 * u + C0
    wire [31:0] poly_t24; wire v_poly_t24;
    fp_fma u_fma_3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_f2_t19), 
        .in_operand_A(f2_t19), .in_operand_B(u_t19), .in_operand_C(C0), 
        .out_valid(v_poly_t24), .out_result(poly_t24),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Trì hoãn kết quả đa thức dải dưới thêm 8 chu kỳ để đồng bộ tại đích chu kỳ T = 32
    wire [31:0] poly_t32;
    shift_reg #(.W(32), .D(8)) dly_poly_8 (.clk(clk), .in(poly_t24), .out(poly_t32));

    // T = 24 -> 28: Tính toán bình phương đa thức phục vụ công thức nhân đôi góc
    wire [31:0] poly2_t28; wire v_poly2_t28;
    fp_mul u_mul_poly2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_poly_t24),
        .in_operand_A(poly_t24), .in_operand_B(poly_t24),
        .out_valid(v_poly2_t28), .out_result(poly2_t28),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Nhân đôi giá trị bình phương bằng phương pháp tăng trường số mũ lên 1 đơn vị nhanh chóng
    wire [31:0] double_poly2_t28 = (poly2_t28[30:23] == 8'd0) ? 32'd0 : 
                                   {poly2_t28[31], poly2_t28[30:23] + 8'd1, poly2_t28[22:0]};

    // T = 28 -> 32: Hoàn thiện công thức nhân đôi góc cho nhánh vượt dải upper_res = 2*cos^2(x/2) - 1
    wire [31:0] upper_res_t32; wire v_upper_t32;
    fp_add_sub u_add_sub_upper (
        .clk(clk), .rst_n(rst_n), .in_valid(v_poly2_t28), .in_is_sub(1'b1),
        .in_operand_A(double_poly2_t28), .in_operand_B(CONST_ONE),
        .out_valid(v_upper_t32), .out_result(upper_res_t32),
        .status_overflow(), .status_zero(), .status_invalid()
    );

    // T = 32: Lựa chọn kết quả cuối cùng thông qua bộ Mux đồng bộ
    assign out_valid = v_upper_t32; 
    assign out_result = is_upper_t32 ? upper_res_t32 : poly_t32;

endmodule