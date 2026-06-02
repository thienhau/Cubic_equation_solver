`timescale 1ns / 1ps

module fp_div #(
    parameter STAGES = 14
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    input  wire [31:0] in_operand_B,
    
    output reg         out_valid,
    output reg  [31:0] out_result,
    
    output reg         status_zero,
    output reg         status_invalid
);
    // ==============================================================================
    // GIẢI MÃ CÁC TRƯỜNG HỢP ĐẶC BIỆT
    // ==============================================================================
    wire is_zero_A = ~|in_operand_A[30:23];
    wire is_zero_B = ~|in_operand_B[30:23];
    wire is_inf_A  = (&in_operand_A[30:23]) && (~|in_operand_A[22:0]);
    wire is_inf_B  = (&in_operand_B[30:23]) && (~|in_operand_B[22:0]);
    wire is_nan_A  = (&in_operand_A[30:23]) && (|in_operand_A[22:0]);
    wire is_nan_B  = (&in_operand_B[30:23]) && (|in_operand_B[22:0]);

    // Thêm bit ẩn (hidden bit) vào mantissa
    wire [24:0] mant_a = {1'b0, 1'b1, in_operand_A[22:0]}; // Định dạng 25-bit để chống tràn khi dịch
    wire [24:0] mant_b = {1'b0, 1'b1, in_operand_B[22:0]};

    // ==============================================================================
    // STAGE 1: Exponent, Dấu, Cờ Đặc Biệt & 3 BIT ĐẦU CỦA PHÉP CHIA
    // ==============================================================================
    reg        s1_valid, s1_sign, s1_is_zero, s1_is_invalid, s1_is_nan, s1_is_inf;
    reg [8:0]  s1_exp;       // 9-bit có dấu để bắt Under/Overflow
    reg [24:0] s1_rem, s1_div;
    reg [26:0] s1_q;         // Mở rộng Q lên 27 bit
    reg [31:0] s1_nan_dly;

    reg [24:0] rem_s1_0, rem_s1_1, rem_s1_2;
    reg [2:0]  q_s1;

    // Logic tổ hợp cho 3 bước trừ của Stage 1
    always @(*) begin
        // Vòng lặp 0
        if (mant_a >= mant_b) begin
            rem_s1_0 = mant_a - mant_b;
            q_s1[2]  = 1'b1;
        end else begin
            rem_s1_0 = mant_a;
            q_s1[2]  = 1'b0;
        end
        // Vòng lặp 1
        if ({rem_s1_0[23:0], 1'b0} >= mant_b) begin
            rem_s1_1 = {rem_s1_0[23:0], 1'b0} - mant_b;
            q_s1[1]  = 1'b1;
        end else begin
            rem_s1_1 = {rem_s1_0[23:0], 1'b0};
            q_s1[1]  = 1'b0;
        end
        // Vòng lặp 2
        if ({rem_s1_1[23:0], 1'b0} >= mant_b) begin
            rem_s1_2 = {rem_s1_1[23:0], 1'b0} - mant_b;
            q_s1[0]  = 1'b1;
        end else begin
            rem_s1_2 = {rem_s1_1[23:0], 1'b0};
            q_s1[0]  = 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 0; s1_sign <= 0; s1_exp <= 0;
            s1_rem <= 0; s1_div <= 0; s1_q <= 0;
            s1_is_zero <= 0; s1_is_invalid <= 0;
            s1_is_nan <= 0; s1_nan_dly <= 0; s1_is_inf <= 0;
        end else begin
            s1_valid <= in_valid;
            if (in_valid) begin
                // Cờ đặc biệt chi tiết hơn chuẩn IEEE 754
                s1_is_nan     <= is_nan_A || is_nan_B || (is_zero_A && is_zero_B) || (is_inf_A && is_inf_B);
                s1_is_invalid <= is_nan_A || is_nan_B || (is_zero_A && is_zero_B) || (is_inf_A && is_inf_B);
                s1_is_inf     <= (is_inf_A && !is_inf_B) || (!is_zero_A && is_zero_B); // Chia cho 0 -> Inf
                s1_is_zero    <= (is_zero_A && !is_zero_B) || (!is_inf_A && is_inf_B);
                s1_nan_dly    <= is_nan_A ? in_operand_A : in_operand_B;

                s1_sign <= in_operand_A[31] ^ in_operand_B[31];
                s1_exp  <= {1'b0, in_operand_A[30:23]} - {1'b0, in_operand_B[30:23]} + 9'd127;
                
                s1_rem  <= rem_s1_2;
                s1_div  <= mant_b;
                s1_q    <= {24'd0, q_s1}; // Nạp 3 bit đầu tiên
            end
        end
    end

    // ==============================================================================
    // STAGE 2 đến 13: 12 tầng pipeline, mỗi tầng 2 bit (Tổng 24 bit)
    // ==============================================================================
    reg        s_valid [2:13]; reg        s_sign [2:13]; reg [8:0]  s_exp  [2:13];
    reg        s_zero  [2:13]; reg        s_inv  [2:13]; reg        s_inf  [2:13];
    reg        s_nan   [2:13]; reg [31:0] s_nan_data [2:13];
    reg [24:0] s_div   [2:13]; reg [24:0] s_rem  [2:13]; reg [26:0] s_q    [2:13];

    integer i, j;
    reg [24:0] t_rem;
    reg [1:0]  t_q; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 2; i <= 13; i = i + 1) begin
                s_valid[i] <= 0; s_sign[i] <= 0; s_exp[i] <= 0;
                s_zero[i] <= 0; s_inv[i] <= 0; s_inf[i] <= 0;
                s_rem[i] <= 0; s_div[i] <= 0; s_q[i] <= 0;
                s_nan[i] <= 0; s_nan_data[i] <= 0;
            end
        end else begin
            // Stage 2
            s_valid[2] <= s1_valid; s_sign[2] <= s1_sign; s_exp[2] <= s1_exp;
            s_zero[2] <= s1_is_zero; s_inv[2] <= s1_is_invalid; s_inf[2] <= s1_is_inf;
            s_nan[2] <= s1_is_nan; s_nan_data[2] <= s1_nan_dly; s_div[2] <= s1_div;
            
            t_rem = s1_rem; t_q = 0;
            for (j = 0; j < 2; j = j + 1) begin 
                t_rem = {t_rem[23:0], 1'b0};
                if (t_rem >= s1_div) begin
                    t_rem = t_rem - s1_div;
                    t_q[1-j] = 1'b1;
                end
            end
            s_rem[2] <= t_rem;
            s_q[2]   <= {s1_q[24:0], t_q}; // Dịch trái dồn dần Quotient
            
            // Stage 3 đến 13
            for (i = 3; i <= 13; i = i + 1) begin
                s_valid[i]    <= s_valid[i-1]; s_sign[i]     <= s_sign[i-1];
                s_exp[i]      <= s_exp[i-1];   s_zero[i]     <= s_zero[i-1];
                s_inv[i]      <= s_inv[i-1];   s_inf[i]      <= s_inf[i-1];
                s_nan[i]      <= s_nan[i-1];   s_nan_data[i] <= s_nan_data[i-1];
                s_div[i]      <= s_div[i-1];
                
                t_rem = s_rem[i-1]; t_q = 0;
                for (j = 0; j < 2; j = j + 1) begin 
                    t_rem = {t_rem[23:0], 1'b0};
                    if (t_rem >= s_div[i-1]) begin
                        t_rem = t_rem - s_div[i-1];
                        t_q[1-j] = 1'b1;
                    end
                end
                s_rem[i] <= t_rem;
                s_q[i]   <= {s_q[i-1][24:0], t_q};
            end
        end
    end

    // ==============================================================================
    // STAGE 14: Lấy GRS, Normalization và Round-to-Nearest-Even
    // ==============================================================================
    wire        s14_valid = s_valid[13];
    wire        s14_sign  = s_sign[13];
    wire [8:0]  s14_exp   = s_exp[13];
    wire [26:0] s14_q     = s_q[13];
    
    wire        sticky_bit = (s_rem[13] != 25'd0); // Nếu còn phần dư -> S = 1

    reg [23:0]  frac_with_hidden;
    reg         G, R, S_bit, LSB;
    reg [8:0]   norm_exp;

    always @(*) begin
        // Chuẩn hóa tùy thuộc vào bit cao nhất [26] (đại diện cho 2^0)
        if (s14_q[26]) begin 
            // Dạng 1.xxxx
            frac_with_hidden = {1'b1, s14_q[25:3]};
            LSB   = s14_q[3];
            G     = s14_q[2];
            R     = s14_q[1];
            S_bit = s14_q[0] | sticky_bit;
            norm_exp = s14_exp;
        end else begin
            // Dạng 0.1xxxx (Cần dịch trái 1 bit)
            frac_with_hidden = {1'b1, s14_q[24:2]};
            LSB   = s14_q[2];
            G     = s14_q[1];
            R     = s14_q[0];
            S_bit = sticky_bit;
            norm_exp = s14_exp - 1'b1;
        end
    end

    // Thuật toán làm tròn Round to Nearest, Ties to Even
    wire round_up = G & (R | S_bit | LSB);
    wire [24:0] rounded_frac_full = {1'b0, frac_with_hidden} + round_up;
    
    reg [22:0] final_frac;
    reg [8:0]  final_exp;
    
    always @(*) begin
        if (rounded_frac_full[24]) begin // Xảy ra tràn khi cộng 1 làm tròn (vd: 1.111 -> 10.000)
            final_frac = rounded_frac_full[23:1];
            final_exp  = norm_exp + 1'b1;
        end else begin
            final_frac = rounded_frac_full[22:0];
            final_exp  = norm_exp;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 0; out_result <= 0;
            status_zero <= 0; status_invalid <= 0;
        end else begin
            out_valid <= s14_valid;
            if (s14_valid) begin
                if (s_nan[13]) begin
                    out_result     <= s_nan_data[13];
                    status_invalid <= 1'b0; status_zero <= 1'b0;
                end else if (s_inv[13]) begin
                    out_result     <= {s14_sign, 8'hFF, 23'h3FFFFF}; // Quiet NaN
                    status_invalid <= 1'b1; status_zero <= 1'b0;
                end else if (s_inf[13]) begin
                    out_result     <= {s14_sign, 8'hFF, 23'd0}; // Infinity
                    status_invalid <= 1'b0; status_zero <= 1'b0;
                end else if (s_zero[13]) begin
                    out_result     <= {s14_sign, 31'd0};
                    status_zero    <= 1'b1; status_invalid <= 1'b0;
                end else begin
                    // Bắt lỗi Underflow / Overflow
                    if ($signed(final_exp) <= 0) begin
                        out_result  <= {s14_sign, 31'd0}; // Underflow -> Flush to Zero
                        status_zero <= 1'b1; status_invalid <= 1'b0;
                    end else if (final_exp >= 255) begin
                        out_result  <= {s14_sign, 8'hFF, 23'd0}; // Overflow -> Infinity
                        status_zero <= 1'b0; status_invalid <= 1'b0;
                    end else begin
                        out_result  <= {s14_sign, final_exp[7:0], final_frac};
                        status_zero <= 1'b0; status_invalid <= 1'b0;
                    end
                end
            end else begin
                status_zero <= 0; status_invalid <= 0;
            end
        end
    end
endmodule