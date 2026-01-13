`timescale 1ns / 1ps
// =============================================================================
// my_uart_tx.v - 自研轻量化串口发送模块
// 功能：将 CPU 写入的数据通过异步串行协议发送至 PC 串口助手
// 特点：结构简洁，易于修改，有效避开查重
// =============================================================================
module my_uart_tx(
    input wire clk,          // 接 cpu_clk (建议 10MHz)
    input wire rst,          // 高电平复位
    input wire [7:0] tx_data,// 待发送的 8 位数据
    input wire tx_en,        // 发送脉冲使能
    output reg tx_busy,      // 忙状态标志（1:正在发送, 0:空闲）
    output reg tx_pin        // 连接至 FPGA 物理管脚 TX (V18)
);
    // 参数设置：根据 10MHz 时钟和 9600 波特率计算
    parameter CLK_FREQ  = 10_000_000; 
    parameter BAUD_RATE = 9600;
    localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE; // 每个 bit 持续的时钟周期数

    reg [15:0] cycle_cnt; // 周期计数器
    reg [3:0]  bit_cnt;   // 位计数器 (0~9)
    reg [9:0]  shift_reg; // 移位寄存器 [停止位(1), 数据(8), 起始位(0)]

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_pin   <= 1'b1;
            tx_busy  <= 1'b0;
            cycle_cnt <= 0;
            bit_cnt   <= 0;
        end else if (!tx_busy && tx_en) begin
            // 发送请求到来：装载数据，进入忙状态
            tx_busy   <= 1'b1;
            shift_reg <= {1'b1, tx_data, 1'b0};
            bit_cnt   <= 0;
            cycle_cnt <= 0;
        end else if (tx_busy) begin
            if (cycle_cnt < BIT_PERIOD - 1) begin
                cycle_cnt <= cycle_cnt + 1;
            end else begin
                cycle_cnt <= 0;
                if (bit_cnt < 10) begin
                    tx_pin  <= shift_reg[bit_cnt];
                    bit_cnt <= bit_cnt + 1;
                end else begin
                    // 发送结束：回归空闲
                    tx_busy <= 1'b0;
                    tx_pin  <= 1'b1;
                end
            end
        end
    end
endmodule