`timescale 1ns / 1ps

module fp_add_sub #(
    parameter STAGES = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire        in_is_sub,
    input  wire [31:0] in_operand_A,
    input  wire [31:0] in_operand_B,
    
    output reg         out_valid,
    output reg  [31:0] out_result,
    output reg         status_overflow,
    output reg         status_zero
);
    wire        eff_sign_B = in_operand_B[31] ^ in_is_sub;
    wire [23:0] mant_A     = (|in_operand_A[30:23]) ? {1'b1, in_operand_A[22:0]} : 24'd0;
    wire [23:0] mant_B     = (|in_operand_B[30:23]) ? {1'b1, in_operand_B[22:0]} : 24'd0;

    // T = 0 -> 1: Hoán đổi toán hạng (A luôn >= B về độ lớn) và tính hiệu số mũ
    reg s1_valid;
    reg s1_sign_L, s1_sign_S;
    reg [7:0] s1_exp_L;
    reg [7:0] s1_exp_diff;
    reg [23:0] s1_mant_L, s1_mant_S;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
            s1_sign_L <= 1'b0; s1_sign_S <= 1'b0;
            s1_exp_L <= 8'd0; s1_exp_diff <= 8'd0;
            s1_mant_L <= 24'd0; s1_mant_S <= 24'd0;
        end else begin
            s1_valid <= in_valid;
            if (in_valid) begin
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

    wire [4:0]  shift_amt      = (s1_exp_diff > 25) ? 5'd25 : s1_exp_diff[4:0];
    wire [23:0] aligned_mant_S = s1_mant_S >> shift_amt;

    // T = 1 -> 2: Căn lề số nhỏ (Alignment Shift) và thực hiện phép tính thực
    reg s2_valid;
    reg s2_sign_res;
    reg [7:0] s2_exp_L;
    reg [24:0] s2_sum;
    reg s2_is_eff_sub;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 1'b0;
            s2_sign_res <= 1'b0; s2_exp_L <= 8'd0;
            s2_sum <= 25'd0; s2_is_eff_sub <= 1'b0;
        end else begin
            s2_valid <= s1_valid;
            s2_sign_res <= s1_sign_L;
            s2_exp_L <= s1_exp_L;
            s2_is_eff_sub <= s1_sign_L ^ s1_sign_S;
            
            if (s1_sign_L ^ s1_sign_S) begin
                s2_sum <= s1_mant_L - aligned_mant_S;
            end else begin
                s2_sum <= s1_mant_L + aligned_mant_S;
            end
        end
    end

    // T = 2 -> 3: Khối đoán trước số không dẫn đầu (LZA)
    reg s3_valid;
    reg s3_sign_res;
    reg [7:0] s3_exp_L;
    reg [24:0] s3_sum;
    reg [4:0] s3_lza_shift;
    
    integer i;
    reg [4:0] temp_shift; // Thêm biến trung gian để tính toán an toàn

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_valid <= 1'b0;
            s3_sign_res <= 1'b0; s3_exp_L <= 8'd0;
            s3_sum <= 25'd0; s3_lza_shift <= 5'd0;
        end else begin
            s3_valid <= s2_valid;
            s3_sign_res <= s2_sign_res;
            s3_exp_L <= s2_exp_L;
            s3_sum <= s2_sum;
            
            // 1. Tính độ dịch bit vào biến trung gian
            temp_shift = 5'd0;
            if (s2_sum[24]) temp_shift = 5'd0;
            else begin
                begin : lza_loop
                    for (i = 23; i >= 0; i = i - 1) begin
                        if (s2_sum[i]) begin
                            temp_shift = 23 - i;
                            disable lza_loop;
                        end
                    end
                end
            end
            
            // 2. Chốt vào thanh ghi bằng phép gán Non-Blocking (<=) 
            // Điều này tách biệt hoàn toàn Data của các Transaction khác nhau
            s3_lza_shift <= temp_shift;
        end
    end

    reg [8:0]       final_exp_ovf;
    reg signed [9:0] final_exp_norm;
    reg [23:0]      norm_mant;

    // T = 3 -> 4: Chuẩn hóa (Normalize), làm tròn và đóng gói kết quả
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_result <= 32'd0;
            status_zero <= 1'b0;
            status_overflow <= 1'b0;
        end else begin
            out_valid <= s3_valid;
            if (s3_valid) begin
                if (s3_sum == 0) begin
                    out_result <= 32'd0;
                    status_zero <= 1'b1;
                    status_overflow <= 1'b0;
                end else begin
                    status_zero <= 1'b0;
                    if (s3_sum[24]) begin 
                        final_exp_ovf = s3_exp_L + 1;
                        if (final_exp_ovf >= 255) begin
                            out_result <= {s3_sign_res, 8'hFF, 23'd0};
                            status_overflow <= 1'b1;
                        end else begin
                            out_result <= {s3_sign_res, final_exp_ovf[7:0], s3_sum[23:1]};
                            status_overflow <= 1'b0;
                        end
                    end else begin
                        final_exp_norm = $signed({2'b0, s3_exp_L}) - $signed({5'b0, s3_lza_shift});
                        norm_mant = s3_sum[23:0] << s3_lza_shift;
                        
                        if (final_exp_norm <= 0) begin
                            out_result <= {s3_sign_res, 31'd0};
                            status_zero <= 1'b1;
                        end else begin
                            out_result <= {s3_sign_res, final_exp_norm[7:0], norm_mant[22:0]};
                        end
                        status_overflow <= 1'b0;
                    end
                end
            end
        end
    end
endmodule