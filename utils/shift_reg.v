`timescale 1ns / 1ps

module shift_reg #(
    parameter W = 32,
    parameter D = 1
)(
    input  wire         clk,
    input  wire [W-1:0] in,
    output wire [W-1:0] out
);
    generate
        if (D == 0) begin : gen_pass
            assign out = in;
        end else begin : gen_delay
            reg [W-1:0] pipes [0:D-1];
            integer i;
            
            always @(posedge clk) begin
                pipes[0] <= in;
                for (i = 1; i < D; i = i + 1) begin
                    pipes[i] <= pipes[i-1];
                end
            end
            assign out = pipes[D-1];
        end
    endgenerate
endmodule