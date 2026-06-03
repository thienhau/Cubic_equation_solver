`timescale 1ns / 1ps

module cardano_top #(
    parameter PRE_PROCESS_STAGES = 52,
    parameter QUAD_PATH_STAGES = 48,
    parameter RADIC_PATH_STAGES = 123,
    parameter TRIGON_PATH_STAGES = 147
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [7:0]  trans_id_in,
    input  wire [31:0] a, b, c, d,
    
    output wire        valid_out,
    output wire [7:0]  trans_id_out,
    output wire [1:0]  num_roots,
    output wire [31:0] x1, x2, x3,
    // PORT BỔ SUNG CHO NGHIỆM PHỨC
    output wire [31:0] x2_imag, x3_imag,
    output wire [31:0] x2_mag,  x3_mag,
    output wire [31:0] x2_phase, x3_phase
);

    // ==============================================================================
    // GÓI KHỐI PRE-PROCESS (Tiền xử lý hệ số, T = 0 -> 52)
    // ==============================================================================
    wire v52;
    wire [7:0] id_52;
    wire is_quad_52, delta_is_pos;
    wire [31:0] b_52, c_52, d_52;
    wire [31:0] p_val, q_val, delta_val, offset_val;

    pre_process #(.STAGES(PRE_PROCESS_STAGES)) u_pre_process (
        .clk(clk), .rst_n(rst_n),
        .valid_in(valid_in), .trans_id_in(trans_id_in),
        .a(a), .b(b), .c(c), .d(d),
        
        .valid_out(v52),
        .trans_id_out(id_52),
        .is_quad_out(is_quad_52),
        .delta_is_pos_out(delta_is_pos),
        
        .b_out(b_52), .c_out(c_52), .d_out(d_52),
        .p_out(p_val), .q_out(q_val), .delta_out(delta_val), .offset_out(offset_val)
    );

    // ==============================================================================
    // KHỐI ĐỊNH TUYẾN DỮ LIỆU VÀ ĐIỀU KHIỂN (ROUTING)
    // ==============================================================================
    wire pre_valid_out = v52;
    
    wire fifo_push = pre_valid_out;
    wire fifo_pop  = pre_valid_out; 
    wire [1:0] meta_in = {is_quad_52, delta_is_pos};
    wire [1:0] meta_out;

    sync_fifo_bypass #(.DATA_WIDTH(2), .DEPTH_LOG2(5)) u_bypass_fifo (
        .clk(clk), .rst_n(rst_n), .push(fifo_push), .pop(fifo_pop),
        .data_in(meta_in), .data_out(meta_out),
        .empty(), .full()
    );

    wire out_is_quad      = meta_out[1];
    wire out_delta_is_pos = meta_out[0];

    wire en_quad   = pre_valid_out & is_quad_52;
    wire en_radic  = pre_valid_out & ~is_quad_52 & delta_is_pos;
    wire en_trigon = pre_valid_out & ~is_quad_52 & ~delta_is_pos;

    // ==============================================================================
    // T = 52 -> 100: NHÁNH 1 BẬC 2 (48 Chu kỳ)
    // ==============================================================================
    wire v_quad;
    wire [31:0] q_x1, q_x2;
    quad_path #(.STAGES(48)) u_quad (
        .clk(clk), .rst_n(rst_n), .in_valid(en_quad), 
        .b(b_52), .c(c_52), .d(d_52), 
        .out_valid(v_quad), .x1(q_x1), .x2(q_x2)
    );
    
    wire [7:0] id_quad_out;
    shift_reg #(.W(8), .D(48)) dly_id_q (.clk(clk), .in(id_52), .out(id_quad_out));


    // ==============================================================================
    // T = 52 -> 175: NHÁNH 2 RADIC - CẬP NHẬT TRỄ GÓC PHỨC (123 Chu kỳ mới)
    // ==============================================================================
    wire v_radic;
    wire [31:0] r_x1, r_x2_real, r_x2_imag, r_x2_mag, r_x2_phase;
    radic_path #(.STAGES(123)) u_radic (
        .clk(clk), .rst_n(rst_n), .in_valid(en_radic), 
        .p(p_val), .q(q_val), .delta(delta_val), .offset(offset_val), 
        .out_valid(v_radic), 
        .x1_real(r_x1), .x2_real(r_x2_real), .x2_imag(r_x2_imag), 
        .x2_mag(r_x2_mag), .x2_phase(r_x2_phase)
    );
    
    wire [7:0] id_radic_out;
    shift_reg #(.W(8), .D(123)) dly_id_r (.clk(clk), .in(id_52), .out(id_radic_out));


    // ==============================================================================
    // T = 52 -> 199: NHÁNH 3 TRIGON - CẬP NHẬT 147 CHU KỲ MỚI
    // ==============================================================================
    wire v_trigon;
    wire [31:0] t_x1, t_x2, t_x3;
    trigon_path #(.STAGES(147)) u_trigon (
        .clk(clk), .rst_n(rst_n), .in_valid(en_trigon), 
        .p(p_val), .q(q_val), .offset(offset_val), 
        .out_valid(v_trigon), .x1(t_x1), .x2(t_x2), .x3(t_x3)
    );
    
    wire [7:0] id_trigon_out;
    shift_reg #(.W(8), .D(147)) dly_id_t (.clk(clk), .in(id_52), .out(id_trigon_out));

    // ==============================================================================
    // T = * -> *: Bộ trọng tài Out-of-Order VÀ FIFOs
    // ==============================================================================
    wire quad_empty, radic_empty, trigon_empty;
    wire [201:0] quad_data_out, radic_data_out, trigon_data_out;
    wire pop_quad, pop_radic, pop_trigon;

    sync_fifo_bypass #(.DATA_WIDTH(202), .DEPTH_LOG2(4)) fifo_quad (
        .clk(clk), .rst_n(rst_n), .push(v_quad), .pop(pop_quad),
        .data_in({id_quad_out, 2'd2, q_x1, q_x2, 32'd0, 32'd0, 32'd0, 32'd0}), .data_out(quad_data_out), .empty(quad_empty), .full()
    );
    sync_fifo_bypass #(.DATA_WIDTH(202), .DEPTH_LOG2(4)) fifo_radic (
        .clk(clk), .rst_n(rst_n), .push(v_radic), .pop(pop_radic),
        .data_in({id_radic_out, 2'd1, r_x1, r_x2_real, r_x2_real, r_x2_imag, r_x2_mag, r_x2_phase}), .data_out(radic_data_out), .empty(radic_empty), .full()
    );
    sync_fifo_bypass #(.DATA_WIDTH(202), .DEPTH_LOG2(4)) fifo_trigon (
        .clk(clk), .rst_n(rst_n), .push(v_trigon), .pop(pop_trigon),
        .data_in({id_trigon_out, 2'd3, t_x1, t_x2, t_x3, 32'd0, 32'd0, 32'd0}), .data_out(trigon_data_out), .empty(trigon_empty), .full()
    );

    // Arbiter
    assign pop_quad   = !quad_empty;
    assign pop_radic  = !quad_empty ? 1'b0 : !radic_empty;
    assign pop_trigon = (!quad_empty || !radic_empty) ? 1'b0 : !trigon_empty;

    assign valid_out = pop_quad | pop_radic | pop_trigon;

    wire [201:0] final_data = pop_quad ? quad_data_out : (pop_radic ? radic_data_out : trigon_data_out);

    // MÁP LẠI TÍN HIỆU ĐẦU RA (Un-packing 202 bits)
    assign trans_id_out = final_data[201:194];
    assign num_roots    = final_data[193:192];
    assign x1           = final_data[191:160];
    assign x2           = final_data[159:128];
    assign x3           = final_data[127:96];
    
    wire [31:0] b_img   = final_data[95:64];
    wire [31:0] b_mag   = final_data[63:32];
    wire [31:0] b_phs   = final_data[31:0];

    // Tạo các liên hợp phức nếu là nhánh 1 nghiệm (Radic)
    assign x2_imag  = (num_roots == 2'd1) ? b_img : 32'd0;
    assign x3_imag  = (num_roots == 2'd1) ? {~b_img[31], b_img[30:0]} : 32'd0; // Đảo dấu liên hợp
    assign x2_mag   = (num_roots == 2'd1) ? b_mag : 32'd0;
    assign x3_mag   = (num_roots == 2'd1) ? b_mag : 32'd0; // Bán kính không đổi
    assign x2_phase = (num_roots == 2'd1) ? b_phs : 32'd0;
    assign x3_phase = (num_roots == 2'd1) ? {~b_phs[31], b_phs[30:0]} : 32'd0; // Góc liên hợp âm

endmodule