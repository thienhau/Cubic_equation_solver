`timescale 1ns / 1ps

module fp_fma #(
    parameter STAGES = 5
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    input  wire [31:0] in_operand_B,
    input  wire [31:0] in_operand_C,
    
    output reg         out_valid,
    output reg  [31:0] out_result,
    output reg         status_overflow,
    output reg         status_underflow,
    output reg         status_invalid,
    output reg         status_zero
);

    // Khai báo các thanh ghi lưu trữ thông tin trung gian cho tầng pipeline thứ nhất
    reg s1_valid, s1_sign_mul, s1_sign_c, s1_is_zero_mul, s1_is_zero_c;
    reg signed [9:0] s1_exp_mul, s1_exp_c;
    reg [23:0] s1_mant_a, s1_mant_b, s1_mant_c;
    reg s1_invalid;

    // Kiểm tra các trạng thái ngoại lệ trực tiếp từ toán hạng đầu vào
    wire a_is_nan  = (&in_operand_A[30:23]) && (|in_operand_A[22:0]);
    wire b_is_nan  = (&in_operand_B[30:23]) && (|in_operand_B[22:0]);
    wire c_is_nan  = (&in_operand_C[30:23]) && (|in_operand_C[22:0]);
    wire a_is_inf  = (&in_operand_A[30:23]) && (~|in_operand_A[22:0]);
    wire b_is_inf  = (&in_operand_B[30:23]) && (~|in_operand_B[22:0]);
    wire c_is_inf  = (&in_operand_C[30:23]) && (~|in_operand_C[22:0]);
    wire mul_is_inf = a_is_inf || b_is_inf;
    wire mul_is_zero = (~|in_operand_A[30:23]) || (~|in_operand_B[30:23]);
    
    // Xác định dấu logic của phép nhân và các điều kiện báo lỗi invalid toán hạng
    wire fma_sign_mul = in_operand_A[31] ^ in_operand_B[31];
    wire inf_minus_inf = (a_is_inf || b_is_inf) && c_is_inf && (fma_sign_mul ^ in_operand_C[31]);
    wire fma_invalid_cond = (a_is_inf && (~|in_operand_B[30:23])) ||
                            (b_is_inf && (~|in_operand_A[30:23])) || 
                            a_is_nan || b_is_nan || c_is_nan || inf_minus_inf;

    // T = 0 -> 1: Thực hiện giải mã toán hạng, tính số mũ sơ bộ và chèn hidden bit
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid       <= 0;
            s1_exp_mul     <= 0; s1_exp_c <= 0;
            s1_mant_a      <= 0; s1_mant_b <= 0; s1_mant_c <= 0;
            s1_is_zero_mul <= 0; s1_is_zero_c <= 0;
            s1_invalid     <= 0;
        end else begin
            s1_valid <= in_valid;
            if (in_valid) begin
                s1_sign_mul    <= fma_sign_mul;
                s1_sign_c      <= in_operand_C[31];
                s1_exp_mul     <= $signed({2'b0, in_operand_A[30:23]}) + $signed({2'b0, in_operand_B[30:23]}) - 10'sd127;
                s1_exp_c       <= $signed({2'b0, in_operand_C[30:23]});
                s1_mant_a      <= (|in_operand_A[30:23]) ? {1'b1, in_operand_A[22:0]} : 24'd0;
                s1_mant_b      <= (|in_operand_B[30:23]) ? {1'b1, in_operand_B[22:0]} : 24'd0;
                s1_mant_c      <= (|in_operand_C[30:23]) ? {1'b1, in_operand_C[22:0]} : 24'd0;
                s1_is_zero_mul <= mul_is_zero;
                s1_is_zero_c   <= (~|in_operand_C[30:23]);
                s1_invalid     <= fma_invalid_cond;
            end
        end
    end

    // Khai báo các thanh ghi lưu trữ thông tin cho tầng pipeline thứ hai
    reg s2_valid, s2_sign_mul, s2_sign_c;
    reg signed [9:0] s2_exp_max;
    reg [47:0] s2_mant_mul;
    reg [72:0] s2_mant_c_aligned;
    reg s2_invalid;

    // T = 1 -> 2: Nhân mantissa đồng thời căn chỉnh dấu chấm động cho toán hạng C
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid          <= 0;
            s2_mant_mul       <= 0; s2_mant_c_aligned <= 0; s2_exp_max <= 0;
            s2_invalid        <= 0;
        end else begin
            s2_valid          <= s1_valid;
            s2_sign_mul       <= s1_sign_mul;
            s2_sign_c         <= s1_sign_c;
            s2_invalid        <= s1_invalid;
            
            if (s1_is_zero_c) begin
                s2_exp_max        <= s1_exp_mul;
                s2_mant_mul       <= (s1_is_zero_mul) ? 48'd0 : (s1_mant_a * s1_mant_b);
                s2_mant_c_aligned <= 73'd0;
            end else if (s1_is_zero_mul) begin
                s2_exp_max        <= s1_exp_c;
                s2_mant_mul       <= 48'd0;
                s2_mant_c_aligned <= {26'd0, s1_mant_c, 23'd0};
            end else if (s1_exp_mul >= s1_exp_c) begin
                s2_exp_max        <= s1_exp_mul;
                s2_mant_mul       <= (s1_mant_a * s1_mant_b); 
                s2_mant_c_aligned <= {26'd0, s1_mant_c, 23'd0} >> (s1_exp_mul - s1_exp_c);
            end else begin
                s2_exp_max        <= s1_exp_c;
                s2_mant_mul       <= (s1_exp_c - s1_exp_mul >= 10'sd48) ?
                                      48'd0 : ((s1_mant_a * s1_mant_b) >> (s1_exp_c - s1_exp_mul));
                s2_mant_c_aligned <= {26'd0, s1_mant_c, 23'd0};
            end
        end
    end

    // Khai báo các thanh ghi lưu trữ thông tin cho tầng pipeline thứ ba
    reg s3_valid, s3_sign_res;
    reg signed [9:0] s3_exp_max;
    reg [72:0] s3_wide_sum;
    reg s3_invalid;
    
    // T = 2 -> 3: Thực hiện phép cộng hoặc trừ góc mantissa trên dải bit mở rộng
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_valid    <= 0;
            s3_wide_sum <= 0; s3_exp_max <= 0;
            s3_invalid  <= 0;
        end else begin
            s3_valid    <= s2_valid;
            s3_exp_max  <= s2_exp_max;
            s3_invalid  <= s2_invalid;
            
            if (s2_sign_mul == s2_sign_c) begin
                s3_wide_sum <= s2_mant_c_aligned + {25'd0, s2_mant_mul};
                s3_sign_res <= s2_sign_mul;
            end else begin
                if (s2_mant_c_aligned >= {25'd0, s2_mant_mul}) begin
                    s3_wide_sum <= s2_mant_c_aligned - {25'd0, s2_mant_mul};
                    s3_sign_res <= s2_sign_c;
                end else begin
                    s3_wide_sum <= {25'd0, s2_mant_mul} - s2_mant_c_aligned;
                    s3_sign_res <= s2_sign_mul;
                end
            end
        end
    end

    // Khai báo các thanh ghi lưu trữ thông tin cho tầng pipeline thứ tư
    reg s4_valid, s4_sign_res;
    reg signed [9:0] s4_exp_res;
    reg [72:0] s4_wide_sum;
    reg [6:0]  s4_lza_shift;
    reg s4_invalid;
    
    integer k; reg [6:0] lza_shift;
    
    // T = 3 -> 4: Dự đoán số lượng bit zero dẫn đầu phục vụ chuẩn hóa kết quả
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s4_valid     <= 0; s4_sign_res  <= 0;
            s4_wide_sum  <= 0; s4_exp_res <= 0; s4_lza_shift <= 0;
            s4_invalid   <= 0;
        end else begin
            s4_valid     <= s3_valid;
            s4_sign_res  <= s3_sign_res;
            s4_wide_sum  <= s3_wide_sum;
            s4_invalid   <= s3_invalid;
            
            if (s3_wide_sum == 0) begin
                s4_exp_res   <= 0;
                s4_lza_shift <= 0;
            end else begin
                lza_shift = 0;
                for (k = 72; k >= 0; k = k - 1) begin
                    if (s3_wide_sum[k] && lza_shift == 0) lza_shift = 72 - k;
                end
                s4_exp_res   <= s3_exp_max - $signed({3'b0, lza_shift}) + 10'sd26;
                s4_lza_shift <= lza_shift;
            end
        end
    end

    // T = 4 -> 5: Thực hiện dịch bit chuẩn hóa, trích xuất grs và thực hiện làm tròn
    wire [72:0] shifted_sum = s4_wide_sum << s4_lza_shift;
    
    // Khai báo các bit guard, round, sticky từ mantissa đã được dịch chỉnh chuẩn hóa
    wire G = shifted_sum[48];
    wire R = shifted_sum[47];
    wire S = |shifted_sum[46:0];
    wire round_up = G & (R | S | shifted_sum[49]);
    
    // Thực hiện cộng bit làm tròn và xác định số mũ cuối cùng sau hiệu chỉnh
    wire [24:0] rounded_mant = {1'b0, shifted_sum[72:49]} + round_up;
    wire signed [10:0] final_exp = s4_exp_res + rounded_mant[24];
    
    // Phân tích trạng thái tràn số mũ dựa trên khung giới hạn định dạng đơn chính xác
    wire fma_overflow  = s4_valid & (final_exp >= 11'sd255) & ~s4_invalid;
    wire fma_underflow = s4_valid & (s4_wide_sum != 0) & (final_exp <= 11'sd0) & ~s4_invalid;
    wire fma_zero      = s4_valid & (s4_wide_sum == 0 || fma_underflow) & ~s4_invalid;

    // Quản lý việc đóng gói dữ liệu và cập nhật các cờ trạng thái ngõ ra module
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid        <= 0; out_result       <= 0;
            status_overflow  <= 0; status_underflow <= 0;
            status_invalid   <= 0; status_zero      <= 0;
        end else begin
            out_valid <= s4_valid;
            if (s4_valid) begin
                if (s4_invalid) begin
                    out_result       <= {s4_sign_res, 8'hFF, 23'h3FFFFF};
                    status_overflow  <= 1'b0; 
                    status_underflow <= 1'b0;
                    status_invalid   <= 1'b1; 
                    status_zero      <= 1'b0;
                end else if (fma_overflow) begin
                    out_result       <= {s4_sign_res, 8'hFF, 23'd0};
                    status_overflow  <= 1'b1; 
                    status_underflow <= 1'b0;
                    status_invalid   <= 1'b0; 
                    status_zero      <= 1'b0;
                end else if (fma_zero) begin
                    out_result       <= 32'd0;
                    status_overflow  <= 1'b0; 
                    status_underflow <= fma_underflow;
                    status_invalid   <= 1'b0; 
                    status_zero      <= 1'b1;
                end else begin
                    out_result       <= {s4_sign_res, final_exp[7:0], rounded_mant[22:0]};
                    status_overflow  <= 1'b0; 
                    status_underflow <= 1'b0;
                    status_invalid   <= 1'b0; 
                    status_zero      <= 1'b0;
                end
            end
        end
    end
endmodule