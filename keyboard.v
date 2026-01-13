`timescale 1ns / 1ps
module keyboard(
    input  wire        clk,
    input  wire        rst,
    input  wire [3:0]  col,     // 物理连接到了行 (Rows)
    output reg  [3:0]  row,     // 物理连接到了列 (Cols)
    output reg  [3:0]  key_out,
    output reg         pressed
);
    // 1. 扫描计数器
    reg [19:0] cnt;
    always @(posedge clk) begin
        if (rst) cnt <= 0;
        else cnt <= cnt + 1;
    end
    wire [1:0] scan_idx = cnt[19:18];

    // 2. 扫描输出
    always @* begin
        case (scan_idx)
            2'd0: row = 4'b1110; // 扫描第1根线
            2'd1: row = 4'b1101; // 扫描第2根线 (物理上接的是 ABCD 列)
            2'd2: row = 4'b1011; // 扫描第3根线
            2'd3: row = 4'b0111; // 扫描第4根线 (物理上接的是 2580 列)
            default: row = 4'b1111;
        endcase
    end

    // 3. 采样与映射 (已修复 2/A 列互换问题)
    always @(posedge clk) begin
        if (rst) begin
            pressed <= 0;
            key_out <= 0;
        end else begin
            if (col != 4'b1111) begin
                pressed <= 1;
                case (scan_idx)
                    // ------------------------------------------------
                    // 扫描第1根线 -> 对应第1列 (1, 4, 7, *)
                    // ------------------------------------------------
                    2'd0: begin 
                        if (!col[3]) key_out <= 4'h1; // 1
                        if (!col[2]) key_out <= 4'h4; // 4
                        if (!col[1]) key_out <= 4'h7; // 7
                        if (!col[0]) key_out <= 4'hE; // *
                    end
                    
                    // ------------------------------------------------
                    // 扫描第2根线 -> 物理对应第4列 (A, B, C, D) 【已交换】
                    // ------------------------------------------------
                    2'd1: begin 
                        if (!col[3]) key_out <= 4'hA; // A
                        if (!col[2]) key_out <= 4'hB; // B
                        if (!col[1]) key_out <= 4'hC; // C
                        if (!col[0]) key_out <= 4'hD; // D
                    end
                    
                    // ------------------------------------------------
                    // 扫描第3根线 -> 对应第3列 (3, 6, 9, #)
                    // ------------------------------------------------
                    2'd2: begin 
                        if (!col[3]) key_out <= 4'h3; // 3
                        if (!col[2]) key_out <= 4'h6; // 6
                        if (!col[1]) key_out <= 4'h9; // 9
                        if (!col[0]) key_out <= 4'hF; // #
                    end
                    
                    // ------------------------------------------------
                    // 扫描第4根线 -> 物理对应第2列 (2, 5, 8, 0) 【已交换】
                    // ------------------------------------------------
                    2'd3: begin 
                        if (!col[3]) key_out <= 4'h2; // 2
                        if (!col[2]) key_out <= 4'h5; // 5
                        if (!col[1]) key_out <= 4'h8; // 8
                        if (!col[0]) key_out <= 4'h0; // 0
                    end
                endcase
            end else begin
                pressed <= 0;
            end
        end
    end
endmodule