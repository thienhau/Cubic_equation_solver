module trigon_path (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] p, 
    input  wire [31:0] q, 
    input  wire [31:0] offset,
    
    // --- CÁC CỔNG GIAO TIẾP ĐỂ MƯỢN TÀI NGUYÊN TỪ TOP-LEVEL ---
    output reg         mul_req, output reg [31:0] mul_op_a, output reg [31:0] mul_op_b, input wire mul_ack, input wire [31:0] mul_result,
    output reg         fma_req, output reg [31:0] fma_op_a, output reg [31:0] fma_op_b, output reg [31:0] fma_op_c, input wire fma_ack, input wire [31:0] fma_result,
    output reg         div_req, output reg [31:0] div_op_a, output reg [31:0] div_op_b, input wire div_ack, input wire [31:0] div_result,
    output reg         add_req, output reg [31:0] add_op_a, output reg [31:0] add_op_b, input wire add_ack, input wire [31:0] add_result,
    output reg         sqrt_req, output reg [31:0] sqrt_op, input wire sqrt_ack, input wire [31:0] sqrt_result,
    output reg         acos_req, output reg [31:0] acos_op, input wire acos_ack, input wire [31:0] acos_result,
    output reg         cos_req,  output reg [31:0] cos_op,  input wire cos_ack,  input wire [31:0] cos_result,

    // --- GIAO DIỆN XUẤT NGHIỆM ---
    output reg         out_valid,
    output reg  [31:0] x1, 
    output reg  [31:0] x2, 
    output reg  [31:0] x3
);

    // Hằng số IEEE-754 Float32
    localparam CONST_NEG_1_3 = 32'hBEAAAAAB; // -1/3
    localparam CONST_1_3     = 32'h3EAAAAAB; // 1/3
    localparam CONST_1_5     = 32'h3FC00000; // 1.5
    localparam CONST_NEG_2PI_3 = 32'hC0060A92; // -2PI/3
    localparam CONST_NEG_4PI_3 = 32'hC0860A92; // -4PI/3

    reg [4:0]  state;
    
    // Các thanh ghi chốt dữ liệu trung gian
    reg [31:0] p_reg, q_reg, off_reg;
    reg [31:0] p_third, val_2, r_reg;
    reg [31:0] denom, num, arg_val;
    reg [31:0] theta, t1, t2, t3;
    reg [31:0] c1, c2, c3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 5'd0;
            out_valid <= 1'b0;
            mul_req <= 0; fma_req <= 0; div_req <= 0; add_req <= 0;
            sqrt_req <= 0; acos_req <= 0; cos_req <= 0;
        end else begin
            out_valid <= 1'b0;
            
            case (state)
                5'd0: begin // S_IDLE
                    if (in_valid) begin
                        p_reg   <= p;
                        q_reg   <= q;
                        off_reg <= offset;
                        state   <= 5'd1;
                    end
                end
                
                // 1. Tính: p_third = p * (-1/3)
                5'd1: begin
                    mul_req  <= 1'b1;
                    mul_op_a <= p_reg;
                    mul_op_b <= CONST_NEG_1_3;
                    if (mul_ack) begin
                        mul_req <= 1'b0;
                        p_third <= mul_result;
                        state   <= 5'd2;
                    end
                end
                
                // 2. Tính: val_2 = sqrt(-p/3)
                5'd2: begin
                    sqrt_req <= 1'b1;
                    sqrt_op  <= p_third;
                    if (sqrt_ack) begin
                        sqrt_req <= 1'b0;
                        val_2    <= sqrt_result;
                        
                        // Tính luôn r = 2 * val_2 bằng cách cộng Exponent thêm 1 (Nhân 2)
                        // Bỏ qua Exception tràn số vì r nằm trong miền an toàn
                        r_reg    <= {sqrt_result[31], sqrt_result[30:23] + 8'd1, sqrt_result[22:0]};
                        state    <= 5'd3;
                    end
                end
                
                // 3. Tính: denom = p * val_2
                5'd3: begin
                    mul_req  <= 1'b1;
                    mul_op_a <= p_reg;
                    mul_op_b <= val_2;
                    if (mul_ack) begin
                        mul_req <= 1'b0;
                        denom   <= mul_result;
                        state   <= 5'd4;
                    end
                end
                
                // 4. Tính: num = q * 1.5
                5'd4: begin
                    mul_req  <= 1'b1;
                    mul_op_a <= q_reg;
                    mul_op_b <= CONST_1_5;
                    if (mul_ack) begin
                        mul_req <= 1'b0;
                        num     <= mul_result;
                        state   <= 5'd5;
                    end
                end
                
                // 5. Tính: arg = num / denom
                5'd5: begin
                    div_req  <= 1'b1;
                    div_op_a <= num;
                    div_op_b <= denom;
                    if (div_ack) begin
                        div_req <= 1'b0;
                        arg_val <= div_result;
                        state   <= 5'd6;
                    end
                end
                
                // 6. Tính: theta = acos(arg)
                5'd6: begin
                    acos_req <= 1'b1;
                    acos_op  <= arg_val;
                    if (acos_ack) begin
                        acos_req <= 1'b0;
                        theta    <= acos_result;
                        state    <= 5'd7;
                    end
                end
                
                // 7. Tính: t1 = theta * (1/3)
                5'd7: begin
                    mul_req  <= 1'b1;
                    mul_op_a <= theta;
                    mul_op_b <= CONST_1_3;
                    if (mul_ack) begin
                        mul_req <= 1'b0;
                        t1      <= mul_result;
                        state   <= 5'd8;
                    end
                end
                
                // 8. Tính: t2 = t1 + (-2PI/3)
                5'd8: begin
                    add_req  <= 1'b1;
                    add_op_a <= t1;
                    add_op_b <= CONST_NEG_2PI_3;
                    if (add_ack) begin
                        add_req <= 1'b0;
                        t2      <= add_result;
                        state   <= 5'd9;
                    end
                end
                
                // 9. Tính: t3 = t1 + (-4PI/3)
                5'd9: begin
                    add_req  <= 1'b1;
                    add_op_a <= t1;
                    add_op_b <= CONST_NEG_4PI_3;
                    if (add_ack) begin
                        add_req <= 1'b0;
                        t3      <= add_result;
                        state   <= 5'd10;
                    end
                end
                
                // 10. Tính: c1 = cos(t1)
                5'd10: begin
                    cos_req <= 1'b1;
                    cos_op  <= t1;
                    if (cos_ack) begin
                        cos_req <= 1'b0;
                        c1      <= cos_result;
                        state   <= 5'd11;
                    end
                end
                
                // 11. Tính: c2 = cos(t2)
                5'd11: begin
                    cos_req <= 1'b1;
                    cos_op  <= t2;
                    if (cos_ack) begin
                        cos_req <= 1'b0;
                        c2      <= cos_result;
                        state   <= 5'd12;
                    end
                end
                
                // 12. Tính: c3 = cos(t3)
                5'd12: begin
                    cos_req <= 1'b1;
                    cos_op  <= t3;
                    if (cos_ack) begin
                        cos_req <= 1'b0;
                        c3      <= cos_result;
                        state   <= 5'd13;
                    end
                end
                
                // 13. Tính: x1 = r * c1 + (-offset)
                5'd13: begin
                    fma_req  <= 1'b1;
                    fma_op_a <= r_reg;
                    fma_op_b <= c1;
                    fma_op_c <= {~off_reg[31], off_reg[30:0]}; // Bù dấu: -offset
                    if (fma_ack) begin
                        fma_req <= 1'b0;
                        x1      <= fma_result;
                        state   <= 5'd14;
                    end
                end
                
                // 14. Tính: x2 = r * c2 + (-offset)
                5'd14: begin
                    fma_req  <= 1'b1;
                    fma_op_a <= r_reg;
                    fma_op_b <= c2;
                    fma_op_c <= {~off_reg[31], off_reg[30:0]};
                    if (fma_ack) begin
                        fma_req <= 1'b0;
                        x2      <= fma_result;
                        state   <= 5'd15;
                    end
                end
                
                // 15. Tính: x3 = r * c3 + (-offset)
                5'd15: begin
                    fma_req  <= 1'b1;
                    fma_op_a <= r_reg;
                    fma_op_b <= c3;
                    fma_op_c <= {~off_reg[31], off_reg[30:0]};
                    if (fma_ack) begin
                        fma_req   <= 1'b0;
                        x3        <= fma_result;
                        out_valid <= 1'b1; // Kích hoạt cờ xong!
                        state     <= 5'd0; // Quay về IDLE
                    end
                end
                
                default: state <= 5'd0;
            endcase
        end
    end
endmodule