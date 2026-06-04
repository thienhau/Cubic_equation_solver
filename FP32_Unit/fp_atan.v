`timescale 1ns / 1ps

module fp_atan #(
    parameter STAGES = 49
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output wire        out_valid, 
    output wire [31:0] out_result
);

    // Khai báo hằng số định dạng số thực dấu chấm động 32-bit
    localparam CONST_ONE        = 32'h3F800000; // Giá trị 1.0
    localparam CONST_BREAKPOINT = 32'h3ED413CD; // Giá trị Sqrt(2) - 1 ~ 0.41421356
    localparam CONST_PI_4       = 32'h3F490FDB; // Giá trị Pi/4 ~ 0.78539816
    
    // Hệ số đa thức tối ưu cho dải giá trị từ 0 đến 0.4142
    localparam C1 = 32'h3F800000; // Giá trị 1.0
    localparam C2 = 32'h3E888889; // Giá trị 4/15 ~ 0.26666668
    localparam C3 = 32'h3F19999A; // Giá trị 3/5  = 0.60000000

    // T = 0: Trích xuất dấu và tính toán giá trị tuyệt đối của toán hạng đầu vào
    wire [31:0] abs_x = {1'b0, in_operand_A[30:0]}; 
    wire        sign_x = in_operand_A[31];          
    
    // Trì hoãn bit dấu ban đầu qua 49 tầng pipeline để phục hồi ở ngõ ra cuối cùng
    wire sign_x_t49;
    shift_reg #(.W(1), .D(49)) dly_sign_49 (.clk(clk), .in(sign_x), .out(sign_x_t49));

    // T = 0 -> 1: Thực hiện so sánh giá trị tuyệt đối đầu vào với điểm phân chia dải
    wire is_upper_t1;
    fp_cmp u_cmp (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .in_operand_A(abs_x), .in_operand_B(CONST_BREAKPOINT),
        .out_valid(), .cmp_eq(), .cmp_gt(is_upper_t1), .cmp_lt(), .status_invalid()
    );
    
    // Trì hoãn cờ so sánh dải đến chu kỳ T = 18 và T = 49 phục vụ cho việc lựa chọn kết quả
    wire is_upper_t18, is_upper_t49;
    shift_reg #(.W(1), .D(17)) dly_upper_18 (.clk(clk), .in(is_upper_t1), .out(is_upper_t18));
    shift_reg #(.W(1), .D(48)) dly_upper_49 (.clk(clk), .in(is_upper_t1), .out(is_upper_t49));

    // T = 0 -> 4: Tính toán song song hai giá trị hiệu (1 - |x|) và tổng (1 + |x|)
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

    // Trì hoãn giá trị tuyệt đối abs_x và cờ hợp lệ nguyên thủy đến chu kỳ T = 18
    wire [31:0] abs_x_t18;
    wire        v_orig_t18;
    shift_reg #(.W(32), .D(18)) dly_abs_x_18 (.clk(clk), .in(abs_x), .out(abs_x_t18));
    shift_reg #(.W(1),  .D(18)) dly_valid_18 (.clk(clk), .in(in_valid), .out(v_orig_t18));

    // T = 4 -> 18: Thực hiện phép chia biến đổi dải z_reduced = (1 - |x|) / (1 + |x|)
    wire [31:0] z_reduced_t18;
    wire v_div_reduced_t18;
    
    fp_div u_div_reduced (
        .clk(clk), .rst_n(rst_n), .in_valid(v_add_t4),
        .in_operand_A(num_reduced_t4), .in_operand_B(den_reduced_t4),
        .out_valid(v_div_reduced_t18), .out_result(z_reduced_t18),
        .status_zero(), .status_invalid()
    );

    // Lựa chọn luồng dữ liệu đầu vào cho khối đa thức Padé tại chu kỳ T = 18
    wire [31:0] z_in_t18 = is_upper_t18 ? z_reduced_t18 : abs_x_t18;
    wire        v_zin_t18 = is_upper_t18 ? v_div_reduced_t18 : v_orig_t18;

    // T = 18 -> 22: Tính toán bình phương biến đầu vào z2 = z_in * z_in
    wire [31:0] z2_t22; wire v_z2_t22;
    fp_mul u_mul_z2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_zin_t18),
        .in_operand_A(z_in_t18), .in_operand_B(z_in_t18),
        .out_valid(v_z2_t22), .out_result(z2_t22),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Trì hoãn biến z_in từ chu kỳ T = 18 đến chu kỳ T = 27 để đồng bộ với ngõ ra của FMA
    wire [31:0] z_in_t27;
    shift_reg #(.W(32), .D(9)) dly_z_in_27 (.clk(clk), .in(z_in_t18), .out(z_in_t27));

    // T = 22 -> 27: Tính toán song song các thành phần tử số và mẫu số qua khối fma
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

    // T = 27 -> 31: Ghép hoàn chỉnh tử số bằng phép nhân n_fin = n_part * z
    wire [31:0] n_fin_t31; wire v_n_t31;
    fp_mul u_mul_n (
        .clk(clk), .rst_n(rst_n), .in_valid(v_fma_t27),
        .in_operand_A(n_part_t27), .in_operand_B(z_in_t27),
        .out_valid(v_n_t31), .out_result(n_fin_t31),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Trì hoãn mẫu số d_part thêm 4 chu kỳ để đồng bộ tại chu kỳ T = 31
    wire [31:0] d_part_t31;
    shift_reg #(.W(32), .D(4)) dly_d_part_31 (.clk(clk), .in(d_part_t27), .out(d_part_t31));

    // T = 31 -> 45: Thực hiện phép chia đa thức cuối cùng poly_out = n_fin / d_part
    wire [31:0] poly_out_t45; wire v_poly_t45;
    fp_div u_div_poly (
        .clk(clk), .rst_n(rst_n), .in_valid(v_n_t31),
        .in_operand_A(n_fin_t31), .in_operand_B(d_part_t31),
        .out_valid(v_poly_t45), .out_result(poly_out_t45),
        .status_zero(), .status_invalid()
    );

    // T = 45 -> 49: Hiệu chỉnh dải cho nhánh trên bằng phép toán hiệu Pi/4 - poly_out
    wire [31:0] y_upper_t49; wire v_final_t49;
    
    fp_add_sub u_add_sub_pi4 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_poly_t45), .in_is_sub(1'b1),
        .in_operand_A(CONST_PI_4), .in_operand_B(poly_out_t45),
        .out_valid(v_final_t49), .out_result(y_upper_t49),
        .status_overflow(), .status_zero(), .status_invalid()
    );

    // Trì hoãn kết quả đa thức gốc poly_out thêm 4 chu kỳ để đồng bộ tại chu kỳ T = 49
    wire [31:0] poly_out_t49;
    shift_reg #(.W(32), .D(4)) dly_poly_out_49 (.clk(clk), .in(poly_out_t45), .out(poly_out_t49));

    // Lựa chọn giá trị tuyệt đối của kết quả dựa trên điều kiện biên ban đầu
    wire [31:0] y_abs_t49 = is_upper_t49 ? y_upper_t49 : poly_out_t49;

    // T = 49: Cập nhật cờ hợp lệ và ghép lại bit dấu gốc cho dữ liệu ngõ ra
    assign out_valid = v_final_t49; 
    assign out_result = {sign_x_t49, y_abs_t49[30:0]};

endmodule