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
    output reg         status_zero,
    output reg         status_invalid
);

    wire        eff_sign_B = in_operand_B[31] ^ in_is_sub;
    wire [23:0] mant_A     = (|in_operand_A[30:23]) ? {1'b1, in_operand_A[22:0]} : 24'd0;
    wire [23:0] mant_B     = (|in_operand_B[30:23]) ? {1'b1, in_operand_B[22:0]} : 24'd0;

    wire a_is_nan = (&in_operand_A[30:23]) && (|in_operand_A[22:0]);
    wire b_is_nan = (&in_operand_B[30:23]) && (|in_operand_B[22:0]);
    wire a_is_inf = (&in_operand_A[30:23]) && (~|in_operand_A[22:0]);
    wire b_is_inf = (&in_operand_B[30:23]) && (~|in_operand_B[22:0]);
    wire inf_sub_invalid = a_is_inf && b_is_inf && (in_operand_A[31] ^ eff_sign_B);

    // T = 0 -> 1: So sánh độ lớn trị tuyệt đối, sắp xếp toán hạng L (Lớn) và S (Nhỏ)
    reg s1_valid;
    reg s1_sign_L, s1_sign_S;
    reg [7:0] s1_exp_L;
    reg [7:0] s1_exp_diff;
    reg [23:0] s1_mant_L, s1_mant_S;
    reg s1_invalid;
    reg s1_is_inf;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid   <= 1'b0;
            s1_sign_L  <= 1'b0; s1_sign_S <= 1'b0;
            s1_exp_L   <= 8'd0; s1_exp_diff <= 8'd0;
            s1_mant_L  <= 24'd0; s1_mant_S <= 24'd0;
            s1_invalid <= 1'b0;
            s1_is_inf  <= 1'b0;
        end else begin
            s1_valid <= in_valid;
            if (in_valid) begin
                s1_invalid <= a_is_nan || b_is_nan || inf_sub_invalid;
                s1_is_inf  <= a_is_inf || b_is_inf;
                
                if (in_operand_A[30:0] >= in_operand_B[30:0]) begin
                    s1_sign_L   <= in_operand_A[31];
                    s1_sign_S   <= eff_sign_B;
                    s1_exp_L    <= in_operand_A[30:23];
                    s1_exp_diff <= in_operand_A[30:23] - in_operand_B[30:23];
                    s1_mant_L   <= mant_A;
                    s1_mant_S   <= mant_B;
                end else begin
                    s1_sign_L   <= eff_sign_B;
                    s1_sign_S   <= in_operand_A[31];
                    s1_exp_L    <= in_operand_B[30:23];
                    s1_exp_diff <= in_operand_B[30:23] - in_operand_A[30:23];
                    s1_mant_L   <= mant_B;
                    s1_mant_S   <= mant_A;
                end
            end
        end
    end

    // Logic tổ hợp giữa T = 1 và T = 2: Dịch phải mantissa toán hạng S để căn bằng số mũ
    wire [5:0]  shift_amt   = (s1_exp_diff > 26) ? 6'd26 : s1_exp_diff[5:0];
    wire [49:0] shifted_ext = {s1_mant_S, 26'b0} >> shift_amt;
    
    wire [23:0] aligned_mant_S_24 = shifted_ext[49:26];
    wire        mant_G            = shifted_ext[25];
    wire        mant_R            = shifted_ext[24];
    wire        mant_S            = |shifted_ext[23:0];

    // T = 1 -> 2: Tính toán tổng/hiệu mantissa trên dải 28-bit mở rộng (Carry, Mantissa, G, R, S)
    reg s2_valid;
    reg s2_sign_res;
    reg [7:0] s2_exp_L;
    reg [27:0] s2_sum; 
    reg s2_invalid;
    reg s2_is_inf;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid    <= 1'b0;
            s2_sign_res <= 1'b0; s2_exp_L <= 8'd0;
            s2_sum      <= 28'd0;
            s2_invalid  <= 1'b0;
            s2_is_inf   <= 1'b0;
        end else begin
            s2_valid    <= s1_valid;
            s2_sign_res <= s1_sign_L;
            s2_exp_L    <= s1_exp_L;
            s2_invalid  <= s1_invalid;
            s2_is_inf   <= s1_is_inf;
            
            if (s1_sign_L ^ s1_sign_S) begin
                s2_sum <= {1'b0, s1_mant_L, 3'b000} - {1'b0, aligned_mant_S_24, mant_G, mant_R, mant_S};
            end else begin
                s2_sum <= {1'b0, s1_mant_L, 3'b000} + {1'b0, aligned_mant_S_24, mant_G, mant_R, mant_S};
            end
        end
    end

    // T = 2 -> 3: Quét tìm vị trí bit 1 cao nhất (LZA loop) phục vụ chuẩn hóa dải động
    reg s3_valid;
    reg s3_sign_res;
    reg [7:0] s3_exp_L;
    reg [27:0] s3_sum;
    reg [4:0] s3_lza_shift;
    reg s3_invalid;
    reg s3_is_inf;
    
    integer i;
    reg [4:0] temp_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_valid     <= 1'b0;
            s3_sign_res  <= 1'b0; s3_exp_L <= 8'd0;
            s3_sum       <= 28'd0; s3_lza_shift <= 5'd0;
            s3_invalid   <= 1'b0;
            s3_is_inf    <= 1'b0;
        end else begin
            s3_valid     <= s2_valid;
            s3_sign_res  <= s2_sign_res;
            s3_exp_L     <= s2_exp_L;
            s3_sum       <= s2_sum;
            s3_invalid   <= s2_invalid;
            s3_is_inf    <= s2_is_inf;
            
            temp_shift = 5'd31; 
            begin : lza_loop
                for (i = 27; i >= 0; i = i - 1) begin
                    if (s2_sum[i]) begin
                        temp_shift = 27 - i;
                        disable lza_loop;
                    end
                end
            end
            s3_lza_shift <= temp_shift;
        end
    end

    // T = 3 -> 4: Thực hiện dịch trái chuẩn hóa, làm tròn RNE và đóng gói kiểm tra lỗi ngõ ra
    wire [27:0] norm_sum = (s3_sum == 0) ? 28'd0 : (s3_sum << s3_lza_shift);
    
    wire norm_G = norm_sum[3];
    wire norm_R = norm_sum[2];
    wire norm_S = norm_sum[1] | norm_sum[0];
    wire round_up = norm_G & (norm_R | norm_S | norm_sum[4]);
    
    wire [24:0] rounded_mant = {1'b0, norm_sum[27:4]} + round_up;
    
    wire signed [10:0] prelim_exp = $signed({3'b0, s3_exp_L}) + 1 - $signed({6'b0, s3_lza_shift});
    wire signed [10:0] final_exp  = prelim_exp + rounded_mant[24]; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid       <= 1'b0;
            out_result      <= 32'd0;
            status_zero     <= 1'b0;
            status_overflow <= 1'b0;
            status_invalid  <= 1'b0;
        end else begin
            out_valid <= s3_valid;
            if (s3_valid) begin
                if (s3_invalid) begin
                    out_result      <= {s3_sign_res, 8'hFF, 23'h3FFFFF}; 
                    status_zero     <= 1'b0;
                    status_overflow <= 1'b0;
                    status_invalid  <= 1'b1;
                end else if (s3_sum == 0) begin
                    out_result      <= 32'd0;
                    status_zero     <= 1'b1;
                    status_overflow <= 1'b0;
                    status_invalid  <= 1'b0;
                end else if (s3_is_inf || final_exp >= 255) begin
                    out_result      <= {s3_sign_res, 8'hFF, 23'd0}; 
                    status_overflow <= 1'b1;
                    status_zero     <= 1'b0;
                    status_invalid  <= 1'b0;
                end else if (final_exp <= 0) begin
                    out_result      <= {s3_sign_res, 31'd0}; 
                    status_zero     <= 1'b1;
                    status_overflow <= 1'b0;
                    status_invalid  <= 1'b0;
                end else begin
                    out_result      <= {s3_sign_res, final_exp[7:0], rounded_mant[22:0]};
                    status_zero     <= 1'b0;
                    status_overflow <= 1'b0;
                    status_invalid  <= 1'b0;
                end
            end
        end
    end
endmodule