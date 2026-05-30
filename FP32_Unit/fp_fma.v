`timescale 1ns / 1ps

module fp_fma #(
    parameter STAGES = 5 // Pipeline 5-stage cho FMA sieu rong
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

    // ==========================================
    // STAGE 1: Giải Mã, Tính Hiệu Số Mũ & Khởi tạo Nhân
    // ==========================================
    reg        s1_valid;
    reg        s1_sign_mul, s1_sign_c;
    reg [9:0]  s1_exp_mul, s1_exp_c;
    reg [23:0] s1_mant_a, s1_mant_b, s1_mant_c;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
            // ... reset registers
        end else begin
            s1_valid <= in_valid;
            if (in_valid) begin
                s1_sign_mul <= in_operand_A[31] ^ in_operand_B[31];
                s1_sign_c   <= in_operand_C[31];
                
                s1_exp_mul  <= in_operand_A[30:23] + in_operand_B[30:23] - 8'd127;
                s1_exp_c    <= in_operand_C[30:23];
                
                s1_mant_a <= (|in_operand_A[30:23]) ? {1'b1, in_operand_A[22:0]} : 24'd0;
                s1_mant_b <= (|in_operand_B[30:23]) ? {1'b1, in_operand_B[22:0]} : 24'd0;
                s1_mant_c <= (|in_operand_C[30:23]) ? {1'b1, in_operand_C[22:0]} : 24'd0;
            end
        end
    end

    // ==========================================
    // STAGE 2: Tích trung gian & Căn lề góc rộng cho C
    // ==========================================
    reg        s2_valid;
    reg        s2_sign_mul, s2_sign_c;
    reg [9:0]  s2_exp_max;
    reg [47:0] s2_mant_mul;
    reg [71:0] s2_mant_c_aligned; // Cần đủ rộng để dịch trái/phải tương đối so với Tích

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 1'b0;
        end else begin
            s2_valid    <= s1_valid;
            s2_sign_mul <= s1_sign_mul;
            s2_sign_c   <= s1_sign_c;
            
            // Thực hiện nhân không làm tròn (48 bit)
            s2_mant_mul <= s1_mant_a * s1_mant_b;
            
            // So sánh số mũ để căn lề C. Đặt tích A*B ở giữa vector 72-bit.
            if (s1_exp_mul >= s1_exp_c) begin
                s2_exp_max <= s1_exp_mul;
                // Dịch phải C nếu số mũ C nhỏ hơn
                s2_mant_c_aligned <= {24'd0, s1_mant_c, 24'd0} >> (s1_exp_mul - s1_exp_c);
            end else begin
                s2_exp_max <= s1_exp_c;
                // Nếu exp_c lớn hơn, tương đương với việc dịch trái C (hoặc dịch phải Tích ở Stage 3)
                s2_mant_c_aligned <= {24'd0, s1_mant_c, 24'd0} << (s1_exp_c - s1_exp_mul);
            end
        end
    end

    // ==========================================
    // STAGE 3: Bộ Cộng Siêu Rộng Dual-Path (Wide CPA)
    // ==========================================
    reg        s3_valid;
    reg        s3_sign_res;
    reg [9:0]  s3_exp_res;
    reg [72:0] s3_wide_sum; // Thêm 1 bit carry

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_valid <= 1'b0;
        end else begin
            s3_valid   <= s2_valid;
            s3_exp_res <= s2_exp_max;
            
            // Xử lý cộng/trừ dựa trên dấu
            if (s2_sign_mul == s2_sign_c) begin
                s3_wide_sum <= {24'd0, s2_mant_mul} + s2_mant_c_aligned;
                s3_sign_res <= s2_sign_mul;
            end else begin
                if ({24'd0, s2_mant_mul} >= s2_mant_c_aligned) begin
                    s3_wide_sum <= {24'd0, s2_mant_mul} - s2_mant_c_aligned;
                    s3_sign_res <= s2_sign_mul;
                end else begin
                    s3_wide_sum <= s2_mant_c_aligned - {24'd0, s2_mant_mul};
                    s3_sign_res <= s2_sign_c;
                end
            end
        end
    end

    // ==========================================
    // STAGE 4: LZA & Chuẩn Hóa (Normalization)
    // ==========================================
    reg        s4_valid;
    reg        s4_sign_res;
    reg [9:0]  s4_exp_res;
    reg [47:0] s4_mant_norm; // Trích xuất lại khoảng giá trị hữu ích

    // Logic mô phỏng mạch Priority Encoder (LZA) đếm số 0 dẫn đầu
    integer i;
    reg [6:0] lza_shift;
    always @* begin
        lza_shift = 0;
        for (i = 72; i >= 0; i = i - 1) begin
            if (s3_wide_sum[i]) begin
                lza_shift = 72 - i;
                break;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s4_valid <= 1'b0;
        end else begin
            s4_valid <= s3_valid;
            s4_sign_res <= s3_sign_res;
            
            // Dịch trái để chuẩn hóa bit '1' về vị trí cao nhất (ẩn)
            if (s3_wide_sum == 0) begin
                s4_exp_res <= 0;
                s4_mant_norm <= 0;
            end else begin
                s4_exp_res <= s3_exp_res - lza_shift + 1; // Điều chỉnh số mũ
                s4_mant_norm <= (s3_wide_sum << lza_shift) >> 24; // Cắt lấy 48-bit định trị hiệu quả
            end
        end
    end

    // ==========================================
    // STAGE 5: Làm Tròn IEEE-754 & Pack (Single Rounding)
    // ==========================================
    wire guard_bit  = s4_mant_norm[23];
    wire round_bit  = s4_mant_norm[22];
    wire sticky_bit = |s4_mant_norm[21:0];
    wire round_up   = guard_bit & (round_bit | sticky_bit | s4_mant_norm[24]);
    
    wire [23:0] final_mant = s4_mant_norm[47:24] + round_up;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_result <= 32'd0;
            status_zero <= 1'b0;
            status_overflow <= 1'b0;
        end else begin
            out_valid <= s4_valid;
            if (s4_valid) begin
                if (s4_exp_res == 0 || s4_mant_norm == 0) begin // Zero/Underflow
                    out_result <= {s4_sign_res, 31'd0};
                    status_zero <= 1'b1;
                    status_overflow <= 1'b0;
                end else if (s4_exp_res >= 255) begin // Overflow
                    out_result <= {s4_sign_res, 8'hFF, 23'd0};
                    status_overflow <= 1'b1;
                    status_zero <= 1'b0;
                end else begin
                    out_result <= {s4_sign_res, s4_exp_res[7:0], final_mant[22:0]};
                    status_zero <= 1'b0;
                    status_overflow <= 1'b0;
                end
            end
        end
    end
endmodule