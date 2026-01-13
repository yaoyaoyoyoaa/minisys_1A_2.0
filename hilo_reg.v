`timescale 1ns / 1ps
// hilo_reg.v - HILO 寄存器堆与乘除法单元
module hilo_reg(
    input  wire        clk,
    input  wire        rst,
    input  wire [2:0]  op,      // 操作码: 0=无, 1=MULT, 2=MULTU, 3=DIV, 4=DIVU, 5=MTHI, 6=MTLO
    input  wire [31:0] a,       // 操作数 A (rs)
    input  wire [31:0] b,       // 操作数 B (rt)
    output wire [31:0] hi_o,    // HI 读出
    output wire [31:0] lo_o     // LO 读出
);

    reg [31:0] hi;
    reg [31:0] lo;

    // 读输出
    assign hi_o = hi;
    assign lo_o = lo;

    // 写逻辑 (时序逻辑)
    always @(posedge clk) begin
        if (rst) begin
            hi <= 32'b0;
            lo <= 32'b0;
        end else begin
            case (op)
                3'd1: {hi, lo} <= $signed(a) * $signed(b);    // MULT
                3'd2: {hi, lo} <= a * b;                      // MULTU
                3'd3: begin                                   // DIV
                    if (b != 0) begin
                        lo <= $signed(a) / $signed(b);
                        hi <= $signed(a) % $signed(b);
                    end
                end
                3'd4: begin                                   // DIVU
                    if (b != 0) begin
                        lo <= a / b;
                        hi <= a % b;
                    end
                end
                3'd5: hi <= a;                                // MTHI (rs -> hi)
                3'd6: lo <= a;                                // MTLO (rs -> lo)
                default: ; // 保持不变
            endcase
        end
    end

endmodule