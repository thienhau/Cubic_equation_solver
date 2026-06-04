`timescale 1ns / 1ps

module fp_sqrt #(
    parameter STAGES = 18
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output wire        out_valid,
    output wire [31:0] out_result,
    output wire        status_invalid 
);

    // T = 0: Phát hiện các trường hợp ngoại lệ (NaN, Infinity, Zero)
    wire is_nan = (&in_operand_A[30:23]) && (|in_operand_A[22:0]);
    wire is_inf = (&in_operand_A[30:23]) && (~|in_operand_A[22:0]);
    wire is_zero = ~|in_operand_A[30:23];
    
    // Số âm (khác zero) hoặc NaN được coi là đầu vào không hợp lệ cho căn bậc hai
    wire is_invalid_input = is_nan || (in_operand_A[31] && !is_zero); 
    
    // Trễ các tín hiệu ngoại lệ để đồng bộ với ngõ ra sau 18 chu kỳ
    wire invalid_d18, inf_d18;
    shift_reg #(.W(1), .D(18)) dly_inv (.clk(clk), .in(is_invalid_input), .out(invalid_d18));
    shift_reg #(.W(1), .D(18)) dly_inf (.clk(clk), .in(is_inf && !in_operand_A[31]), .out(inf_d18));

    // T = 0 -> 1: tính toán số mũ, chuẩn hóa mantissa và truy xuất ROM
    // Tính toán số mũ thực tế (bỏ bias 127) và chia đôi cho phép toán căn bậc hai
    wire signed [8:0] e_diff = $signed({1'b0, in_operand_A[30:23]}) - 9'sd127;
    wire [7:0] k_exp = e_diff >>> 1;
    
    // Nếu số mũ lẻ, cần dịch mantissa để đưa về dạng chuẩn hóa thích hợp
    wire [31:0] w_fp = (e_diff[0]) ? {1'b0, 8'd128, in_operand_A[22:0]} : {1'b0, 8'd127, in_operand_A[22:0]};
    
    // Tra bảng tìm giá trị xấp xỉ ban đầu y0 dựa trên 12-bit MSB của mantissa
    wire [31:0] y0_rom;
    pade_sqrt_rom u_rom (
        .clk(clk), 
        .addr(w_fp[22:11]),
        .data_out(y0_rom)
    );

    // Pipeline tầng 1: lưu trữ các giá trị trung gian từ T = 0 sang T = 1
    reg [31:0] w_d1; reg [7:0] k_d1; reg v_d1; reg e_odd_d1;
    always @(posedge clk) begin 
        w_d1     <= w_fp;
        k_d1     <= k_exp;
        v_d1     <= in_valid; 
        e_odd_d1 <= e_diff[0];
    end

    // T = 1: xử lý tỉ lệ (scaling) cho dự đoán ban đầu và thực hiện làm tròn GRS
    // Mở rộng mantissa thêm 12-bit zero về phía dưới thành dạng 36-bit để tăng độ chính xác
    wire [35:0] m_y0_ext = {1'b1, y0_rom[22:0], 12'b0}; 
    
    // Nhân dịch bit xấp xỉ với hằng số 1/sqrt(2) khi số mũ ban đầu là số lẻ
    wire [35:0] y0_scaled_odd_ext = (m_y0_ext >> 1) + (m_y0_ext >> 3) + (m_y0_ext >> 4) + 
                                    (m_y0_ext >> 6) + (m_y0_ext >> 8) + (m_y0_ext >> 14) + (m_y0_ext >> 17);
                                    
    wire [35:0] y0_scaled_ext = e_odd_d1 ? y0_scaled_odd_ext : m_y0_ext;
    
    // Kiểm tra bit nguyên để xác định nhu cầu dịch chỉnh góc mantissa
    wire shift_req = ~y0_scaled_ext[35];
    
    // Trích xuất 25-bit thô chứa hidden bit và phần phân số để chuẩn bị làm tròn
    wire [24:0] y0_mant_raw = shift_req ? y0_scaled_ext[34:10] : y0_scaled_ext[35:11];
    
    // Xác định các bit guard (G), round (R), và sticky (S) phục vụ thuật toán làm tròn RNE
    wire y0_G = shift_req ? y0_scaled_ext[9] : y0_scaled_ext[10];
    wire y0_R = shift_req ? y0_scaled_ext[8] : y0_scaled_ext[9];
    wire y0_S = shift_req ? (|y0_scaled_ext[7:0]) : (|y0_scaled_ext[8:0]);
    
    // Thực hiện logic làm tròn theo phương thức round to nearest, ties to even (RNE)
    wire y0_rnd = y0_G & (y0_R | y0_S | y0_mant_raw[0]);
    wire [23:0] y0_mant_final = y0_mant_raw[24:1] + y0_rnd;
    
    // Hiệu chỉnh lại số mũ của y0 sau khi dịch mantissa
    wire [7:0]  final_y0_exp  = y0_rom[30:23] - shift_req;
    wire [31:0] y0 = {y0_rom[31], final_y0_exp, y0_mant_final[22:0]};

    // T = 1 -> 5: thực hiện phép tính bình phương y0 * y0
    wire [31:0] t1; wire v_t1;
    fp_mul u_mul1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_d1), 
        .in_operand_A(y0), .in_operand_B(y0), 
        .out_valid(v_t1), .out_result(t1), 
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Trì hoãn các tín hiệu phối hợp song song với bộ nhân u_mul1 (4 chu kỳ)
    wire [31:0] w_d5, y0_d5; wire [7:0] k_d5;
    shift_reg #(.W(32), .D(4)) dly_w5  (.clk(clk), .in(w_d1),  .out(w_d5));
    shift_reg #(.W(32), .D(4)) dly_y5  (.clk(clk), .in(y0),    .out(y0_d5));
    shift_reg #(.W(8),  .D(4)) dly_k5  (.clk(clk), .in(k_d1),  .out(k_d5));

    // T = 5 -> 10: thực hiện phép tính nhân cộng fma (3/2 - 0.5 * w * t1)
    // Tạo giá trị (-0.5 * w) bằng cách đảo bit dấu và giảm số mũ đi 1 đơn vị
    wire [31:0] neg_half_w = {~w_d5[31], w_d5[30:23] - 8'd1, w_d5[22:0]};
    wire [31:0] t2; wire v_t2;
    fp_fma u_fma1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t1), 
        .in_operand_A(neg_half_w), .in_operand_B(t1), .in_operand_C(32'h3FC00000), // h3FC00000 là 1.5 ở định dạng fp32
        .out_valid(v_t2), .out_result(t2),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Trì hoãn các tín hiệu phối hợp song song với bộ fma u_fma1 (5 chu kỳ)
    wire [31:0] w_d10, y0_d10; wire [7:0] k_d10;
    shift_reg #(.W(32), .D(5)) dly_w10 (.clk(clk), .in(w_d5),  .out(w_d10));
    shift_reg #(.W(32), .D(5)) dly_y10 (.clk(clk), .in(y0_d5), .out(y0_d10));
    shift_reg #(.W(8),  .D(5)) dly_k10 (.clk(clk), .in(k_d5),  .out(k_d10));

    // T = 10 -> 14: thực hiện cập nhật giá trị xấp xỉ bậc cao y1 = y0 * t2
    wire [31:0] y1; wire v_t3;
    fp_mul u_mul2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t2), 
        .in_operand_A(y0_d10), .in_operand_B(t2), 
        .out_valid(v_t3), .out_result(y1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Trì hoãn các tín hiệu phối hợp song song với bộ nhân u_mul2 (4 chu kỳ)
    wire [31:0] w_d14; wire [7:0] k_d14;
    shift_reg #(.W(32), .D(4)) dly_w14 (.clk(clk), .in(w_d10), .out(w_d14));
    shift_reg #(.W(8),  .D(4)) dly_k14 (.clk(clk), .in(k_d10), .out(k_d14));

    // T = 14 -> 18: tính toán kết quả căn bậc hai thô sqrt_raw = w * y1
    wire [31:0] sqrt_raw; wire v_out;
    fp_mul u_mul3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t3), 
        .in_operand_A(w_d14), .in_operand_B(y1), 
        .out_valid(v_out), .out_result(sqrt_raw),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Trì hoãn số mũ k_exp thêm 4 chu kỳ cuối cùng để đồng bộ tại T = 18
    wire [7:0] k_d18;
    shift_reg #(.W(8), .D(4)) dly_k18 (.clk(clk), .in(k_d14), .out(k_d18));

    // Trì hoãn bit dấu và trạng thái zero của toán hạng đầu vào đến chu kỳ thứ 18
    wire sign_d18, z_d18;
    shift_reg #(.W(1), .D(18)) dly_sign (.clk(clk), .in(in_operand_A[31]), .out(sign_d18));
    shift_reg #(.W(1), .D(18)) dly_z    (.clk(clk), .in(is_zero),          .out(z_d18));

    // Kết nối các ngõ ra hợp lệ và báo lỗi
    assign out_valid = v_out;
    assign status_invalid = invalid_d18;

    // T = 18: Lựa chọn kết quả ngõ ra dựa trên kết quả tính toán hoặc các trường hợp ngoại lệ
    assign out_result = invalid_d18 ? 32'h7FC00000 : 
                        inf_d18     ? 32'h7F800000 : 
                        z_d18       ? {sign_d18, 31'd0} : 
                                      {1'b0, sqrt_raw[30:23] + k_d18, sqrt_raw[22:0]};

endmodule