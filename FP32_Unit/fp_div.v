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
    // --- Các cờ và tín hiệu phụ trợ ---
    wire is_zero_A = ~|in_operand_A[30:23];
    wire is_zero_B = ~|in_operand_B[30:23];
    wire is_inf_A  = (&in_operand_A[30:23]) && (~|in_operand_A[22:0]);
    wire is_inf_B  = (&in_operand_B[30:23]) && (~|in_operand_B[22:0]);
    wire is_nan_A  = (&in_operand_A[30:23]) && (|in_operand_A[22:0]);
    wire is_nan_B  = (&in_operand_B[30:23]) && (|in_operand_B[22:0]);

    wire [24:0] mant_a = {2'b01, in_operand_A[22:0]};
    wire [24:0] mant_b = {2'b01, in_operand_B[22:0]};
    wire a_ge_b = (mant_a >= mant_b); // Kiểm tra bit chia đầu tiên

    // ==============================================================================
    // STAGE 1: Xử lý Exponent, Sign, Đặc biệt và TÍNH 1 BIT ĐẦU TIÊN CỦA PHÉP CHIA
    // ==============================================================================
    reg s1_valid, s1_sign, s1_is_zero, s1_is_invalid;
    reg [8:0]  s1_exp;
    reg [24:0] s1_rem, s1_div;
    reg [25:0] s1_q;
    reg s1_is_nan;
    reg [31:0] s1_nan_dly;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 0; s1_sign <= 0; s1_exp <= 0;
            s1_rem <= 0; s1_div <= 0; s1_q <= 0;
            s1_is_zero <= 0; s1_is_invalid <= 0;
            s1_is_nan <= 0; s1_nan_dly <= 0;
        end else begin
            s1_valid <= in_valid;
            if (in_valid) begin
                s1_is_invalid <= (is_zero_A && is_zero_B) || (is_inf_A && is_inf_B);
                s1_is_nan     <= is_nan_A || is_nan_B;
                s1_nan_dly    <= is_nan_A ? in_operand_A : in_operand_B;
                s1_is_zero    <= is_zero_A && !is_zero_B;

                s1_sign <= in_operand_A[31] ^ in_operand_B[31];
                s1_exp  <= in_operand_A[30:23] - in_operand_B[30:23] + 8'd127;
                
                // Thực hiện 1 bước trừ đầu tiên để san sẻ gánh nặng
                s1_rem  <= a_ge_b ? (mant_a - mant_b) : mant_a;
                s1_div  <= mant_b;
                s1_q    <= {25'd0, a_ge_b};
            end
        end
    end

    // ==============================================================================
    // STAGE 2 đến 13: 12 tầng tính toán (Mỗi tầng giải quyết 2 bit - Rất nhẹ)
    // ==============================================================================
    reg        s_valid [2:13];
    reg        s_sign  [2:13];
    reg [8:0]  s_exp   [2:13];
    reg        s_zero  [2:13];
    reg        s_inv   [2:13]; 
    reg [24:0] s_div   [2:13];
    reg [24:0] s_rem   [2:13]; 
    reg [25:0] s_q     [2:13];
    reg        s_nan   [2:13];
    reg [31:0] s_nan_data [2:13];

    integer i, j;
    reg [25:0] t_rem;
    reg [1:0]  t_q; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 2; i <= 13; i = i + 1) begin
                s_valid[i] <= 0; s_sign[i] <= 0; s_exp[i] <= 0;
                s_zero[i] <= 0; s_inv[i] <= 0; s_rem[i] <= 0; s_div[i] <= 0; s_q[i] <= 0;
                s_nan[i] <= 0; s_nan_data[i] <= 0;
            end
        end else begin
            // --- Stage 2 lấy dữ liệu từ Stage 1 ---
            s_valid[2] <= s1_valid; s_sign[2] <= s1_sign;
            s_exp[2]   <= s1_exp;   s_zero[2] <= s1_is_zero;
            s_inv[2]   <= s1_is_invalid; s_div[2] <= s1_div;
            s_nan[2]   <= s1_is_nan; s_nan_data[2] <= s1_nan_dly;
            
            t_rem = {1'b0, s1_rem}; t_q = 0;
            for (j = 0; j < 2; j = j + 1) begin 
                t_rem = t_rem << 1;
                if (t_rem >= {1'b0, s1_div}) begin
                    t_rem = t_rem - {1'b0, s1_div};
                    t_q[1-j] = 1'b1;
                end
            end
            s_rem[2] <= t_rem[24:0];
            s_q[2]   <= {s1_q[23:0], t_q};
            
            // --- Stage 3 đến 13 ---
            for (i = 3; i <= 13; i = i + 1) begin
                s_valid[i]    <= s_valid[i-1]; s_sign[i]     <= s_sign[i-1];
                s_exp[i]      <= s_exp[i-1];   s_zero[i]     <= s_zero[i-1];
                s_inv[i]      <= s_inv[i-1];   s_div[i]      <= s_div[i-1];
                s_nan[i]      <= s_nan[i-1];   s_nan_data[i] <= s_nan_data[i-1];
                
                t_rem = {1'b0, s_rem[i-1]}; t_q = 0;
                for (j = 0; j < 2; j = j + 1) begin 
                    t_rem = t_rem << 1;
                    if (t_rem >= {1'b0, s_div[i-1]}) begin
                        t_rem = t_rem - {1'b0, s_div[i-1]};
                        t_q[1-j] = 1'b1;
                    end
                end
                s_rem[i] <= t_rem[24:0];
                s_q[i]   <= {s_q[i-1][23:0], t_q};
            end
        end
    end

    // ==============================================================================
    // STAGE 14: Chuẩn hóa và Đóng gói kết quả (Giữ nguyên)
    // ==============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 0; out_result <= 0;
            status_zero <= 0; status_invalid <= 0;
        end else begin
            out_valid <= s_valid[13];
            if (s_valid[13]) begin
                if (s_nan[13]) begin
                    out_result     <= s_nan_data[13];
                    status_invalid <= 1'b0; status_zero <= 1'b0;
                end else if (s_inv[13]) begin
                    out_result     <= {s_sign[13], 8'hFF, 23'h3FFFFF}; // Quiet NaN
                    status_invalid <= 1'b1; status_zero <= 1'b0;
                end else if (s_zero[13]) begin
                    out_result     <= 32'd0;
                    status_zero <= 1'b1; status_invalid <= 1'b0;
                end else begin
                    status_zero <= 0; status_invalid <= 0;
                    // Sau 12 lần dịch 2 bit + 1 bit ở S1 = tổng 25 bit, bit cao nhất ở vị trí 24.
                    if (s_q[13][24]) begin 
                        out_result <= {s_sign[13], s_exp[13][7:0], s_q[13][23:1]};
                    end else begin
                        out_result <= {s_sign[13], s_exp[13][7:0] - 8'd1, s_q[13][22:0]};
                    end
                end
            end else begin
                status_zero <= 0; status_invalid <= 0;
            end
        end
    end
endmodule