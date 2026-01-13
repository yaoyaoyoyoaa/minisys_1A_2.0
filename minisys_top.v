`timescale 1ns / 1ps
// minisys_top.v
// 适配新 cpu_core 接口，保持 ~cpu_clk 驱动 ROM 策略
module minisys_top(
    input  wire        board_clk,      // 100MHz
    input  wire        board_rst,      // 板载复位
    input  wire [23:0] switches_in,    // 拨码开关
    input  wire [4:0]  buttons_in,     // 按钮
    input  wire [3:0]  keyboard_cols_in, // 矩阵键盘列
    output wire [3:0]  keyboard_rows_out,// 矩阵键盘行
    output wire [7:0]  digits_sel_out,   // 数码管位选
    output wire [7:0]  digits_data_out,  // 数码管段选
    output wire [7:0]  led_RLD_out,    // 红灯
    output wire [7:0]  led_YLD_out,    // 黄灯
    output wire [7:0]  led_GLD_out,    // 绿灯
    output wire        beep_out,       // 蜂鸣器
    output wire        tx,             // 串口发送
    input  wire        rx              // 串口接收
);

    // 1. 时钟管理
    wire cpu_clk;
    pll u_clocking (
        .clk_in1(board_clk),
        .clk_out1(cpu_clk), // 10MHz (或根据 PLL 设置)
        .reset(1'b0)
    );

    // 2. 复位逻辑
    wire sys_rst = board_rst; 

    // 3. 内部总线信号
    wire [31:0] imem_addr, imem_rdata;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata_cpu;
    wire        dmem_we;
    wire [3:0]  dmem_wstrb;
    wire [31:0] ram_rdata, mmio_rdata, uart_rdata;
    wire [1:0]  timer_int;
    wire        wdg_rst;
    wire [31:0] dbg_pc; // 新增调试信号

    // 4. 地址译码
    wire is_high_addr = (dmem_addr[31:16] == 16'hFFFF);
    wire is_uart      = (dmem_addr[31:4]  == 28'hFFFFFC9);
    wire is_mmio      = is_high_addr && !is_uart;
    wire is_ram       = !is_mmio && !is_uart;

    // 5. CPU 核心 (接口已更新)
    cpu_core u_cpu(
        .clk(cpu_clk),
        .rst(sys_rst | wdg_rst),
        .ext_int({4'b0, timer_int}), // 连接定时器中断
        // 指令总线
        .imem_rdata(imem_rdata),
        .imem_addr(imem_addr),
        // 数据总线
        .dmem_rdata(dmem_rdata_cpu),
        .dmem_we(dmem_we),
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_wstrb(dmem_wstrb),
        // 调试
        .dbg_pc(dbg_pc)
    );

    // 6. 指令存储器 (使用 ~cpu_clk 解决取指延迟)
    inst_rom u_inst_rom (
      .clka (~cpu_clk),        
      .addra(imem_addr[15:2]), 
      .douta(imem_rdata)
    );

    // 7. 数据存储器 (分布式 RAM)
    reg [31:0] data_mem [0:16383];
    assign ram_rdata = data_mem[dmem_addr[15:2]];
    
    always @(posedge cpu_clk) begin
        if (dmem_we && is_ram) begin
            if(dmem_wstrb[0]) data_mem[dmem_addr[15:2]][7:0]   <= dmem_wdata[7:0];
            if(dmem_wstrb[1]) data_mem[dmem_addr[15:2]][15:8]  <= dmem_wdata[15:8];
            if(dmem_wstrb[2]) data_mem[dmem_addr[15:2]][23:16] <= dmem_wdata[23:16];
            if(dmem_wstrb[3]) data_mem[dmem_addr[15:2]][31:24] <= dmem_wdata[31:24];
        end
    end

    // 8. 外设接口 (MMIO)
    mmio_if u_mmio(
        .clk(cpu_clk),
        .rst(sys_rst),
        .we(dmem_we && is_mmio),
        .be(dmem_wstrb),
        .addr(dmem_addr),
        .wdata(dmem_wdata),
        .rdata(mmio_rdata),
        .switches(switches_in),
        .col(keyboard_cols_in),
        .led_out({led_RLD_out, led_YLD_out, led_GLD_out}),
        .seg_out(digits_data_out),
        .an_out(digits_sel_out),
        .row(keyboard_rows_out),
        .beep_out(beep_out),
        .pwm_out(),
        .wdg_rst_req(wdg_rst),
        .timer_int(timer_int)
    );

    // 9. 串口发送模块
    wire uart_busy;
    my_uart_tx u_uart(
        .clk(cpu_clk),
        .rst(sys_rst),
        .tx_data(dmem_wdata[7:0]),
        .tx_en(dmem_we && is_uart && (dmem_addr[3:0] == 4'h0)),
        .tx_busy(uart_busy),
        .tx_pin(tx)
    );
    assign uart_rdata = {31'b0, uart_busy};

    // 10. 读数据多路选择
    assign dmem_rdata_cpu = is_uart ? uart_rdata : 
                            is_mmio ? mmio_rdata : ram_rdata;

endmodule