`timescale 1ns / 1ps

module fp_add_sub #(
    parameter STAGES = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire        in_is_sub, // 0 = Cộng, 1 = Trừ
    input  wire [31:0] in_operand_A,
    input  wire [31:0] in_operand_B,
    
    output reg         out_valid,
    output reg  [31:0] out_result,
    output reg         status_overflow,
    output reg         status_zero
);

    // ==========================================
    // STAGE 1: Hoán đổi Toán hạng (A luôn >= B về độ lớn) & Tính hiệu số mũ
    // ==========================================
    reg s1_valid;
    reg s1_sign_L, s1_sign_S;
    reg [7:0] s1_exp_L;
    reg [7:0] s1_exp_diff;
    reg [23:0] s1_mant_L, s1_mant_S;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
            // ... reset
        end else begin
            s1_valid <= in_valid;
            if (in_valid) begin
                // Lật dấu B nếu là phép trừ
                wire eff_sign_B = in_operand_B[31] ^ in_is_sub;
                
                // Trích xuất Mantissa (cấy hidden bit 1)
                wire [23:0] mant_A = (|in_operand_A[30:23]) ? {1'b1, in_operand_A[22:0]} : 24'd0;
                wire [23:0] mant_B = (|in_operand_B[30:23]) ? {1'b1, in_operand_B[22:0]} : 24'd0;
                
                // So sánh Magnitude để quyết định Large (L) và Small (S)
                if (in_operand_A[30:0] >= in_operand_B[30:0]) begin
                    s1_sign_L <= in_operand_A[31];
                    s1_sign_S <= eff_sign_B;
                    s1_exp_L  <= in_operand_A[30:23];
                    s1_exp_diff <= in_operand_A[30:23] - in_operand_B[30:23];
                    s1_mant_L <= mant_A;
                    s1_mant_S <= mant_B;
                end else begin
                    s1_sign_L <= eff_sign_B;
                    s1_sign_S <= in_operand_A[31];
                    s1_exp_L  <= in_operand_B[30:23];
                    s1_exp_diff <= in_operand_B[30:23] - in_operand_A[30:23];
                    s1_mant_L <= mant_B;
                    s1_mant_S <= mant_A;
                end
            end
        end
    end

    // ==========================================
    // STAGE 2: Căn lề số nhỏ (Alignment Shift) & Chọn phép tính Thực
    // ==========================================
    reg s2_valid;
    reg s2_sign_res;
    reg [7:0] s2_exp_L;
    reg [24:0] s2_sum; // +1 bit carry
    reg s2_is_eff_sub;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 1'b0;
        end else begin
            s2_valid <= s1_valid;
            s2_sign_res <= s1_sign_L;
            s2_exp_L <= s1_exp_L;
            
            // Effective operation: Cùng dấu -> Cộng, Trái dấu -> Trừ
            s2_is_eff_sub <= s1_sign_L ^ s1_sign_S;
            
            // Giới hạn dịch lớn nhất là 25 bit (mantissa biến mất)
            wire [4:0] shift_amt = (s1_exp_diff > 25) ? 5'd25 : s1_exp_diff[4:0];
            wire [23:0] aligned_mant_S = s1_mant_S >> shift_amt;
            
            if (s1_sign_L ^ s1_sign_S) begin
                s2_sum <= s1_mant_L - aligned_mant_S; // Phép trừ thực tế
            end else begin
                s2_sum <= s1_mant_L + aligned_mant_S; // Phép cộng thực tế
            end
        end
    end

    // ==========================================
    // STAGE 3: LZA (Leading Zero Anticipator)
    // ==========================================
    reg s3_valid;
    reg s3_sign_res;
    reg [7:0] s3_exp_L;
    reg [24:0] s3_sum;
    reg [4:0] s3_lza_shift; // Đếm số 0 dẫn đầu (Tối đa dịch 24)

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_valid <= 1'b0;
        end else begin
            s3_valid <= s2_valid;
            s3_sign_res <= s2_sign_res;
            s3_exp_L <= s2_exp_L;
            s3_sum <= s2_sum;
            
            // Priority Encoder đơn giản tìm vị trí bit 1 cao nhất
            s3_lza_shift = 0;
            if (s2_sum[24]) s3_lza_shift = 5'd0; // Carry out
            else begin
                for (i = 23; i >= 0; i = i - 1) begin
                    if (s2_sum[i]) begin
                        s3_lza_shift = 23 - i;
                        break;
                    end
                end
            end
        end
    end

    // ==========================================
    // STAGE 4: Normalize, Round & Pack
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_result <= 32'd0;
            status_zero <= 1'b0;
            status_overflow <= 1'b0;
        end else begin
            out_valid <= s3_valid;
            if (s3_valid) begin
                if (s3_sum == 0) begin // Triệt tiêu sạch Mantissa
                    out_result <= 32'd0;
                    status_zero <= 1'b1;
                    status_overflow <= 1'b0;
                end else begin
                    status_zero <= 1'b0;
                    
                    if (s3_sum[24]) begin 
                        // Trường hợp có Carry: Dịch phải 1, tăng số mũ 1
                        wire [8:0] final_exp = s3_exp_L + 1;
                        if (final_exp >= 255) begin
                            out_result <= {s3_sign_res, 8'hFF, 23'd0}; // Overflow
                            status_overflow <= 1'b1;
                        end else begin
                            out_result <= {s3_sign_res, final_exp[7:0], s3_sum[23:1]};
                            status_overflow <= 1'b0;
                        end
                    end else begin
                        // Trường hợp bình thường hoặc cần chuẩn hóa do trừ
                        wire signed [9:0] final_exp = $signed({2'b0, s3_exp_L}) - $signed({5'b0, s3_lza_shift});
                        wire [23:0] norm_mant = s3_sum[23:0] << s3_lza_shift;
                        
                        if (final_exp <= 0) begin // Underflow (Flush to zero)
                            out_result <= {s3_sign_res, 31'd0};
                            status_zero <= 1'b1;
                        end else begin
                            out_result <= {s3_sign_res, final_exp[7:0], norm_mant[22:0]};
                        end
                        status_overflow <= 1'b0;
                    end
                end
            end
        end
    end
endmodule