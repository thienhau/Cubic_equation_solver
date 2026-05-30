`timescale 1ns / 1ps

module pade_cbrt_rom (
    input  wire        clk,
    input  wire [7:0]  addr,
    output reg  [31:0] data_out
);
    (* rom_style = "block" *) reg [31:0] rom_array [0:255];

    initial begin
        $readmemh("pade_cbrt_fp32.mem", rom_array);
    end

    always @(posedge clk) begin
        data_out <= rom_array[addr];
    end
endmodule

module fp_cbrt #(
    parameter STAGES = 20
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    // --- GIAO TIEP VOI BO NHAN (FP_MUL) ---
    output reg         mul_req,       
    output reg  [31:0] mul_op_a,      
    output reg  [31:0] mul_op_b,      
    input  wire        mul_ack,       
    input  wire [31:0] mul_result,    
    
    // --- GIAO TIEP VOI BO FMA (FP_FMA) ---
    output reg         fma_req,       
    output reg  [31:0] fma_op_a,
    output reg  [31:0] fma_op_b,
    output reg  [31:0] fma_op_c,
    input  wire        fma_ack,       
    input  wire [31:0] fma_result,
    
    // --- GIAO DIEN DAU RA ---
    output reg         out_valid,
    output reg  [31:0] out_result,
    output reg         status_invalid,
    output reg         status_zero,
    output reg         status_overflow,
    output reg         status_underflow
);

    reg [4:0]  state;
    reg        sign_res;
    reg [7:0]  k_exp;
    reg [1:0]  e_mod;
    reg [31:0] w_fp, w_third_fp, y0_fp, t1_fp, y1_fp;
    
    wire [7:0]  lut_addr = w_fp[22:15];
    wire [31:0] lut_data_fp; 
    
    pade_cbrt_rom u_cbrt_rom (
        .clk(clk), 
        .addr(lut_addr), 
        .data_out(lut_data_fp)
    );

    wire [25:0] mant_w = {1'b1, w_fp[22:0], 2'b0}; 
    wire [25:0] mant_w_third = (mant_w >> 2) + (mant_w >> 4) + (mant_w >> 6) + (mant_w >> 8);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 5'd0;
            out_valid <= 1'b0;
            mul_req <= 1'b0;
            fma_req <= 1'b0;
            status_overflow <= 1'b0;
            status_underflow <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            mul_req   <= 1'b0; 
            fma_req   <= 1'b0;
            
            case (state)
                0: begin 
                    if (in_valid) begin
                        if (in_operand_A[30:0] == 0) begin
                            out_valid <= 1'b1;
                            out_result <= 32'd0;
                            status_zero <= 1'b1;
                        end else begin
                            sign_res <= in_operand_A[31];
                            
                            begin : PRE_PROCESS_CBRT
                                wire signed [9:0] e_diff = $signed({2'b00, in_operand_A[30:23]}) - 10'sd127;
                                if (e_diff >= 0) begin
                                    k_exp <= e_diff / 3;
                                    e_mod <= e_diff % 3;
                                end else begin
                                    k_exp <= (e_diff - 2) / 3;
                                    e_mod <= (e_diff % 3 == -1) ? 2'd2 : 
                                             (e_diff % 3 == -2) ? 2'd1 : 2'd0;
                                end
                            end
                            state <= 5'd1;
                        end
                    end
                end
                
                1: begin
                    if (e_mod == 1) w_fp <= {1'b0, 8'd128, in_operand_A[22:0]};
                    else if (e_mod == 2) w_fp <= {1'b0, 8'd129, in_operand_A[22:0]};
                    else w_fp <= {1'b0, 8'd127, in_operand_A[22:0]};
                    state <= 5'd2;
                end
                
                2: begin
                    w_third_fp <= {1'b1, w_fp[30:23], mant_w_third[24:2]}; // -w/3
                    state <= 5'd3;
                end
                
                3: begin
                    y0_fp <= lut_data_fp; // Nhan Padé Seed tu ROM
                    state <= 5'd4;
                end
                
                // NR: t1 = y0 * y0
                4: begin
                    mul_req  <= 1'b1;
                    mul_op_a <= y0_fp;
                    mul_op_b <= y0_fp;
                    state    <= 5'd5;
                end
                5: if (mul_ack) begin
                    t1_fp <= mul_result;
                    state <= 5'd6;
                end
                
                // NR: t2 = y0 * t1 (y0^3)
                6: begin
                    mul_req  <= 1'b1;
                    mul_op_a <= y0_fp;
                    mul_op_b <= t1_fp;
                    state    <= 5'd7;
                end
                7: if (mul_ack) begin
                    fma_req  <= 1'b1;
                    fma_op_a <= w_third_fp;       
                    fma_op_b <= mul_result;       // y0^3
                    fma_op_c <= 32'h3FAAAAAB;     // 4/3
                    state    <= 5'd8;
                end
                
                // NR: t3 = 4/3 - (w/3) * y0^3
                8: if (fma_ack) begin
                    mul_req  <= 1'b1;
                    mul_op_a <= y0_fp;
                    mul_op_b <= fma_result; // t3
                    state    <= 5'd9;
                end
                
                // NR: y1 = y0 * t3
                9: if (mul_ack) begin
                    y1_fp <= mul_result;
                    mul_req  <= 1'b1;
                    mul_op_a <= mul_result;
                    mul_op_b <= mul_result;
                    state    <= 5'd10;
                end
                
                // NR: y1^2
                10: if (mul_ack) begin
                    mul_req  <= 1'b1;
                    mul_op_a <= w_fp;
                    mul_op_b <= mul_result;
                    state    <= 5'd11;
                end
                
                // Final: cbrt(w) = w * y1^2
                11: if (mul_ack) begin
                    out_valid  <= 1'b1;
                    out_result <= {sign_res, mul_result[30:23] + k_exp, mul_result[22:0]};
                    status_invalid <= 1'b0;
                    status_zero <= 1'b0;
                    state      <= 5'd0;
                end
                
                default: state <= 5'd0;
            endcase
        end
    end
endmodule