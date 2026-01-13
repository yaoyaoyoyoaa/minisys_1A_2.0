`timescale 1ns / 1ps

module cpu_core(
    input  wire        clk,
    input  wire        rst,
    input  wire [5:0]  ext_int,      // 外部中断输入
    // 指令存储器接口
    input  wire [31:0] imem_rdata,
    output wire [31:0] imem_addr,
    // 数据存储器接口
    input  wire [31:0] dmem_rdata,
    output wire        dmem_we,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_wstrb,
    // 调试
    output wire [31:0] dbg_pc
);
    // =========================================================================
    // 1. 流水线寄存器与连线定义
    // =========================================================================
    reg [31:0] pc;
    wire [31:0] next_pc;
    wire stall, flush;

    // --- IF/ID 寄存器 ---
    reg [31:0] if_id_pc, if_id_instr;
    // --- ID/EX 寄存器 ---
    reg [31:0] id_ex_pc, id_ex_rs_val, id_ex_rt_val, id_ex_imm;
    reg [4:0]  id_ex_rs, id_ex_rt, id_ex_rd, id_ex_shamt;
    reg [5:0]  id_ex_op, id_ex_fn;
    // ID/EX 控制信号
    reg        id_ex_reg_write, id_ex_mem_to_reg, id_ex_mem_read, id_ex_mem_write;
    reg        id_ex_alu_src, id_ex_reg_dest, id_ex_is_shift;
    reg [3:0]  id_ex_alu_op;
    reg        id_ex_is_mtc0; 
    reg        id_ex_shift_var;
    reg        id_ex_is_link;
    // 异常控制信号
    reg        id_ex_is_syscall, id_ex_is_break;
    reg        id_ex_is_eret; // [新增]
    // HILO 相关
    reg [2:0]  id_ex_hilo_op;
    reg [1:0]  id_ex_hilo_read;

    // --- EX/MEM 寄存器 ---
    reg [31:0] ex_mem_pc, ex_mem_alu_res, ex_mem_wdata;
    reg [4:0]  ex_mem_dst_reg;
    reg [5:0]  ex_mem_op; 
    reg        ex_mem_reg_write, ex_mem_mem_to_reg, ex_mem_mem_read, ex_mem_mem_write;
    reg        ex_mem_is_mtc0;
    reg        ex_mem_is_link;
    reg        ex_mem_is_syscall, ex_mem_is_break, ex_mem_is_eret; // [新增 eret]

    // --- MEM/WB 寄存器 ---
    reg [31:0] mem_wb_pc, mem_wb_read_data, mem_wb_alu_res;
    reg [4:0]  mem_wb_dst_reg;
    reg        mem_wb_reg_write, mem_wb_mem_to_reg;
    reg [5:0]  mem_wb_op;
    reg        mem_wb_is_link;

    // =========================================================================
    // 2. IF Stage (取指)
    // =========================================================================
    assign imem_addr = pc;
    assign dbg_pc = pc;

    wire        branch_taken;
    wire [31:0] branch_target;
    wire        jump_taken;
    wire [31:0] jump_target;
    
    wire [31:0] cp0_epc;
    wire        mem_exc_occurred; // 异常发生标志
    wire        wb_is_eret;       // 写回级的ERET信号(或MEM级处理)
    
    // PC 跳转逻辑
    // 优先级: ERET > Exception > Branch > Jump > PC+4
    // 注意：ERET 通常跳转到 EPC，Exception 跳转到入口地址 (0x00000008 或 0x380)
    // 这里我们使用 MEM 级的 ex_mem_is_eret 信号来判断
    assign next_pc = (ex_mem_is_eret) ? cp0_epc : 
                     (mem_exc_occurred) ? 32'h00000008 : 
                     (branch_taken) ? branch_target :
                     (jump_taken)   ? jump_target : 
                     pc + 4;

    always @(posedge clk) begin
        if (rst) pc <= 32'h00000000;
        else if (!stall) pc <= next_pc;
    end

    always @(posedge clk) begin
        if (rst) begin
            if_id_pc <= 0;
            if_id_instr <= 0;
        end else if (!stall) begin
            // 遇到跳转、异常或 ERET 时，清空流水线取指
            if (flush || mem_exc_occurred || ex_mem_is_eret) begin
                if_id_pc <= 0;
                if_id_instr <= 0;
            end else begin
                if_id_pc <= pc + 4;
                if_id_instr <= imem_rdata;
            end
        end
    end

    // =========================================================================
    // 3. ID Stage (译码 & 控制单元)
    // =========================================================================
    wire [5:0] id_op = if_id_instr[31:26];
    wire [4:0] id_rs = if_id_instr[25:21];
    wire [4:0] id_rt = if_id_instr[20:16];
    wire [4:0] id_rd = if_id_instr[15:11];
    wire [4:0] id_shamt = if_id_instr[10:6];
    wire [5:0] id_fn = if_id_instr[5:0];
    wire [15:0] id_imm = if_id_instr[15:0];
    wire [25:0] id_jump_idx = if_id_instr[25:0];

    // --- 控制信号 ---
    reg       ctrl_reg_write, ctrl_mem_to_reg, ctrl_mem_read, ctrl_mem_write;
    reg       ctrl_alu_src, ctrl_reg_dest, ctrl_branch, ctrl_jump;
    reg       ctrl_is_shift, ctrl_is_mtc0;
    reg [3:0] ctrl_alu_op;
    reg       ctrl_imm_zero, ctrl_shift_var, ctrl_is_link;   
    
    // 异常与特殊指令
    reg       ctrl_is_syscall, ctrl_is_break, ctrl_is_eret;
    reg [2:0] ctrl_hilo_op; // 0=None, 1=MULT...
    reg [1:0] ctrl_hilo_read;

    always @* begin
        ctrl_reg_write = 0; ctrl_mem_to_reg = 0; ctrl_mem_read = 0; ctrl_mem_write = 0;
        ctrl_alu_src = 0; ctrl_reg_dest = 0; ctrl_branch = 0; ctrl_jump = 0;
        ctrl_is_shift = 0; ctrl_alu_op = 4'h0; ctrl_is_mtc0 = 0;
        ctrl_imm_zero = 0; ctrl_shift_var = 0; ctrl_is_link = 0;
        ctrl_hilo_op = 3'd0; ctrl_hilo_read = 2'd0;
        ctrl_is_syscall = 0; ctrl_is_break = 0; ctrl_is_eret = 0;

        case(id_op)
            6'h00: begin // R-Type
                if (id_fn == 6'h0C) ctrl_is_syscall = 1;
                else if (id_fn == 6'h0D) ctrl_is_break = 1;
                else if (id_fn != 6'h00 || id_rd != 0 || id_rt != 0) begin
                    ctrl_reg_dest = 1; ctrl_reg_write = 1;
                    case(id_fn)
                        6'h20, 6'h21: ctrl_alu_op = 4'h0; // ADD/U
                        6'h22, 6'h23: ctrl_alu_op = 4'h1; // SUB/U
                        6'h24: ctrl_alu_op = 4'h2; // AND
                        6'h25: ctrl_alu_op = 4'h3; // OR
                        6'h26: ctrl_alu_op = 4'h4; // XOR
                        6'h27: ctrl_alu_op = 4'hA; // NOR
                        6'h2A: ctrl_alu_op = 4'h5; // SLT
                        6'h2B: ctrl_alu_op = 4'hB; // SLTU
                        6'h00: begin ctrl_alu_op = 4'h6; ctrl_is_shift = 1; end // SLL
                        6'h02: begin ctrl_alu_op = 4'h7; ctrl_is_shift = 1; end // SRL
                        6'h03: begin ctrl_alu_op = 4'h8; ctrl_is_shift = 1; end // SRA
                        6'h04: begin ctrl_alu_op = 4'h6; ctrl_is_shift = 1; ctrl_shift_var = 1; end // SLLV
                        6'h06: begin ctrl_alu_op = 4'h7; ctrl_is_shift = 1; ctrl_shift_var = 1; end // SRLV
                        6'h07: begin ctrl_alu_op = 4'h8; ctrl_is_shift = 1; ctrl_shift_var = 1; end // SRAV
                        6'h08: begin ctrl_jump = 1; ctrl_reg_write = 0; end // JR
                        6'h09: begin ctrl_jump = 1; ctrl_is_link = 1; ctrl_reg_dest = 1; ctrl_reg_write = 1; end // JALR
                        // HILO
                        6'h18: begin ctrl_hilo_op = 3'd1; ctrl_reg_write = 0; end // MULT
                        6'h19: begin ctrl_hilo_op = 3'd2; ctrl_reg_write = 0; end // MULTU
                        6'h1A: begin ctrl_hilo_op = 3'd3; ctrl_reg_write = 0; end // DIV
                        6'h1B: begin ctrl_hilo_op = 3'd4; ctrl_reg_write = 0; end // DIVU
                        6'h10: begin ctrl_hilo_read = 2'd1; ctrl_reg_write = 1; ctrl_reg_dest = 1; end // MFHI
                        6'h12: begin ctrl_hilo_read = 2'd2; ctrl_reg_write = 1; ctrl_reg_dest = 1; end // MFLO
                        6'h11: begin ctrl_hilo_op = 3'd5; ctrl_reg_write = 0; end // MTHI
                        6'h13: begin ctrl_hilo_op = 3'd6; ctrl_reg_write = 0; end // MTLO
                        default: ctrl_reg_write = 0;
                    endcase
                end
            end
            // I-Type & J-Type & System
            6'h08, 6'h09: begin ctrl_alu_src = 1; ctrl_reg_write = 1; ctrl_alu_op = 4'h0; end // ADDI/U
            6'h0A: begin ctrl_alu_src = 1; ctrl_reg_write = 1; ctrl_alu_op = 4'h5; end // SLTI
            6'h0B: begin ctrl_alu_src = 1; ctrl_reg_write = 1; ctrl_alu_op = 4'hB; end // SLTIU
            6'h0C: begin ctrl_alu_src = 1; ctrl_reg_write = 1; ctrl_alu_op = 4'h2; ctrl_imm_zero = 1; end // ANDI
            6'h0D: begin ctrl_alu_src = 1; ctrl_reg_write = 1; ctrl_alu_op = 4'h3; ctrl_imm_zero = 1; end // ORI
            6'h0E: begin ctrl_alu_src = 1; ctrl_reg_write = 1; ctrl_alu_op = 4'h4; ctrl_imm_zero = 1; end // XORI
            6'h0F: begin ctrl_alu_src = 1; ctrl_reg_write = 1; ctrl_alu_op = 4'h9; end // LUI
            6'h20, 6'h21, 6'h23, 6'h24, 6'h25: begin ctrl_alu_src = 1; ctrl_mem_to_reg = 1; ctrl_reg_write = 1; ctrl_mem_read = 1; ctrl_alu_op = 4'h0; end // Load
            6'h28, 6'h29, 6'h2B: begin ctrl_alu_src = 1; ctrl_mem_write = 1; ctrl_alu_op = 4'h0; end // Store
            6'h04, 6'h05: begin ctrl_branch = 1; ctrl_alu_op = 4'h1; end // BEQ, BNE
            6'h06, 6'h07: ctrl_branch = 1; // BLEZ, BGTZ
            6'h01: begin ctrl_branch = 1; if(id_rt==16||id_rt==17) begin ctrl_is_link = 1; ctrl_reg_write = 1; ctrl_reg_dest = 0; end end // BGEZ/BLTZ/AL
            6'h02: ctrl_jump = 1; // J
            6'h03: begin ctrl_jump = 1; ctrl_is_link = 1; ctrl_reg_write = 1; end // JAL
            6'h10: begin // COP0
                if (if_id_instr[25:21] == 5'h04) ctrl_is_mtc0 = 1; // MTC0
                else if (if_id_instr[25:21] == 5'h00) ctrl_reg_write = 1; // MFC0
                else if (if_id_instr[25:0] == 26'b10000000000000000000011000) ctrl_is_eret = 1; // ERET (CO=1, FN=0x18)
            end
        endcase
    end

    // ... (Regfile & Branch logic 保持不变) ...
    // ...
    wire [31:0] reg_rdata1, reg_rdata2;
    wire [31:0] wb_wdata;
    wire [4:0]  final_wb_dst = mem_wb_is_link ? 5'd31 : mem_wb_dst_reg;
    regfile u_regfile(
        .clk(clk), .rst(rst),
        .raddr1(id_rs), .raddr2(id_rt),
        .rdata1(reg_rdata1), .rdata2(reg_rdata2),
        .we(mem_wb_reg_write), 
        .waddr(final_wb_dst), 
        .wdata(wb_wdata)
    );
    // ... (Branch 比较逻辑) ...
    // 请保留您原有的 Branch 判断逻辑 (is_bgez, is_bltz, branch_taken etc.)
    wire [31:0] branch_op_a = (ex_mem_reg_write && ex_mem_dst_reg != 0 && ex_mem_dst_reg == id_rs) ? ex_mem_alu_res : (mem_wb_reg_write && mem_wb_dst_reg != 0 && mem_wb_dst_reg == id_rs) ? wb_wdata : reg_rdata1;
    wire [31:0] branch_op_b = (ex_mem_reg_write && ex_mem_dst_reg != 0 && ex_mem_dst_reg == id_rt) ? ex_mem_alu_res : (mem_wb_reg_write && mem_wb_dst_reg != 0 && mem_wb_dst_reg == id_rt) ? wb_wdata : reg_rdata2;
    wire signed [31:0] rs_val_s = branch_op_a;
    assign branch_taken = ctrl_branch && (
        (id_op == 6'h04 && branch_op_a == branch_op_b) || 
        (id_op == 6'h05 && branch_op_a != branch_op_b) || 
        (id_op == 6'h06 && rs_val_s <= 0) ||              
        (id_op == 6'h07 && rs_val_s >  0) ||              
        ((id_op == 6'h01 && (id_rt==1||id_rt==17)) && rs_val_s >= 0) || 
        ((id_op == 6'h01 && (id_rt==0||id_rt==16)) && rs_val_s <  0)
    );
    
    // ... (Imm Gen & Stall Logic) ...
    wire [31:0] sign_ext_imm = {{16{id_imm[15]}}, id_imm};
    wire [31:0] zero_ext_imm = {16'b0, id_imm};
    wire [31:0] final_imm    = ctrl_imm_zero ? zero_ext_imm : sign_ext_imm;
    assign branch_target = if_id_pc + (sign_ext_imm << 2);
    assign jump_target   = {if_id_pc[31:28], id_jump_idx, 2'b00};
    wire is_jr_type = (id_op == 6'h00 && (id_fn == 6'h08 || id_fn == 6'h09));
    assign jump_taken = (ctrl_jump && (id_op == 6'h02 || id_op == 6'h03 || is_jr_type));
    assign stall = id_ex_mem_read && (id_ex_rt == id_rs || id_ex_rt == id_rt);
    assign flush = branch_taken || jump_taken || ex_mem_is_eret; // ERET 也要 flush

    // --- ID/EX 流水线 ---
    always @(posedge clk) begin
        if (rst || flush || stall || mem_exc_occurred) begin // Exception flush
            id_ex_pc <= 0;
            id_ex_reg_write <= 0; id_ex_mem_write <= 0; id_ex_mem_read <= 0;
            id_ex_op <= 0; id_ex_fn <= 0; id_ex_is_link <= 0;
            id_ex_hilo_op <= 0; id_ex_hilo_read <= 0;
            id_ex_is_syscall <= 0; id_ex_is_break <= 0; id_ex_is_eret <= 0;
        end else begin
            id_ex_pc <= if_id_pc;
            id_ex_rs_val <= reg_rdata1;
            id_ex_rt_val <= reg_rdata2;
            id_ex_imm    <= final_imm;
            id_ex_rs     <= id_rs;
            id_ex_rt     <= id_rt;
            id_ex_rd     <= id_rd;
            id_ex_shamt  <= id_shamt;
            id_ex_op     <= id_op;
            id_ex_fn     <= id_fn;
            
            id_ex_reg_write <= ctrl_reg_write;
            id_ex_mem_to_reg<= ctrl_mem_to_reg;
            id_ex_mem_read  <= ctrl_mem_read;
            id_ex_mem_write <= ctrl_mem_write;
            id_ex_alu_src   <= ctrl_alu_src;
            id_ex_reg_dest  <= ctrl_reg_dest;
            id_ex_alu_op    <= ctrl_alu_op;
            id_ex_is_shift  <= ctrl_is_shift;
            id_ex_is_mtc0   <= ctrl_is_mtc0;
            id_ex_shift_var <= ctrl_shift_var;
            id_ex_is_link   <= ctrl_is_link;
            
            id_ex_hilo_op   <= ctrl_hilo_op;
            id_ex_hilo_read <= ctrl_hilo_read;
            
            id_ex_is_syscall <= ctrl_is_syscall;
            id_ex_is_break   <= ctrl_is_break;
            id_ex_is_eret    <= ctrl_is_eret;
        end
    end

    // =========================================================================
    // 4. EX Stage (执行 & 前递 & HILO)
    // =========================================================================
    // ... (FWD Logic 保持不变) ...
    reg [1:0] fwd_a, fwd_b;
    always @* begin
        fwd_a = 0; fwd_b = 0;
        if (ex_mem_reg_write && ex_mem_dst_reg != 0 && ex_mem_dst_reg == id_ex_rs) fwd_a = 2'b10;
        if (ex_mem_reg_write && ex_mem_dst_reg != 0 && ex_mem_dst_reg == id_ex_rt) fwd_b = 2'b10;
        if (mem_wb_reg_write && mem_wb_dst_reg != 0 && mem_wb_dst_reg == id_ex_rs && fwd_a == 0) fwd_a = 2'b01;
        if (mem_wb_reg_write && mem_wb_dst_reg != 0 && mem_wb_dst_reg == id_ex_rt && fwd_b == 0) fwd_b = 2'b01;
    end
    wire [31:0] alu_src_a_fwd = (fwd_a == 2'b10) ? ex_mem_alu_res : (fwd_a == 2'b01) ? wb_wdata : id_ex_rs_val;
    wire [31:0] alu_src_b_fwd = (fwd_b == 2'b10) ? ex_mem_alu_res : (fwd_b == 2'b01) ? wb_wdata : id_ex_rt_val;
    wire [31:0] shift_amt = id_ex_shift_var ? alu_src_a_fwd : {27'b0, id_ex_shamt};
    wire [31:0] alu_src_a = id_ex_is_shift ? shift_amt : alu_src_a_fwd;
    wire [31:0] alu_src_b = id_ex_alu_src  ? id_ex_imm : alu_src_b_fwd;

    wire [31:0] alu_result;
    alu u_alu(.op(id_ex_alu_op), .a(alu_src_a), .b(alu_src_b), .y(alu_result));

    wire [31:0] hi_val, lo_val;
    hilo_reg u_hilo (
        .clk(clk), .rst(rst),
        .op(id_ex_hilo_op), .a(alu_src_a_fwd), .b(alu_src_b_fwd),
        .hi_o(hi_val), .lo_o(lo_val)
    );
    wire [31:0] final_ex_result = (id_ex_hilo_read == 2'd1) ? hi_val : (id_ex_hilo_read == 2'd2) ? lo_val : alu_result;
    wire [4:0] dst_reg = id_ex_reg_dest ? id_ex_rd : id_ex_rt;

    always @(posedge clk) begin
        if (rst || mem_exc_occurred) begin
            ex_mem_reg_write <= 0; ex_mem_mem_write <= 0; ex_mem_is_mtc0 <= 0; ex_mem_is_link <= 0;
            ex_mem_is_syscall <= 0; ex_mem_is_break <= 0; ex_mem_is_eret <= 0;
        end else begin
            ex_mem_pc        <= id_ex_pc;
            ex_mem_alu_res   <= final_ex_result; 
            ex_mem_wdata     <= alu_src_b_fwd;
            ex_mem_dst_reg   <= dst_reg;
            ex_mem_op        <= id_ex_op;
            ex_mem_reg_write <= id_ex_reg_write;
            ex_mem_mem_to_reg<= id_ex_mem_to_reg;
            ex_mem_mem_read  <= id_ex_mem_read;
            ex_mem_mem_write <= id_ex_mem_write;
            ex_mem_is_mtc0   <= id_ex_is_mtc0;
            ex_mem_is_link   <= id_ex_is_link;
            
            ex_mem_is_syscall <= id_ex_is_syscall;
            ex_mem_is_break   <= id_ex_is_break;
            ex_mem_is_eret    <= id_ex_is_eret;
        end
    end

    // =========================================================================
    // 5. MEM Stage
    // =========================================================================
    assign dmem_addr = ex_mem_alu_res;
    
    // [关键修改] 异常/中断检测
    wire irq_req; // 来自 CP0 的最终中断请求 (屏蔽后)
    
    // 触发异常条件: 有 IRQ 请求 OR Syscall OR Break
    assign mem_exc_occurred = (irq_req) || ex_mem_is_syscall || ex_mem_is_break;
    
    // 异常类型码 (ExcCode)
    // Int=0, Syscall=8, Break=9
    wire [4:0] exc_code = (irq_req)           ? 5'd0 :
                          (ex_mem_is_syscall) ? 5'd8 :
                          (ex_mem_is_break)   ? 5'd9 : 5'd0;

    assign dmem_we = ex_mem_mem_write && !mem_exc_occurred;

    reg [31:0] aligned_wdata;
    reg [3:0]  aligned_wstrb;
    always @* begin
        aligned_wdata = ex_mem_wdata;
        aligned_wstrb = 4'b1111;
        case(ex_mem_op)
            6'h28: begin // SB
                case(ex_mem_alu_res[1:0])
                    2'b00: aligned_wstrb = 4'b0001;
                    2'b01: aligned_wstrb = 4'b0010;
                    2'b10: aligned_wstrb = 4'b0100;
                    2'b11: aligned_wstrb = 4'b1000;
                endcase
                aligned_wdata = {4{ex_mem_wdata[7:0]}};
            end
            6'h29: begin // SH
                if (ex_mem_alu_res[1] == 0) aligned_wstrb = 4'b0011;
                else                        aligned_wstrb = 4'b1100;
                aligned_wdata = {2{ex_mem_wdata[15:0]}};
            end
        endcase
    end
    assign dmem_wdata = aligned_wdata;
    assign dmem_wstrb = aligned_wstrb;

    wire [31:0] cp0_data_out;
    cp0_regfile u_cp0 (
        .clk(clk), .rst(rst),
        .we(ex_mem_is_mtc0), 
        .addr(ex_mem_dst_reg), 
        .din(ex_mem_wdata),    
        .ext_int(ext_int),
        .exception_i(mem_exc_occurred),
        .epc_i(ex_mem_pc),
        .cause_type(exc_code),
        .data_o(cp0_data_out),
        .epc_o(cp0_epc),
        .irq_o(irq_req) // [连接] 接收 CP0 判断后的中断请求
    );

    wire [31:0] mem_result_mux = (ex_mem_op == 6'h10) ? cp0_data_out : dmem_rdata;

    // =========================================================================
    // 6. WB Stage
    // =========================================================================
    always @(posedge clk) begin
        if (rst || mem_exc_occurred) begin
            mem_wb_reg_write <= 0;
        end else begin
            mem_wb_pc         <= ex_mem_pc;
            mem_wb_read_data  <= mem_result_mux;
            mem_wb_alu_res    <= ex_mem_alu_res;
            mem_wb_dst_reg    <= ex_mem_dst_reg;
            mem_wb_op         <= ex_mem_op;
            mem_wb_reg_write  <= ex_mem_reg_write;
            mem_wb_mem_to_reg <= ex_mem_mem_to_reg;
            mem_wb_is_link    <= ex_mem_is_link;
        end
    end

    reg [31:0] final_wb_data;
    always @* begin
        if (mem_wb_is_link) begin
            final_wb_data = mem_wb_pc + 4; // PC+8 is computed here as PC_IF + 4? No, Link is PC+8.
            // if_id_pc is PC+4. So id_ex_pc is address of instruction. 
            // Standard JAL saves PC+8. ex_mem_pc is `id_ex_pc`. 
            // So we need ex_mem_pc + 8.
            // Note: In my code above `mem_wb_pc` holds address of current inst.
            // So link address should be `mem_wb_pc + 8`.
            // Wait, Standard JALR saves PC+4? No, PC+8 usually.
            // Let's stick to PC+8 for consistency with MIPS.
            final_wb_data = mem_wb_pc + 8; 
        end else if (mem_wb_mem_to_reg) begin
            case(mem_wb_op)
                6'h20: begin // LB
                    case(mem_wb_alu_res[1:0])
                        2'b00: final_wb_data = {{24{mem_wb_read_data[7]}},  mem_wb_read_data[7:0]};
                        2'b01: final_wb_data = {{24{mem_wb_read_data[15]}}, mem_wb_read_data[15:8]};
                        2'b10: final_wb_data = {{24{mem_wb_read_data[23]}}, mem_wb_read_data[23:16]};
                        2'b11: final_wb_data = {{24{mem_wb_read_data[31]}}, mem_wb_read_data[31:24]};
                    endcase
                end
                6'h24: begin // LBU
                    case(mem_wb_alu_res[1:0])
                        2'b00: final_wb_data = {24'b0, mem_wb_read_data[7:0]};
                        2'b01: final_wb_data = {24'b0, mem_wb_read_data[15:8]};
                        2'b10: final_wb_data = {24'b0, mem_wb_read_data[23:16]};
                        2'b11: final_wb_data = {24'b0, mem_wb_read_data[31:24]};
                    endcase
                end
                6'h21: begin // LH
                    if (mem_wb_alu_res[1] == 0) final_wb_data = {{16{mem_wb_read_data[15]}}, mem_wb_read_data[15:0]};
                    else                        final_wb_data = {{16{mem_wb_read_data[31]}}, mem_wb_read_data[31:16]};
                end
                6'h25: begin // LHU
                    if (mem_wb_alu_res[1] == 0) final_wb_data = {16'b0, mem_wb_read_data[15:0]};
                    else                        final_wb_data = {16'b0, mem_wb_read_data[31:16]};
                end
                default: final_wb_data = mem_wb_read_data; // LW
            endcase
        end else begin
            final_wb_data = mem_wb_alu_res;
        end
    end

    assign wb_wdata = final_wb_data;

endmodule