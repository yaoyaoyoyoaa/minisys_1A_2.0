`timescale 1ns / 1ps
// cp0_regfile.v - 协处理器0 (功能补全版：带定时器与中断屏蔽)
module cp0_regfile(
    input  wire        clk,
    input  wire        rst,
    input  wire        we,          // 写使能 (MTC0)
    input  wire [4:0]  addr,        // 寄存器地址
    input  wire [31:0] din,         // 写入数据
    input  wire [5:0]  ext_int,     // 外部硬件中断输入 (6位)
    input  wire        exception_i, // 异常发生信号 (来自CPU核心)
    input  wire [31:0] epc_i,       // 异常返回地址 (EPC)
    input  wire [4:0]  cause_type,  // 异常类型编码 (5位, 0=Int, 8=Sys, 9=Bp, 12=Ovf)
    
    output reg  [31:0] data_o,      // 读出数据 (MFC0)
    output wire [31:0] epc_o,       // 输出给 PC 的 EPC 值
    output wire        irq_o        // [关键] 经过屏蔽判断后的最终中断请求
);

    // --- 寄存器定义 ---
    // 9:  Count (计数器)
    // 11: Compare (比较器)
    // 12: Status (状态寄存器: IE, EXL, IM)
    // 13: Cause (原因寄存器: BD, TI, IP, ExcCode)
    // 14: EPC (异常程序计数器)
    reg [31:0] count;
    reg [31:0] compare;
    reg [31:0] status;
    reg [31:0] cause;
    reg [31:0] epc;

    assign epc_o = epc;

    // --- 1. 定时器逻辑 (Count & Compare) ---
    // Count 寄存器每两个时钟周期加 1 (符合 MIPS 规范) 或者每周期加 1
    // 这里为了简化仿真，采用每周期加 1
    wire timer_int_req = (count == compare) && (compare != 0);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count   <= 0;
            compare <= 0;
        end else begin
            if (we && addr == 5'd9)       count <= din; // 写入 Count
            else                          count <= count + 1;
            
            if (we && addr == 5'd11)      compare <= din; // 写入 Compare
        end
    end

    // --- 2. 中断请求生成 (IRQ) ---
    // Status 寄存器位: [15:8] Mask (IM), [1] EXL, [0] IE
    // Cause 寄存器位:  [15:10] IP[7:2] (Ext), [30] TI (Timer)
    
    // 内部定时器中断映射到 Cause 的 IP7 (位15) 或 TI (位30)
    // Minisys 习惯将定时器中断视为硬件中断之一，这里映射到 Cause[30] (TI) 和 IP7 (bit 15) 以确保兼容性
    wire [7:0] active_interrupts;
    assign active_interrupts = {timer_int_req, ext_int[5:0], 1'b0}; // {IP7..IP0}
    
    // 最终中断触发条件: 
    // 1. 有中断请求 (硬件或定时器)
    // 2. Status.IE = 1 (全局使能)
    // 3. Status.EXL = 0 (不在异常级)
    // 4. Status.IM 对应位为 1 (该中断未被屏蔽)
    wire global_int_en = status[0] && !status[1]; // IE=1 && EXL=0
    wire int_pending   = (cause[15:8] & status[15:8]) != 0; // 检查掩码
    
    assign irq_o = global_int_en && int_pending;

    // --- 3. 寄存器读写与异常处理 ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            status <= 32'h00000001; // 默认开启中断 (IE=1)
            cause  <= 0;
            epc    <= 0;
        end else begin
            // 持续采样中断信号到 Cause 寄存器
            cause[15:10] <= ext_int;      // 外部中断 IP7..IP2 -> 映射到 IP
            cause[30]    <= timer_int_req;// TI 位
            // 同时将定时器也映射到 IP7 (位15) 以便通过 Status[15] 进行屏蔽控制
            if (timer_int_req) cause[15] <= 1'b1; 
            else               cause[15] <= ext_int[5]; // 如果没有定时器中断，保持外部值

            if (exception_i) begin
                // === 异常发生时 ===
                epc <= epc_i;
                status[1] <= 1'b1;        // 设置 EXL=1 (进入异常模式，自动屏蔽中断)
                cause[6:2] <= cause_type; // 记录异常类型 (ExcCode)
                cause[31] <= 1'b0;        // BD (分支延迟槽标志，暂简写为0)
            end else if (we) begin
                // === 正常写寄存器 ===
                case(addr)
                    5'd12: status <= din;
                    5'd13: cause  <= din;
                    5'd14: epc    <= din;
                    // Count 和 Compare 已在上方处理
                endcase
            end
        end
    end

    // --- 读操作 ---
    always @* begin
        case(addr)
            5'd9:  data_o = count;
            5'd11: data_o = compare;
            5'd12: data_o = status;
            5'd13: data_o = cause;
            5'd14: data_o = epc;
            default: data_o = 0;
        endcase
    end

endmodule