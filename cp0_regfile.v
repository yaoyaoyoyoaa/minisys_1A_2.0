`timescale 1ns / 1ps
// cp0_regfile.v
// 修改：对齐标准版 Cause 寄存器定义 (IntPend 位于 [13:8])
module cp0_regfile(
    input  wire        clk,
    input  wire        rst,
    input  wire        we,          // MTC0 写使能
    input  wire [4:0]  addr,        // 寄存器地址
    input  wire [31:0] din,         // 写入数据
    
    input  wire [5:0]  ext_int,     // 外部中断输入
    input  wire        exception_i, // 异常发生
    input  wire [31:0] epc_i,       // 异常 EPC
    input  wire [4:0]  cause_type,  // 异常类型 (ExcCode)
    
    output reg  [31:0] data_o,      // MFC0 读出数据
    output wire [31:0] epc_o,
    output wire        irq_o        // 中断请求信号
);

    // 寄存器定义
    reg [31:0] count;
    reg [31:0] compare;
    reg [31:0] status;
    reg [31:0] cause;
    reg [31:0] epc;
    
    // 定时器中断标志
    reg timer_int_flag;

    assign epc_o = epc;

    // --- 1. 定时器逻辑 ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count <= 0;
            compare <= 0;
            timer_int_flag <= 0;
        end else begin
            // Count 自增
            if (we && addr == 5'd9) count <= din;
            else count <= count + 1;

            // Compare 写入与比较
            if (we && addr == 5'd11) begin
                compare <= din;
                timer_int_flag <= 0; // 写 Compare 时清除中断
            end else if (compare != 0 && count == compare) begin
                timer_int_flag <= 1;
            end
        end
    end

    // --- 2. Cause 寄存器更新逻辑 (参考标准 cp0.v) ---
    // 标准定义: Cause[13:8] 为外部中断 (IntPend)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cause <= 0;
        end else begin
            // 更新中断挂起位
            cause[13:8] <= ext_int; 
            
            // 异常处理
            if (exception_i) begin
                cause[6:2] <= cause_type; // 更新 ExcCode
                cause[31]  <= 1'b0;       // BD
            end
            
            // 写 Cause (通常仅用于调试)
            if (we && addr == 5'd13) begin
                cause[6:2] <= din[6:2]; // 仅允许写 ExcCode 部分? 标准代码允许全写，这里跟随标准
                cause[9:8] <= din[9:8]; // IP0, IP1 (Soft Int)
            end
        end
    end

    // --- 3. Status/EPC 与中断产生 ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            status <= 32'h00000001; // IE=1 (默认开中断)
            epc    <= 0;
        end else begin
            if (exception_i) begin
                epc <= epc_i;
                status[1] <= 1'b1; // EXL=1 (进入异常级，屏蔽中断)
            end else if (we) begin
                case(addr)
                    5'd12: status <= din;
                    5'd14: epc    <= din;
                endcase
            end else if (cause_type == 5'h18) begin // 假设 5'h18 为 ERET 触发的特殊类型(如果流水线有处理)
                // 此时通常由 CPU 控制 Status[1] 自动复位，或在这里处理
                // 标准 id.v 处理了 ERET，这里假设 cpu_core 会处理 EXL 的复位
                // 如果 cpu_core 通过写 Status 来复位 EXL，则此处无需特殊处理
            end
        end
    end

    // --- 4. 中断请求生成 (IRQ) ---
    // [15:8] 为 IM (Interrupt Mask), [1] EXL, [0] IE
    // 中断源包括: 外部中断 ext_int 和 内部定时器 timer_int_flag
    // 注意：标准代码将外部中断放在 Cause[13:8]，对应 Status 的 IM[?]?
    // 通常 MIPS 中，Cause[15:8] 对应 Status[15:8]。
    // 标准代码 cp0.v 第 436 行: cause_out[13:8] <= int_in;
    // 这意味着 ext_int[0] 对应 Cause[8]，即 IP0。
    // 因此我们需要检查 Status[8] (IM0) 来屏蔽它。
    
    wire [7:0] im = status[15:8];
    // 构造当前所有待处理中断位: {timer, ext_int[5:0], 0} 
    // 假设 Timer 映射到 IP7 (bit 15)
    wire [7:0] ip;
    assign ip[7]   = timer_int_flag; // IP7 (Timer)
    assign ip[6]   = 1'b0;
    assign ip[5:0] = ext_int[5:0];   // IP5..0
    
    // 只要有任意一个未被屏蔽的中断位置 1
    wire int_req = |(ip & im);
    
    // 全局中断使能: IE=1 且 EXL=0
    assign irq_o = (status[0] && !status[1]) && int_req;

    // --- 读数据 ---
    always @* begin
        case(addr)
            5'd9:  data_o = count;
            5'd11: data_o = compare;
            5'd12: data_o = status;
            5'd13: data_o = {cause[31:16], ip[7], 1'b0, cause[13:0]}; // 读出时将 IP7(Timer) 拼接到正确位置(bit 15)
            5'd14: data_o = epc;
            default: data_o = 0;
        endcase
    end

endmodule