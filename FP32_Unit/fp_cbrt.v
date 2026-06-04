`timescale 1ns / 1ps

module fp_cbrt #(
    parameter STAGES = 26
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output wire        out_valid,
    output wire [31:0] out_result
);

    // T = 0 -> 1: Tiền xử lý toán hạng đầu vào và truy xuất bảng tìm kiếm ROM
    // Tính toán số mũ thực tế sau khi loại bỏ số bias 127
    wire signed [9:0] e_diff = $signed({2'b00, in_operand_A[30:23]}) - 10'sd127;
    
    // Thực hiện chia 3 lấy nguyên đối với số mũ thực tế cho phép toán căn bậc ba
    wire signed [9:0] k_signed = (e_diff >= 0) ? (e_diff / 3) : ((e_diff - 2) / 3);
    
    // Tính toán số dư r để xác định hệ số dịch chỉnh cho phần phân số mantissa
    wire [1:0] r = e_diff - k_signed * 3;
    
    // Khôi phục số mũ mới về dạng có bias 127 phục vụ cho ngõ ra sau này
    wire [7:0] k_exp = k_signed + 8'd127;
    
    // Chuẩn hóa mantissa ban đầu dựa trên giá trị số dư r thu được
    wire [31:0] w_fp = {1'b0, 8'd127 + {6'd0, r}, in_operand_A[22:0]};
    
    // Lưu trữ lại bit dấu ban đầu vì căn bậc ba của số âm vẫn là số âm hợp lệ
    wire sign_res = in_operand_A[31];
    
    // Truy cập bảng Rom chứa giá trị xấp xỉ ban đầu y0 dựa trên 12-bit msb của mantissa
    wire [31:0] y0_rom;
    pade_cbrt_rom u_rom (
        .clk(clk), 
        .addr(w_fp[22:11]),
        .data_out(y0_rom)
    );

    // Pipeline tầng 1: Lưu trữ các giá trị trung gian từ chu kỳ T = 0 sang T = 1
    reg [31:0] w_d1; reg [7:0] k_d1; reg v_d1; reg s_d1; reg [1:0] r_d1;
    always @(posedge clk) begin 
        w_d1 <= w_fp; k_d1 <= k_exp;
        v_d1 <= in_valid; s_d1 <= sign_res; 
        r_d1 <= r;
    end

    // T = 1 -> 2: Khởi tạo chuỗi dịch bit song song để chuẩn bị chia 3 cho mantissa
    // Mở rộng mantissa thêm 12-bit không về phía dưới để tăng độ phân giải tính toán
    wire [35:0] m_w_early = {1'b1, w_d1[22:0], 12'b0};
    reg [35:0] w3_sumA, w3_sumB, w3_sumC;
    reg [31:0] w_d2_reg, w_d3_reg;
    
    // Chia nhỏ việc dịch cộng các số hạng xấp xỉ chuỗi hình học thành 3 nhóm thanh ghi song song
    always @(posedge clk) begin
        w3_sumA  <= (m_w_early>>2)  + (m_w_early>>4)  + (m_w_early>>6)  + (m_w_early>>8)  + (m_w_early>>10);
        w3_sumB  <= (m_w_early>>12) + (m_w_early>>14) + (m_w_early>>16) + (m_w_early>>18) + (m_w_early>>20);
        w3_sumC  <= (m_w_early>>22) + (m_w_early>>24) + (m_w_early>>26) + (m_w_early>>28) + (m_w_early>>30);
        w_d2_reg <= w_d1;
    end
    
    // T = 2 -> 3: Cộng tổng hợp các nhóm số hạng xấp xỉ lại với nhau
    reg [35:0] w3_sum;
    always @(posedge clk) begin
        w3_sum   <= w3_sumA + w3_sumB + w3_sumC;
        w_d3_reg <= w_d2_reg;
    end
    
    // T = 3 -> 4: Thực hiện trích xuất grs và làm tròn rne cho kết quả chia 3
    // Kiểm tra bit chuẩn hóa tại vị trí số 34 để xác định khung dữ liệu trích xuất
    wire norm = w3_sum[34];
    wire [24:0] w3_mant_raw = norm ? w3_sum[34:10] : w3_sum[33:9];
    
    // Xác định các bit guard (G), round (R), và sticky (S) từ phần đuôi bị loại bỏ
    wire w3_G = norm ? w3_sum[9] : w3_sum[8];
    wire w3_R = norm ? w3_sum[8] : w3_sum[7];
    wire w3_S = norm ? (|w3_sum[7:0]) : (|w3_sum[6:0]);
    
    // Thực hiện logic làm tròn theo phương thức round to nearest, ties to even (RNE)
    wire w3_rnd = w3_G & (w3_R | w3_S | w3_mant_raw[0]);
    wire [23:0] w3_mant_rnd = w3_mant_raw[24:1] + w3_rnd;
    
    // Đóng gói kết quả âm của phép chia 3 vào thanh ghi và hiệu chỉnh lại số mũ tương ứng
    reg [31:0] neg_w_third_reg;
    always @(posedge clk) begin
        neg_w_third_reg <= norm ?
            {1'b1, w_d3_reg[30:23] - 8'd1, w3_mant_rnd[22:0]} :
            {1'b1, w_d3_reg[30:23] - 8'd2, w3_mant_rnd[22:0]};
    end
    
    // Đẩy giá trị (-w/3) vào hàng đợi để đồng bộ với tiến trình tính toán chính
    wire [31:0] neg_w_third;
    shift_reg #(.W(32), .D(5)) dly_nwt (.clk(clk), .in(neg_w_third_reg), .out(neg_w_third));

    // T = 1: Thực hiện tỉ lệ hóa và làm tròn grs cho giá trị y0 tra từ bảng Rom
    // Mở rộng dữ liệu mantissa từ Rom phục vụ cho việc dịch nhân chính xác
    wire [35:0] m_y0_ext = {1'b1, y0_rom[22:0], 12'b0};
    
    // Tính toán chuỗi dịch bit xấp xỉ hằng số tỉ lệ trong trường hợp số dư r bằng 1
    wire [35:0] y0_r1_ext = (m_y0_ext>>1) + (m_y0_ext>>2) + (m_y0_ext>>5) + (m_y0_ext>>7) + (m_y0_ext>>8) + 
                            (m_y0_ext>>11) + (m_y0_ext>>13) + (m_y0_ext>>14) + (m_y0_ext>>16);
                            
    // Tính toán chuỗi dịch bit xấp xỉ hằng số tỉ lệ trong trường hợp số dư r bằng 2
    wire [35:0] y0_r2_ext = (m_y0_ext>>1) + (m_y0_ext>>3) + (m_y0_ext>>8) + (m_y0_ext>>10) + (m_y0_ext>>12) + 
                            (m_y0_ext>>15) + (m_y0_ext>>19);
                            
    // Lựa chọn chuỗi hằng số phù hợp dựa trên số dư r thu được từ tầng trước
    wire [35:0] y0_scaled_ext = (r_d1 == 2) ? y0_r2_ext : ((r_d1 == 1) ? y0_r1_ext : m_y0_ext);
    
    // Kiểm tra bit nguyên để xác định nhu cầu hiệu chỉnh dịch bit của mantissa
    wire shift_req = ~y0_scaled_ext[35];
    wire [24:0] y0_mant_raw = shift_req ? y0_scaled_ext[34:10] : y0_scaled_ext[35:11];
    
    // Trích xuất các bit guard, round, sticky cho quá trình làm tròn y0
    wire y0_G = shift_req ? y0_scaled_ext[9] : y0_scaled_ext[10];
    wire y0_R = shift_req ? y0_scaled_ext[8] : y0_scaled_ext[9];
    wire y0_S = shift_req ? (|y0_scaled_ext[7:0]) : (|y0_scaled_ext[8:0]);
    wire y0_rnd = y0_G & (y0_R | y0_S | y0_mant_raw[0]);
    wire [23:0] y0_mant_final = y0_mant_raw[24:1] + y0_rnd;
    
    // Cập nhật số mũ và đóng gói hoàn chỉnh cấu trúc số thực dấu chấm động cho y0
    wire [7:0]  final_y0_exp  = y0_rom[30:23] - shift_req;
    wire [31:0] y0 = (r_d1 == 0) ? y0_rom : {y0_rom[31], final_y0_exp, y0_mant_final[22:0]};

    // T = 1 -> 5: Tính toán phép bình phương sơ bộ t1 = y0 * y0
    wire [31:0] t1; wire v_t1;
    fp_mul u_mul1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_d1), 
        .in_operand_A(y0), .in_operand_B(y0), 
        .out_valid(v_t1), .out_result(t1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Trì hoãn các tín hiệu phối hợp song song với bộ nhân u_mul1 (4 chu kỳ)
    wire [31:0] w_d5, y0_d5; wire [7:0] k_d5; wire s_d5;
    shift_reg #(.W(32), .D(4)) dw5 (.clk(clk), .in(w_d1),  .out(w_d5));
    shift_reg #(.W(32), .D(4)) dy5 (.clk(clk), .in(y0),    .out(y0_d5));
    shift_reg #(.W(8),  .D(4)) dk5 (.clk(clk), .in(k_d1),  .out(k_d5));
    shift_reg #(.W(1),  .D(4)) ds5 (.clk(clk), .in(s_d1),  .out(s_d5));
    
    // T = 5 -> 9: Tính toán phép toán bậc ba t2 = y0 * t1
    wire [31:0] t2; wire v_t2;
    fp_mul u_mul2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t1), 
        .in_operand_A(y0_d5), .in_operand_B(t1), 
        .out_valid(v_t2), .out_result(t2),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Trì hoãn các tín hiệu phối hợp song song với bộ nhân u_mul2 (4 chu kỳ)
    wire [31:0] w_d9, y0_d9; wire [7:0] k_d9; wire s_d9;
    shift_reg #(.W(32), .D(4)) dw9 (.clk(clk), .in(w_d5),  .out(w_d9));
    shift_reg #(.W(32), .D(4)) dy9 (.clk(clk), .in(y0_d5), .out(y0_d9));
    shift_reg #(.W(8),  .D(4)) dk9 (.clk(clk), .in(k_d5),  .out(k_d9));
    shift_reg #(.W(1),  .D(4)) ds9 (.clk(clk), .in(s_d5),  .out(s_d9));
    
    // T = 9 -> 14: Thực hiện phép toán nhân cộng fma tìm giá trị trung gian t3 = (-w/3) * t2 + 4/3
    // Giá trị h3FAAAAAB đại diện cho hằng số thực 4/3 định dạng fp32
    wire [31:0] t3; wire v_t3;
    fp_fma u_fma1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t2), 
        .in_operand_A(neg_w_third), .in_operand_B(t2), .in_operand_C(32'h3FAAAAAB), 
        .out_valid(v_t3), .out_result(t3),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Trì hoãn các tín hiệu phối hợp song song với bộ fma u_fma1 (5 chu kỳ)
    wire [31:0] w_d14, y0_d14; wire [7:0] k_d14; wire s_d14;
    shift_reg #(.W(32), .D(5)) dw14 (.clk(clk), .in(w_d9),  .out(w_d14));
    shift_reg #(.W(32), .D(5)) dy14 (.clk(clk), .in(y0_d9), .out(y0_d14));
    shift_reg #(.W(8),  .D(5)) dk14 (.clk(clk), .in(k_d9),  .out(k_d14));
    shift_reg #(.W(1),  .D(5)) ds14 (.clk(clk), .in(s_d9),  .out(s_d14));
    
    // T = 14 -> 18: Tính toán cập nhật giá trị xấp xỉ bậc cao y1 = y0 * t3
    wire [31:0] y1; wire v_t4;
    fp_mul u_mul3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t3), 
        .in_operand_A(y0_d14), .in_operand_B(t3), 
        .out_valid(v_t4), .out_result(y1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Trì hoãn các tín hiệu phối hợp song song với bộ nhân u_mul3 (4 chu kỳ)
    wire [31:0] w_d18; wire [7:0] k_d18; wire s_d18;
    shift_reg #(.W(32), .D(4)) dw18 (.clk(clk), .in(w_d14), .out(w_d18));
    shift_reg #(.W(8),  .D(4)) dk18 (.clk(clk), .in(k_d14), .out(k_d18)); 
    shift_reg #(.W(1),  .D(4)) ds18 (.clk(clk), .in(s_d14), .out(s_d18));

    // T = 18 -> 22: Bình phương giá trị xấp xỉ bậc cao t4 = y1 * y1
    wire [31:0] t4; wire v_t5;
    fp_mul u_mul4 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t4), 
        .in_operand_A(y1), .in_operand_B(y1), 
        .out_valid(v_t5), .out_result(t4),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Trì hoãn các tín hiệu phối hợp song song với bộ nhân u_mul4 (4 chu kỳ)
    wire [31:0] w_d22; wire [7:0] k_d22; wire s_d22;
    shift_reg #(.W(32), .D(4)) dw22 (.clk(clk), .in(w_d18), .out(w_d22));
    shift_reg #(.W(8),  .D(4)) dk22 (.clk(clk), .in(k_d18), .out(k_d22)); 
    shift_reg #(.W(1),  .D(4)) ds22 (.clk(clk), .in(s_d18), .out(s_d22));

    // T = 22 -> 26: Tính toán kết quả căn bậc ba thô ngõ ra raw = w * t4
    wire [31:0] raw; wire v_out;
    fp_mul u_mul5 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_t5), 
        .in_operand_A(w_d22), .in_operand_B(t4), 
        .out_valid(v_out), .out_result(raw),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // Trì hoãn số mũ và bit dấu thêm 4 chu kỳ cuối cùng để đồng bộ tại T = 26
    wire [7:0] k_d26; wire s_d26;
    shift_reg #(.W(8), .D(4)) dk26 (.clk(clk), .in(k_d22), .out(k_d26));
    shift_reg #(.W(1), .D(4)) ds26 (.clk(clk), .in(s_d22), .out(s_d26));

    // Trì hoãn cờ trạng thái kiểm tra đầu vào bằng không suốt 26 tầng pipeline
    wire in_is_zero_d26;
    shift_reg #(.W(1), .D(26)) d_zero (.clk(clk), .in(~|in_operand_A[30:23]), .out(in_is_zero_d26));

    // Ánh xạ tín hiệu hợp lệ ra ngoài cổng out_valid
    assign out_valid = v_out;
    
    // T = 26: Lựa chọn và hiệu chỉnh số mũ kết quả cuối cùng đưa ra ngoài module
    assign out_result = in_is_zero_d26 ? 32'd0 : {s_d26, raw[30:23] + k_d26 - 8'd127, raw[22:0]};

endmodule