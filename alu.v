`timescale 1ns / 1ps
// alu.v - 算术逻辑单元 (升级版)
// 支持: 加减, 逻辑(AND/OR/XOR/NOR), 移位(SLL/SRL/SRA), 比较(SLT/SLTU), LUI
module alu(
    input  wire [3:0]  op,    // 操作码 (来自 cpu_core 的 id_ex_alu_op)
    input  wire [31:0] a,     // 操作数 A (rs 或 shamt)
    input  wire [31:0] b,     // 操作数 B (rt 或 imm)
    output reg  [31:0] y      // 运算结果
);

    always @* begin
        case(op)
            // 算术运算
            4'h0: y = a + b;                  // ADD, ADDU, ADDI, ADDIU, Load/Store地址计算
            4'h1: y = a - b;                  // SUB, SUBU, BEQ/BNE比较
            
            // 逻辑运算
            4'h2: y = a & b;                  // AND, ANDI
            4'h3: y = a | b;                  // OR, ORI
            4'h4: y = a ^ b;                  // XOR, XORI
            4'hA: y = ~(a | b);               // NOR [新增]
            
            // 比较运算
            4'h5: y = ($signed(a) < $signed(b)) ? 32'h1 : 32'h0; // SLT, SLTI (有符号)
            4'hB: y = (a < b) ? 32'h1 : 32'h0;                    // SLTU, SLTIU (无符号) [新增]

            // 移位运算 (注意：移位数取 a 的低5位)
            4'h6: y = b << a[4:0];            // SLL, SLLV
            4'h7: y = b >> a[4:0];            // SRL, SRLV
            4'h8: y = $signed(b) >>> a[4:0];  // SRA, SRAV
            
            // 其他
            4'h9: y = {b[15:0], 16'h0};       // LUI
            
            default: y = 32'h0;
        endcase
    end

endmodule

