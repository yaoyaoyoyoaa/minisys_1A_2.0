# bios.s - MiniSys-1A 启动引导与自检程序
# 布局说明：
# 0x0000: 复位入口 -> 跳转到初始化
# 0x0008: 异常入口 -> 跳转到异常处理函数

.text
__RESET_ENTRY:
    J   __BIOS_INIT         # 0x0000: 复位后第一条指令
    NOP                     # 0x0004: 延迟槽

__EXCEPTION_VECTOR:
    J   __ISR_HANDLER       # 0x0008: 硬件异常/中断入口
    NOP                     # 0x000C: 延迟槽

__BIOS_INIT:
    # 1. 设定堆栈指针 (根据讲义 P122，向上生长)
    # 假设 RAM 起始于 0x00002000，我们将栈初始化在 0x7000
    LUI $sp, 0x0000
    ORI $sp, $sp, 0x7000
    MOVE $30, $sp           # 初始化 TOP 指针 ($30) 等于 SP

    # 2. 算术与逻辑自检 (保留你原有的测试)
    LI $t0, 1
    LI $t1, 2
    ADD $t2, $t0, $t1       # t2 = 3
    SUB $t3, $t2, $t1       # t3 = 1
    AND $t4, $t2, $t1       # t4 = 2
    OR  $t5, $t2, $t1       # t5 = 3
    XOR $t6, $t2, $t1       # t6 = 1

    # 3. 子字访存测试 (针对你修改的 SB/LB 逻辑)
    LI $s0, 0x12345678
    SW $s0, 0($sp)          # 先存一个字
    LI $s1, 0xAA
    SB $s1, 1($sp)          # 在偏移1处存一个字节: 内存应变为 0x1234AA78
    LB $s2, 1($sp)          # 读回该字节，s2 应为 0xFFFFFFAA (符号扩展)
    LBU $s3, 1($sp)         # 读回该字节，s3 应为 0x000000AA (零扩展)

    # 4. 中断控制测试 (针对 CP0 寄存器)
    LI $t0, 0x00000001
    MTC0 $t0, 12            # 设置 Status 寄存器，使能全局中断
    
    # 5. 跳转到用户程序 (通常由链接器决定 USER_ENTRY 地址)
    J   MAIN                # 跳转到 MiniC 编译出来的 main 函数
    NOP

# --- 异常处理程序 ---
__ISR_HANDLER:
    # 简单的异常返回逻辑
    # 在实际系统中，这里会读取 Cause 寄存器并访问串口打印错误
    MFC0 $k0, 14            # 读取 EPC (异常返回地址)
    ADDI $k0, $k0, 4        # 跳过触发异常的那条指令（简单处理）
    MTC0 $k0, 14
    ERET                    # 异常返回指令 (0x42000018)

# --- 用户程序占位 ---
MAIN:
    # 如果没有链接用户程序，则在此死循环
    J MAIN
    NOP