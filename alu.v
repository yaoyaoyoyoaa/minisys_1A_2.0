`timescale 1ns / 1ps
// alu.v
// 基于标准代码逻辑修改，适配 cpu_core 接口
module alu(
    input  wire [3:0]  op,    // 操作码，对应 cpu_core 中的定义
    input  wire [31:0] a,     // 操作数1 (rs)
    input  wire [31:0] b,     // 操作数2 (rt 或 imm)
    output reg  [31:0] y,     // 运算结果
    output wire        zf,    // 零标志
    output wire        cf,    // 进位标志
    output wire        sf,    // 符号标志
    output wire        of     // 溢出标志
);

    // 内部信号
    reg [32:0] result; // 多一位用于计算进位/溢出
    wire signed [31:0] a_signed = a;
    wire signed [31:0] b_signed = b;

    // 操作码定义 (需与 cpu_core.v 中的 case 保持一致)
    localparam ALU_ADD  = 4'h0; // 加法 (ADDU/ADD)
    localparam ALU_SUB  = 4'h1; // 减法 (SUBU/SUB)
    localparam ALU_AND  = 4'h2;
    localparam ALU_OR   = 4'h3;
    localparam ALU_XOR  = 4'h4;
    localparam ALU_SLT  = 4'h5; // 有符号比较
    localparam ALU_SLL  = 4'h6;
    localparam ALU_SRL  = 4'h7;
    localparam ALU_SRA  = 4'h8;
    localparam ALU_NOR  = 4'hA;
    localparam ALU_SLTU = 4'hB; // 无符号比较

    always @(*) begin
        result = 33'd0;
        case (op)
            ALU_ADD:  result = {1'b0, a} + {1'b0, b};
            ALU_SUB:  result = {1'b0, a} - {1'b0, b};
            ALU_AND:  result = {1'b0, a & b};
            ALU_OR:   result = {1'b0, a | b};
            ALU_XOR:  result = {1'b0, a ^ b};
            ALU_NOR:  result = {1'b0, ~(a | b)};
            ALU_SLL:  result = {1'b0, b << a[4:0]}; // 注意：移位量通常在 a (rs) 或 shamt 中，cpu_core 已处理好传入 a
            ALU_SRL:  result = {1'b0, b >> a[4:0]};
            ALU_SRA:  result = {1'b0, b_signed >>> a[4:0]}; // 标准 SRA 实现
            ALU_SLT:  result = (a_signed < b_signed) ? 33'd1 : 33'd0;
            ALU_SLTU: result = (a < b) ? 33'd1 : 33'd0;
            default:  result = 33'd0;
        endcase
        y = result[31:0];
    end

    // 标志位生成 (标准行为)
    assign zf = (y == 32'd0);
    assign sf = y[31];
    assign cf = result[32]; // 进位/借位
    assign of = (op == ALU_ADD && a[31] == b[31] && y[31] != a[31]) || 
                (op == ALU_SUB && a[31] != b[31] && y[31] == b[31]); // 有符号溢出判断

endmodule