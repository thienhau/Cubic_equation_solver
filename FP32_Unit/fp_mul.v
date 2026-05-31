`timescale 1ns / 1ps

module fp_mul #(
    parameter STAGES = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    input  wire [31:0] in_operand_B,
    
    output reg         out_valid,
    output reg  [31:0] out_result,
    output reg         status_overflow,
    output reg         status_underflow,
    output reg         status_invalid,
    output reg         status_zero
);
    // T = 0 -> 1: Giải mã và chuẩn bị số mũ
    reg        s1_valid;
    reg        s1_sign;
    reg [8:0]  s1_exp; 
    reg [23:0] s1_mant_A, s1_mant_B;
    reg        s1_is_zero, s1_is_nan_inf;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
            s1_sign <= 1'b0;
            s1_exp <= 9'd0;
            s1_mant_A <= 24'd0; s1_mant_B <= 24'd0;
            s1_is_zero <= 1'b0; s1_is_nan_inf <= 1'b0;
        end else begin
            s1_valid <= in_valid;
            if (in_valid) begin
                s1_sign <= in_operand_A[31] ^ in_operand_B[31];
                s1_exp  <= in_operand_A[30:23] + in_operand_B[30:23] - 8'd127;
                
                s1_mant_A <= (|in_operand_A[30:23]) ? {1'b1, in_operand_A[22:0]} : 24'd0;
                s1_mant_B <= (|in_operand_B[30:23]) ? {1'b1, in_operand_B[22:0]} : 24'd0;
                
                s1_is_zero <= (~|in_operand_A[30:23]) | (~|in_operand_B[30:23]);
                s1_is_nan_inf <= (&in_operand_A[30:23]) | (&in_operand_B[30:23]);
            end
        end
    end

    // T = 1 -> 2: Nhân phần định trị (Mantissa)
    reg        s2_valid;
    reg        s2_sign;
    reg [8:0]  s2_exp;
    reg [47:0] s2_mant_mult;
    reg        s2_is_zero, s2_is_nan_inf;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 1'b0;
            s2_mant_mult <= 48'd0;
            s2_sign <= 1'b0; s2_exp <= 9'd0;
            s2_is_zero <= 1'b0; s2_is_nan_inf <= 1'b0;
        end else begin
            s2_valid <= s1_valid;
            s2_sign  <= s1_sign;
            s2_exp   <= s1_exp;
            s2_is_zero <= s1_is_zero;
            s2_is_nan_inf <= s1_is_nan_inf;
            
            s2_mant_mult <= s1_mant_A * s1_mant_B;
        end
    end

    // T = 2 -> 3: Phân tích chuẩn hóa (Norm Shift Anticipation)
    reg        s3_valid;
    reg        s3_sign;
    reg [8:0]  s3_exp;
    reg [47:0] s3_mant_res;
    reg        s3_norm_shift; 
    reg        s3_is_zero, s3_is_nan_inf;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_valid <= 1'b0;
            s3_mant_res <= 48'd0;
            s3_sign <= 1'b0; s3_exp <= 9'd0;
            s3_norm_shift <= 1'b0;
            s3_is_zero <= 1'b0; s3_is_nan_inf <= 1'b0;
        end else begin
            s3_valid <= s2_valid;
            s3_sign  <= s2_sign;
            s3_exp   <= s2_exp;
            s3_is_zero <= s2_is_zero;
            s3_is_nan_inf <= s2_is_nan_inf;
            
            s3_mant_res <= s2_mant_mult;
            s3_norm_shift <= ~s2_mant_mult[47]; 
        end
    end

    // T = 3 -> 4: Chuẩn hóa, làm tròn và đóng gói
    wire [47:0] norm_mant = s3_norm_shift ? (s3_mant_res << 1) : s3_mant_res;
    wire [8:0]  norm_exp  = s3_norm_shift ? s3_exp : (s3_exp + 1);
    wire guard_bit  = norm_mant[23];
    wire round_bit  = norm_mant[22];
    wire sticky_bit = |norm_mant[21:0];
    wire round_up   = guard_bit & (round_bit | sticky_bit | norm_mant[24]);
    wire [23:0] rounded_mant = norm_mant[47:24] + round_up;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid        <= 1'b0;
            out_result       <= 32'd0;
            status_overflow  <= 1'b0;
            status_underflow <= 1'b0;
            status_invalid   <= 1'b0;
            status_zero      <= 1'b0;
        end else begin
            out_valid <= s3_valid;
            if (s3_valid) begin
                if (s3_is_nan_inf) begin
                    // Sửa chuẩn Invalid cho ngoại lệ Inf * 0
                    if (s3_is_zero) begin
                        out_result       <= {s3_sign, 8'hFF, 23'h3FFFFF}; // NaN (Quiet NaN)
                        status_invalid   <= 1'b1;
                    end else begin
                        out_result       <= {s3_sign, 8'hFF, 23'd0};     // Infinity
                        status_invalid   <= 1'b0; // Hợp lệ theo chuẩn IEEE-754
                    end
                    status_overflow  <= 1'b0;
                    status_underflow <= 1'b0;
                    status_zero      <= 1'b0;
                    
                end else if (s3_is_zero || norm_exp[8]) begin 
                    out_result       <= {s3_sign, 31'd0};
                    status_underflow <= ~s3_is_zero;
                    status_zero      <= s3_is_zero;
                    // BẮT BUỘC: Hạ các cờ còn lại để xóa dấu vết của transaction trước
                    status_overflow  <= 1'b0;
                    status_invalid   <= 1'b0;
                    
                end else if (norm_exp >= 9'd255) begin
                    out_result       <= {s3_sign, 8'hFF, 23'd0};
                    status_overflow  <= 1'b1;
                    status_underflow <= 1'b0;
                    status_invalid   <= 1'b0;
                    status_zero      <= 1'b0;
                    
                end else begin
                    out_result       <= {s3_sign, norm_exp[7:0], rounded_mant[22:0]};
                    status_zero      <= 1'b0;
                    status_overflow  <= 1'b0;
                    status_underflow <= 1'b0;
                    status_invalid   <= 1'b0;
                end
            end
        end
    end
endmodule