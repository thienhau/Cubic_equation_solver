module cardano_fpu_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [31:0] a, b, c, d,
    
    output wire        valid_out,
    output wire [1:0]  num_roots,
    output wire [31:0] x1, x2, x3
);

    // 1. Phân loại cấu hình từ đầu vào
    wire is_quad = (a == 32'h00000000); 
    
    // -------------------------------------------------------------
    // KHỐI TIỀN XỬ LÝ (Pre-processing: Tính p, q, Delta, offset)
    // Trễ giả định: 25 Chu kỳ
    // -------------------------------------------------------------
    wire        pre_valid_out;
    wire [31:0] p_val, q_val, delta_val, offset_val;
    wire        delta_is_pos; // 1 = 1 nghiệm, 0 = 3 nghiệm
    
    // (Bên trong khối này bạn cắm mạch tính: p = (3ac-b^2)/3a^2, v.v...)
    // Mock signal:
    assign pre_valid_out = valid_in; // Cần delay line thực tế cho pre_valid
    assign delta_is_pos  = delta_val[31] == 1'b0; 

    // -------------------------------------------------------------
    // SYNC FIFO BYPASS (Cứu tinh Area)
    // Đẩy metadata vào FIFO khi kết thúc Pre-processing
    // -------------------------------------------------------------
    wire fifo_push = pre_valid_out;
    wire fifo_pop; 
    wire [1:0] meta_in = {is_quad, delta_is_pos};
    wire [1:0] meta_out;
    
    sync_fifo_bypass #(.DATA_WIDTH(2), .DEPTH_LOG2(5)) u_bypass_fifo (
        .clk(clk), .rst_n(rst_n),
        .push(fifo_push), .pop(fifo_pop),
        .data_in(meta_in), .data_out(meta_out),
        .empty(), .full()
    );

    wire out_is_quad     = meta_out[1];
    wire out_delta_is_pos = meta_out[0];

    // -------------------------------------------------------------
    // ĐỊNH TUYẾN SANG CÁC NHÁNH (Routing)
    // Chỉ kích hoạt mạch (Clock Gating) tương ứng để tiết kiệm điện
    // -------------------------------------------------------------
    wire en_quad   = pre_valid_out & is_quad;
    wire en_radic  = pre_valid_out & ~is_quad & delta_is_pos;
    wire en_trigon = pre_valid_out & ~is_quad & ~delta_is_pos;

    // Nhánh 1: Bậc 2
    wire v_quad; wire [31:0] q_x1, q_x2;
    quad_path U_QUAD (
        .clk(clk), .rst_n(rst_n), .in_valid(en_quad),
        .b(b), .c(c), .d(d),
        .out_valid(v_quad), .x1(q_x1), .x2(q_x2)
    );

    // Nhánh 2: Bậc 3 (Delta > 0)
    wire v_radic; wire [31:0] r_x1;
    radic_path U_RADI (
        .clk(clk), .rst_n(rst_n), .in_valid(en_radic),
        .p(p_val), .q(q_val), .delta(delta_val), .offset(offset_val),
        .out_valid(v_radic), .x1(r_x1)
    );

    // Nhánh 3: Bậc 3 (Delta < 0)
    wire v_trigon; wire [31:0] t_x1, t_x2, t_x3;
    trigon_path U_TRIG (
        .clk(clk), .rst_n(rst_n), .in_valid(en_trigon),
        .p(p_val), .q(q_val), .offset(offset_val),
        .out_valid(v_trigon), .x1(t_x1), .x2(t_x2), .x3(t_x3)
    );

    // -------------------------------------------------------------
    // GOM NGHIỆM VÀ POP FIFO
    // -------------------------------------------------------------
    // Bất kỳ nhánh nào tính xong cũng sẽ kích hoạt Output Valid và Pop FIFO
    assign valid_out = v_quad | v_radic | v_trigon;
    assign fifo_pop  = valid_out; // Rút siêu dữ liệu của phương trình tương ứng ra

    // Đếm số nghiệm dựa trên siêu dữ liệu đi tắt qua FIFO
    assign num_roots = out_is_quad ? 2'd2 : (out_delta_is_pos ? 2'd1 : 2'd3);

    // MUX cuối cùng (Sử dụng metadata từ FIFO để chọn đúng Bus)
    assign x1 = out_is_quad ? q_x1 : (out_delta_is_pos ? r_x1 : t_x1);
    assign x2 = out_is_quad ? q_x2 : (out_delta_is_pos ? 32'h0 : t_x2);
    assign x3 = out_is_quad ? 32'h0 : (out_delta_is_pos ? 32'h0 : t_x3);

endmodule