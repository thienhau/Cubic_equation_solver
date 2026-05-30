// ============================================================================
// MODULE 2: FP_COS (Cosine)
// Phương pháp: Đa thức Padé [3/3] cho cos(x) với z = x^2
// N(z) = n0 + z*(n1 + z*(n2 + n3*z))
// D(z) = d0 + z*(d1 + z*(d2 + d3*z))
// Gấp góc phần tư: Giả định đầu vào đã được chuẩn hóa về [0, pi/2]
// Số chu kỳ dự tính (Shared Resource): 
// 1 MUL + 6 FMA (Horner) + 1 DIV = 4 + (6*5) + 14 = 48 chu kỳ
// ============================================================================
module fp_cos (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output reg         mul_req, output reg [31:0] mul_op_a, output reg [31:0] mul_op_b, input wire mul_ack, input wire [31:0] mul_result,    
    output reg         fma_req, output reg [31:0] fma_op_a, output reg [31:0] fma_op_b, output reg [31:0] fma_op_c, input wire fma_ack, input wire [31:0] fma_result,
    output reg         div_req, output reg [31:0] div_op_a, output reg [31:0] div_op_b, input wire div_ack, input wire [31:0] div_result,
    
    output reg         out_valid,
    output reg  [31:0] out_result,
    output reg         status_invalid
);

    // Hằng số Padé [3/3] (Dạng Horner)
    localparam N3 = 32'hB5000000; localparam N2 = 32'h39000000; localparam N1 = 32'hBF000000; localparam N0 = 32'h3F800000; // 1.0
    localparam D3 = 32'h33000000; localparam D2 = 32'h38000000; localparam D1 = 32'h3D000000; localparam D0 = 32'h3F800000; // 1.0

    reg [3:0] state;
    reg [31:0] z_reg;
    reg [31:0] tn1, td1, tn2, td2, n_final, d_final;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 4'd0;
            out_valid <= 1'b0;
            mul_req <= 0; fma_req <= 0; div_req <= 0;
        end else begin
            out_valid <= 1'b0;
            case (state)
                4'd0: begin
                    if (in_valid) begin
                        // (Khối Gấp góc phần tư nội suy tại đây nếu cần)
                        state <= 4'd1;
                    end
                end
                
                4'd1: begin // MUL: z = x * x
                    if (mul_ack) begin z_reg <= mul_result; mul_req <= 1'b0; state <= 4'd2; end 
                    else begin mul_req <= 1'b1; mul_op_a <= in_operand_A; mul_op_b <= in_operand_A; end
                end
                
                4'd2: begin // FMA: tn1 = n3 * z + n2
                    if (fma_ack) begin tn1 <= fma_result; fma_req <= 1'b0; state <= 4'd3; end 
                    else begin fma_req <= 1'b1; fma_op_a <= N3; fma_op_b <= z_reg; fma_op_c <= N2; end
                end
                
                4'd3: begin // FMA: td1 = d3 * z + d2
                    if (fma_ack) begin td1 <= fma_result; fma_req <= 1'b0; state <= 4'd4; end 
                    else begin fma_req <= 1'b1; fma_op_a <= D3; fma_op_b <= z_reg; fma_op_c <= D2; end
                end
                
                4'd4: begin // FMA: tn2 = tn1 * z + n1
                    if (fma_ack) begin tn2 <= fma_result; fma_req <= 1'b0; state <= 4'd5; end 
                    else begin fma_req <= 1'b1; fma_op_a <= tn1; fma_op_b <= z_reg; fma_op_c <= N1; end
                end
                
                4'd5: begin // FMA: td2 = td1 * z + d1
                    if (fma_ack) begin td2 <= fma_result; fma_req <= 1'b0; state <= 4'd6; end 
                    else begin fma_req <= 1'b1; fma_op_a <= td1; fma_op_b <= z_reg; fma_op_c <= D1; end
                end
                
                4'd6: begin // FMA: N = tn2 * z + n0
                    if (fma_ack) begin n_final <= fma_result; fma_req <= 1'b0; state <= 4'd7; end 
                    else begin fma_req <= 1'b1; fma_op_a <= tn2; fma_op_b <= z_reg; fma_op_c <= N0; end
                end
                
                4'd7: begin // FMA: D = td2 * z + d0
                    if (fma_ack) begin d_final <= fma_result; fma_req <= 1'b0; state <= 4'd8; end 
                    else begin fma_req <= 1'b1; fma_op_a <= td2; fma_op_b <= z_reg; fma_op_c <= D0; end
                end
                
                4'd8: begin // DIV: Result = N / D
                    if (div_ack) begin
                        out_valid <= 1'b1;
                        out_result <= div_result;
                        status_invalid <= 1'b0;
                        div_req <= 1'b0;
                        state <= 4'd0;
                    end else begin
                        div_req <= 1'b1; div_op_a <= n_final; div_op_b <= d_final;
                    end
                end
                default: state <= 4'd0;
            endcase
        end
    end
endmodule