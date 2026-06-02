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

    // Phát hiện NaN hoặc ngoại lệ vô cực bất định ngay tại T=0
    wire a_is_nan = (&in_operand_A[30:23]) && (|in_operand_A[22:0]);
    wire b_is_nan = (&in_operand_B[30:23]) && (|in_operand_B[22:0]);
    wire a_is_inf = (&in_operand_A[30:23]) && (~|in_operand_A[22:0]);
    wire b_is_inf = (&in_operand_B[30:23]) && (~|in_operand_B[22:0]);
    // Vô cực đối dấu thực hiện phép cộng (hoặc cùng dấu thực hiện phép trừ) -> Bất định
    wire inf_sub_invalid = a_is_inf && b_is_inf && (in_operand_A[31] ^ eff_sign_B);

    // T = 0 -> 1
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

    // Tổ hợp G, R, S Shift Logic (T=1 -> 2)
    wire [5:0]  shift_amt   = (s1_exp_diff > 26) ? 6'd26 : s1_exp_diff[5:0];
    wire [49:0] shifted_ext = {s1_mant_S, 26'b0} >> shift_amt;
    
    wire [23:0] aligned_mant_S_24 = shifted_ext[49:26];
    wire        mant_G            = shifted_ext[25];
    wire        mant_R            = shifted_ext[24];
    wire        mant_S            = |shifted_ext[23:0];

    // T = 1 -> 2
    reg s2_valid;
    reg s2_sign_res;
    reg [7:0] s2_exp_L;
    reg [27:0] s2_sum; // Mở rộng thành 28 bit: [27] Carry, [26:3] Mantissa 24-bit, [2] G, [1] R, [0] S
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
            
            // Thực hiện tính toán trên 28 bits để bảo toàn độ chính xác
            if (s1_sign_L ^ s1_sign_S) begin
                s2_sum <= {1'b0, s1_mant_L, 3'b000} - {1'b0, aligned_mant_S_24, mant_G, mant_R, mant_S};
            end else begin
                s2_sum <= {1'b0, s1_mant_L, 3'b000} + {1'b0, aligned_mant_S_24, mant_G, mant_R, mant_S};
            end
        end
    end

    // T = 2 -> 3
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
            
            temp_shift = 5'd31; // Mặc định nếu bằng 0
            begin : lza_loop
                // Quét 28 bit để tìm MSB
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

    // Tổ hợp Normalization & Rounding (T=3 -> 4)
    wire [27:0] norm_sum = (s3_sum == 0) ? 28'd0 : (s3_sum << s3_lza_shift);
    
    // GRS tại vị trí tương ứng sau chuẩn hóa
    wire norm_G = norm_sum[3];
    wire norm_R = norm_sum[2];
    wire norm_S = norm_sum[1] | norm_sum[0];
    
    // Round to Nearest, Ties to Even
    wire round_up = norm_G & (norm_R | norm_S | norm_sum[4]);
    
    // Mảng 25-bit cho phép bắt tràn bit (overflow) trong lúc làm tròn
    wire [24:0] rounded_mant = {1'b0, norm_sum[27:4]} + round_up;
    
    // Tính số mũ: Bù đắp +1 do implicit format, -shift do LZD
    wire signed [10:0] prelim_exp = $signed({3'b0, s3_exp_L}) + 1 - $signed({6'b0, s3_lza_shift});
    // Nếu bị tràn khi làm tròn (rounded_mant[24] == 1), số mũ tăng 1
    wire signed [10:0] final_exp  = prelim_exp + rounded_mant[24]; 

    // T = 3 -> 4
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
                    out_result      <= {s3_sign_res, 8'hFF, 23'h3FFFFF}; // Quiet NaN
                    status_zero     <= 1'b0;
                    status_overflow <= 1'b0;
                    status_invalid  <= 1'b1;
                end else if (s3_sum == 0) begin
                    out_result      <= 32'd0;
                    status_zero     <= 1'b1;
                    status_overflow <= 1'b0;
                    status_invalid  <= 1'b0;
                end else if (s3_is_inf || final_exp >= 255) begin
                    out_result      <= {s3_sign_res, 8'hFF, 23'd0}; // Vô cực / Tràn
                    status_overflow <= 1'b1;
                    status_zero     <= 1'b0;
                    status_invalid  <= 1'b0;
                end else if (final_exp <= 0) begin
                    out_result      <= {s3_sign_res, 31'd0}; // Underflow -> Flush to 0
                    status_zero     <= 1'b1;
                    status_overflow <= 1'b0;
                    status_invalid  <= 1'b0;
                end else begin
                    // Kết quả hợp lệ cuối cùng (do cấu trúc chuẩn hóa, nếu rounded_mant tràn thì phần [22:0] tự động bằng 0, rất gọn)
                    out_result      <= {s3_sign_res, final_exp[7:0], rounded_mant[22:0]};
                    status_zero     <= 1'b0;
                    status_overflow <= 1'b0;
                    status_invalid  <= 1'b0;
                end
            end
        end
    end
endmodule