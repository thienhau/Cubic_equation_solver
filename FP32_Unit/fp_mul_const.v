`timescale 1ns / 1ps

module fp_mul_const_one_third #(
    parameter STAGES = 2
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output reg         out_valid,
    output reg  [31:0] out_result
);
    wire        in_sign = in_operand_A[31];
    wire [7:0]  in_exp  = in_operand_A[30:23];
    wire [23:0] in_mant = {1'b1, in_operand_A[22:0]};

    // Tạo thanh ghi mở rộng 56 bit để chống rớt bit khi dịch
    // Dấu phẩy động ngầm định nằm giữa bit 55 và 54
    wire [55:0] in_mant_ext = {in_mant, 32'd0}; 

    // ==============================================================================
    // STAGE 1: Dịch bit độ phân giải cao (Mô phỏng nhân với 0.33333333)
    // ==============================================================================
    reg        s1_valid;
    reg        s1_sign;
    reg [7:0]  s1_exp;
    reg [55:0] s1_sum_A, s1_sum_B, s1_sum_C, s1_sum_D;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 0; s1_sign <= 0; s1_exp <= 0;
            s1_sum_A <= 0; s1_sum_B <= 0; s1_sum_C <= 0; s1_sum_D <= 0;
        end else begin
            s1_valid <= in_valid;
            if (in_valid && in_exp != 0) begin
                s1_sign <= in_sign;
                s1_exp  <= in_exp;
                // Chuỗi cộng kéo dài đến 32 bit thập phân (Không bị mất bit)
                s1_sum_A <= (in_mant_ext >> 2)  + (in_mant_ext >> 4)  + (in_mant_ext >> 6)  + (in_mant_ext >> 8);
                s1_sum_B <= (in_mant_ext >> 10) + (in_mant_ext >> 12) + (in_mant_ext >> 14) + (in_mant_ext >> 16);
                s1_sum_C <= (in_mant_ext >> 18) + (in_mant_ext >> 20) + (in_mant_ext >> 22) + (in_mant_ext >> 24);
                s1_sum_D <= (in_mant_ext >> 26) + (in_mant_ext >> 28) + (in_mant_ext >> 30) + (in_mant_ext >> 32);
            end else begin
                s1_sign <= 0; s1_exp <= 0;
                s1_sum_A <= 0; s1_sum_B <= 0; s1_sum_C <= 0; s1_sum_D <= 0;
            end
        end
    end

    // ==============================================================================
    // STAGE 2: Gom tổng, Chuẩn hóa và Làm tròn (GRS)
    // ==============================================================================
    wire [55:0] sum_total = s1_sum_A + s1_sum_B + s1_sum_C + s1_sum_D;

    reg [23:0]       norm_mant;
    reg signed [8:0] norm_exp; // Mở rộng 9 bit có dấu để bắt Underflow
    reg              G, R, S, LSB;

    // Chuẩn hóa tùy thuộc vào bit kết quả cao nhất
    always @(*) begin
        // Vì Mantissa lớn nhất là ~2.0, nhân 1/3 = ~0.666
        // Nên bit 55 (đại diện 2^0) luôn luôn = 0.
        // Ta chỉ kiểm tra từ bit 54 (đại diện 2^-1)
        if (sum_total[54]) begin
            // Kết quả dạng 0.1xxxxx... -> Dịch trái 1 bit
            norm_exp  = {1'b0, s1_exp} - 9'd1;
            norm_mant = sum_total[54:31]; 
            LSB       = sum_total[31];
            G         = sum_total[30];
            R         = sum_total[29];
            S         = |sum_total[28:0]; // Gom toàn bộ rác phía sau thành Sticky
        end else begin
            // Kết quả dạng 0.01xxxxx... -> Dịch trái 2 bit
            norm_exp  = {1'b0, s1_exp} - 9'd2;
            norm_mant = sum_total[53:30];
            LSB       = sum_total[30];
            G         = sum_total[29];
            R         = sum_total[28];
            S         = |sum_total[27:0];
        end
    end

    // Thực hiện làm tròn IEEE-754: Round to Nearest, Ties to Even
    wire round_up = G & (R | S | LSB);
    wire [24:0] rounded_mant = {1'b0, norm_mant} + round_up;

    // Xử lý đóng gói Output
    reg [7:0]  out_exp;
    reg [22:0] out_frac;

    always @(*) begin
        if (s1_exp == 0 || norm_exp <= 0) begin
            // Xử lý Flush-to-Zero khi bị Underflow
            out_exp  = 8'd0;
            out_frac = 23'd0;
        end else begin
            if (rounded_mant[24]) begin 
                // Tràn bit khi cộng +1 làm tròn (vd: 1.11...1 -> 10.00...0)
                out_exp  = norm_exp[7:0] + 8'd1;
                out_frac = rounded_mant[23:1];
            end else begin
                out_exp  = norm_exp[7:0];
                out_frac = rounded_mant[22:0];
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid  <= 1'b0;
            out_result <= 32'd0;
        end else begin
            out_valid <= s1_valid;
            if (s1_valid) begin
                if (s1_exp == 0 || norm_exp <= 0) begin
                    out_result <= 32'd0;
                end else begin
                    out_result <= {s1_sign, out_exp, out_frac};
                end
            end
        end
    end
endmodule