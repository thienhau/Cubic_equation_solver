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
    // --- STAGE 1: Setup ---
    reg s1_valid, s1_sign_mul, s1_sign_c, s1_is_zero_mul, s1_is_zero_c;
    reg signed [9:0] s1_exp_mul, s1_exp_c;
    reg [23:0] s1_mant_a, s1_mant_b, s1_mant_c;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 0;
            s1_exp_mul <= 0; s1_exp_c <= 0;
            s1_mant_a <= 0; s1_mant_b <= 0; s1_mant_c <= 0;
            s1_is_zero_mul <= 0; s1_is_zero_c <= 0;
        end else begin
            s1_valid <= in_valid;
            if (in_valid) begin
                s1_sign_mul <= in_operand_A[31] ^ in_operand_B[31];
                s1_sign_c   <= in_operand_C[31];
                
                s1_exp_mul <= $signed({2'b0, in_operand_A[30:23]}) + $signed({2'b0, in_operand_B[30:23]}) - 10'sd127;
                s1_exp_c   <= $signed({2'b0, in_operand_C[30:23]});
                
                s1_mant_a <= (|in_operand_A[30:23]) ? {1'b1, in_operand_A[22:0]} : 24'd0;
                s1_mant_b <= (|in_operand_B[30:23]) ? {1'b1, in_operand_B[22:0]} : 24'd0;
                s1_mant_c <= (|in_operand_C[30:23]) ? {1'b1, in_operand_C[22:0]} : 24'd0;
                
                s1_is_zero_mul <= (~|in_operand_A[30:23]) | (~|in_operand_B[30:23]);
                s1_is_zero_c   <= (~|in_operand_C[30:23]);
            end
        end
    end

    // --- STAGE 2: Mul & Align ---
    reg s2_valid, s2_sign_mul, s2_sign_c;
    reg signed [9:0] s2_exp_max;
    reg [47:0] s2_mant_mul;
    reg [72:0] s2_mant_c_aligned;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 0;
            s2_mant_mul <= 0; s2_mant_c_aligned <= 0; s2_exp_max <= 0;
        end else begin
            s2_valid <= s1_valid;
            s2_sign_mul <= s1_sign_mul;
            s2_sign_c   <= s1_sign_c;
            
            if (s1_is_zero_c) begin
                s2_exp_max <= s1_exp_mul;
                s2_mant_mul <= (s1_is_zero_mul) ? 48'd0 : (s1_mant_a * s1_mant_b);
                s2_mant_c_aligned <= 73'd0;
            end else if (s1_is_zero_mul) begin
                s2_exp_max <= s1_exp_c;
                s2_mant_mul <= 48'd0;
                s2_mant_c_aligned <= {26'd0, s1_mant_c, 23'd0};
            end else if (s1_exp_mul >= s1_exp_c) begin
                s2_exp_max <= s1_exp_mul;
                s2_mant_mul <= (s1_mant_a * s1_mant_b); 
                s2_mant_c_aligned <= {26'd0, s1_mant_c, 23'd0} >> (s1_exp_mul - s1_exp_c);
            end else begin
                s2_exp_max <= s1_exp_c;
                s2_mant_mul <= (s1_exp_c - s1_exp_mul >= 10'sd48) ? 48'd0 : ((s1_mant_a * s1_mant_b) >> (s1_exp_c - s1_exp_mul));
                s2_mant_c_aligned <= {26'd0, s1_mant_c, 23'd0};
            end
        end
    end

    // --- STAGE 3: Wide Add ---
    reg s3_valid, s3_sign_res;
    reg signed [9:0] s3_exp_max;
    reg [72:0] s3_wide_sum;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_valid <= 0;
            s3_wide_sum <= 0; s3_exp_max <= 0;
        end else begin
            s3_valid <= s2_valid;
            s3_exp_max <= s2_exp_max;
            
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

    // --- STAGE 4: LZA Anticipation (TỐI ƯU CRITICAL PATH Ở ĐÂY) ---
    // Không gộp phép dịch (shift) vào đây nữa để giảm logic delay.
    reg s4_valid, s4_sign_res;
    reg signed [9:0] s4_exp_res;
    reg [72:0] s4_wide_sum;
    reg [6:0]  s4_lza_shift;
    
    integer i; reg [6:0] lza_shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s4_valid <= 0; s4_sign_res <= 0;
            s4_wide_sum <= 0; s4_exp_res <= 0; s4_lza_shift <= 0;
        end else begin
            s4_valid <= s3_valid;
            s4_sign_res <= s3_sign_res;
            s4_wide_sum <= s3_wide_sum;
            
            if (s3_wide_sum == 0) begin
                s4_exp_res <= 0;
                s4_lza_shift <= 0;
            end else begin
                lza_shift = 0;
                for (i = 72; i >= 0; i = i - 1) begin
                    if (s3_wide_sum[i] && lza_shift == 0) lza_shift = 72 - i;
                end
                s4_exp_res <= s3_exp_max - $signed({3'b0, lza_shift}) + 10'sd26;
                s4_lza_shift <= lza_shift;
            end
        end
    end

    // --- STAGE 5: Pack & Shift ---
    // Phép dịch 73-bit giờ đây nằm gọn trong Stage này
    wire [72:0] shifted_sum = s4_wide_sum << s4_lza_shift;
    wire [47:0] s4_mant_norm = shifted_sum[72:25]; // tương đương với dịch phải 25
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 0; out_result <= 0;
            status_overflow <= 0; status_underflow <= 0;
            status_invalid <= 0; status_zero <= 0;
        end else begin
            out_valid <= s4_valid;
            if (s4_valid) begin
                if (s4_wide_sum == 0 || s4_exp_res <= 0) begin
                    out_result <= 32'd0;
                end else begin
                    out_result <= {s4_sign_res, s4_exp_res[7:0], s4_mant_norm[46:24]};
                end
            end
        end
    end
endmodule