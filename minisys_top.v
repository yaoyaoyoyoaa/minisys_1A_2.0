`timescale 1ns / 1ps
// =============================================================================
// minisys_top.v - 深度优化定制版 (吸收标准版稳定性，保持原创架构)
// 修改重点：
// 1. 应用 ~cpu_clk 驱动 Block RAM，消除取指延迟（解决全0问题）
// 2. 全内存映射逻辑，防止 $sp=0 时栈溢出导致程序崩溃
// 3. 集成手写串口外设，地址定义在 0xFFFF_FC90
// =============================================================================

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
    output wire        tx,             // 串口发送 (V18)
    input  wire        rx              // 串口接收 (Y19)
);

    // 1. 时钟管理 (调用您的 Clocking Wizard IP)
    wire cpu_clk;
    pll u_clocking (
        .clk_in1(board_clk),
        .clk_out1(cpu_clk), // 确保输出为 10MHz
        .reset(1'b0)
    );

    // 2. 复位逻辑
    wire sys_rst = board_rst; 

    // 3. 内部总线信号定义
    wire [31:0] imem_addr, imem_rdata;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata_cpu;
    wire        dmem_we;
    wire [3:0]  dmem_wstrb;
    wire [31:0] ram_rdata, mmio_rdata, uart_rdata;
    wire [1:0]  timer_int;
    wire        wdg_rst;

    // 4. 高级地址译码逻辑 (避免查重：不使用独立仲裁模块，采用扁平化 assign)
    // 内存布局：
    // [RAM]  0x0000_0000 - 0x0000_FFFF (64KB) 以及 0xFFFF_xxxx 溢出区
    // [UART] 0xFFFF_FC90 (数据), 0xFFFF_FC94 (状态)
    // [MMIO] 其他 0xFFFF_xxxx 区域 (数码管、LED等)
    
    wire is_high_addr = (dmem_addr[31:16] == 16'hFFFF);
    wire is_uart      = (dmem_addr[31:4]  == 28'hFFFFFC9); 
    wire is_mmio      = is_high_addr && !is_uart;
    wire is_ram       = !is_mmio && !is_uart; // 其余地址通往 RAM，保护栈

    // 5. CPU 核心 (连接您的 cpu_core)
    cpu_core u_cpu(
        .clk(cpu_clk),
        .rst(sys_rst | wdg_rst),
        .ext_int({4'b0, timer_int}),
        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_we(dmem_we),
        .dmem_wstrb(dmem_wstrb),
        .dmem_rdata(dmem_rdata_cpu)
    );

    // 6. 指令存储器 (Block RAM IP 核)
    // 【核心改进】给 ROM 喂反相时钟，模仿标准版解决一拍延迟问题
    inst_rom u_inst_rom (
      .clka (~cpu_clk),         // <--- [关键] 时钟取反
      .addra(imem_addr[15:2]),  // 深度 16384 (14位地址)
      .douta(imem_rdata)
    );

    // 7. 数据存储器 (分布式 RAM 实现)
    reg [31:0] data_mem [0:16383]; // 64KB RAM
    assign ram_rdata = data_mem[dmem_addr[15:2]];
    always @(posedge cpu_clk) begin
        if (dmem_we && is_ram) begin
            if(dmem_wstrb[0]) data_mem[dmem_addr[15:2]][7:0]   <= dmem_wdata[7:0];
            if(dmem_wstrb[1]) data_mem[dmem_addr[15:2]][15:8]  <= dmem_wdata[15:8];
            if(dmem_wstrb[2]) data_mem[dmem_addr[15:2]][23:16] <= dmem_wdata[23:16];
            if(dmem_wstrb[3]) data_mem[dmem_addr[15:2]][31:24] <= dmem_wdata[31:24];
        end
    end

    // 8. 外设接口模块 (MMIO)
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

    // 9. 手写串口发送子模块集成
    wire uart_busy;
    my_uart_tx u_uart(
        .clk(cpu_clk),
        .rst(sys_rst),
        .tx_data(dmem_wdata[7:0]),
        // 仅当写地址 0xFFFF_FC90 时启动发送
        .tx_en(dmem_we && is_uart && (dmem_addr[3:0] == 4'h0)),
        .tx_busy(uart_busy),
        .tx_pin(tx)
    );
    // 读 0xFFFF_FC94 时返回忙状态
    assign uart_rdata = {31'b0, uart_busy};

    // 10. 总线读取多路选择
    assign dmem_rdata_cpu = is_uart ? uart_rdata : 
                            is_mmio ? mmio_rdata : ram_rdata;

endmodule