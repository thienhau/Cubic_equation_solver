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

    reg s1_valid, s1_sign, s1_is_zero, s1_is_invalid;
    reg [8:0] s1_exp;
    reg [24:0] s1_rem_a, s1_div_b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 0; s1_sign <= 0; s1_exp <= 0;
            s1_rem_a <= 0; s1_div_b <= 0;
            s1_is_zero <= 0; s1_is_invalid <= 0;
        end else begin
            s1_valid <= in_valid;
            if (in_valid) begin
                if (~|in_operand_B[30:23]) begin 
                    s1_is_invalid <= 1'b1; s1_is_zero <= 1'b0;
                end else if (~|in_operand_A[30:23]) begin 
                    s1_is_zero <= 1'b1; s1_is_invalid <= 1'b0;
                end else begin
                    s1_is_zero <= 1'b0; s1_is_invalid <= 1'b0;
                end
                s1_sign  <= in_operand_A[31] ^ in_operand_B[31];
                s1_exp   <= in_operand_A[30:23] - in_operand_B[30:23] + 8'd127;
                s1_rem_a <= {2'b01, in_operand_A[22:0]};
                s1_div_b <= {2'b01, in_operand_B[22:0]};
            end
        end
    end

    reg s2_valid, s2_sign, s2_is_zero, s2_is_invalid;
    reg [8:0] s2_exp;
    reg [24:0] s2_rem, s2_div;
    reg [25:0] s2_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 0; s2_sign <= 0; s2_exp <= 0;
            s2_rem <= 0; s2_div <= 0; s2_q <= 0;
            s2_is_zero <= 0; s2_is_invalid <= 0;
        end else begin
            s2_valid <= s1_valid; s2_sign <= s1_sign;
            s2_exp <= s1_exp; s2_is_zero <= s1_is_zero;
            s2_is_invalid <= s1_is_invalid; s2_div <= s1_div_b;
            
            if (s1_rem_a >= s1_div_b) begin
                s2_rem <= s1_rem_a - s1_div_b;
                s2_q <= 26'd1;
            end else begin
                s2_rem <= s1_rem_a;
                s2_q <= 26'd0;
            end
        end
    end

    reg        s_valid [3:8]; reg        s_sign  [3:8];
    reg [8:0]  s_exp   [3:8]; reg        s_zero  [3:8];
    reg        s_inv   [3:8]; reg [24:0] s_div   [3:8];
    reg [24:0] s_rem   [3:8]; reg [25:0] s_q     [3:8];

    integer i, j;
    reg [25:0] t_rem; // [FIX QUAN TRỌNG NHẤT]: Tăng lên 26 bit để không bị rơi mất bit 1 khi dịch trái
    reg [3:0]  t_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 3; i <= 8; i = i + 1) begin
                s_valid[i] <= 0; s_sign[i] <= 0; s_exp[i] <= 0;
                s_zero[i] <= 0; s_inv[i] <= 0;
                s_rem[i] <= 0; s_div[i] <= 0; s_q[i] <= 0;
            end
        end else begin
            s_valid[3] <= s2_valid; s_sign[3] <= s2_sign;
            s_exp[3]   <= s2_exp;   s_zero[3] <= s2_is_zero;
            s_inv[3]   <= s2_is_invalid; s_div[3] <= s2_div;
            
            t_rem = {1'b0, s2_rem}; t_q = 0;
            for (j = 0; j < 4; j = j + 1) begin
                t_rem = t_rem << 1;
                if (t_rem >= {1'b0, s2_div}) begin
                    t_rem = t_rem - {1'b0, s2_div};
                    t_q[3-j] = 1'b1;
                end
            end
            s_rem[3] <= t_rem[24:0]; s_q[3] <= {s2_q[21:0], t_q};
            
            for (i = 4; i <= 8; i = i + 1) begin
                s_valid[i] <= s_valid[i-1]; s_sign[i] <= s_sign[i-1];
                s_exp[i]   <= s_exp[i-1];   s_zero[i] <= s_zero[i-1];
                s_inv[i]   <= s_inv[i-1];   s_div[i]  <= s_div[i-1];
                
                t_rem = {1'b0, s_rem[i-1]}; t_q = 0;
                for (j = 0; j < 4; j = j + 1) begin
                    t_rem = t_rem << 1;
                    if (t_rem >= {1'b0, s_div[i-1]}) begin
                        t_rem = t_rem - {1'b0, s_div[i-1]};
                        t_q[3-j] = 1'b1;
                    end
                end
                s_rem[i] <= t_rem[24:0]; s_q[i] <= {s_q[i-1][21:0], t_q};
            end
        end
    end

    reg        p_valid [9:13]; reg        p_sign  [9:13];
    reg [8:0]  p_exp   [9:13]; reg        p_zero  [9:13];
    reg        p_inv   [9:13]; reg [25:0] p_q     [9:13];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 9; i <= 13; i = i + 1) begin
                p_valid[i] <= 0; p_sign[i] <= 0; p_exp[i] <= 0;
                p_zero[i] <= 0; p_inv[i] <= 0; p_q[i] <= 0;
            end
        end else begin
            p_valid[9] <= s_valid[8]; p_sign[9] <= s_sign[8];
            p_exp[9]   <= s_exp[8];   p_zero[9] <= s_zero[8];
            p_inv[9]   <= s_inv[8];   p_q[9]    <= s_q[8];
            for (i = 10; i <= 13; i = i + 1) begin
                p_valid[i] <= p_valid[i-1]; p_sign[i] <= p_sign[i-1];
                p_exp[i]   <= p_exp[i-1];   p_zero[i] <= p_zero[i-1];
                p_inv[i]   <= p_inv[i-1];   p_q[i]    <= p_q[i-1];
            end
        end
    end

    // T = 13 -> 14: Stage 14 - Chuẩn hóa và Đóng gói kết quả (NORM_PACK)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 0; out_result <= 0;
            status_zero <= 0; status_invalid <= 0;
        end else begin
            out_valid <= p_valid[13];
            if (p_valid[13]) begin
                if (p_inv[13]) begin
                    out_result <= {p_sign[13], 8'hFF, 23'd0};
                    status_invalid <= 1'b1; status_zero <= 1'b0;
                end else if (p_zero[13]) begin
                    out_result <= 32'd0;
                    status_zero <= 1'b1; status_invalid <= 1'b0;
                end else begin
                    status_zero <= 0; status_invalid <= 0;
                    // ĐÃ FIX LỖI: Xét chuẩn hóa tại bit 24 (bit nguyên của mantissa)
                    if (p_q[13][24]) begin 
                        out_result <= {p_sign[13], p_exp[13][7:0], p_q[13][23:1]};
                    end else begin
                        out_result <= {p_sign[13], p_exp[13][7:0] - 8'd1, p_q[13][22:0]};
                    end
                end
            end else begin
                status_zero <= 0; status_invalid <= 0;
            end
        end
    end

endmodule