`timescale 1ns / 1ps
module mmio_if(
    input  wire        clk,
    input  wire        rst,
    input  wire        we,
    input  wire [3:0]  be,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    input  wire [23:0] switches,
    output reg  [23:0] led_out,
    output reg  [7:0]  seg_out,
    output reg  [7:0]  an_out,
    input  wire [3:0]  col,
    output wire [3:0]  row,
    output reg         pwm_out,
    output reg         beep_out,    // 确保有这个端口
    output reg         wdg_rst_req,
    output wire [1:0]  timer_int
);
    // 地址定义
    localparam ADDR_SEG_L   = 16'hFC00;
    localparam ADDR_SEG_H   = 16'hFC02;
    localparam ADDR_KEY_VAL = 16'hFC10;
    localparam ADDR_KEY_ST  = 16'hFC12;
    localparam ADDR_T0_MODE = 16'hFC20;
    localparam ADDR_T1_MODE = 16'hFC22;
    localparam ADDR_T0_VAL  = 16'hFC24;
    localparam ADDR_T1_VAL  = 16'hFC26;
    localparam ADDR_PWM_MAX = 16'hFC30;
    localparam ADDR_PWM_CMP = 16'hFC32;
    localparam ADDR_PWM_CTL = 16'hFC34;
    localparam ADDR_WDG     = 16'hFC50;
    localparam ADDR_LED     = 16'hFC60;
    localparam ADDR_SWITCH  = 16'hFC70;
    localparam ADDR_BEEP    = 16'hFD10; // 确保有这个地址

    reg [31:0] disp_data_reg;
    reg [15:0] t0_mode, t1_mode;
    reg [15:0] t0_init, t1_init;
    reg [15:0] t0_curr, t1_curr;
    reg t0_flag, t1_flag;
    reg [15:0] pwm_max, pwm_cmp;
    reg pwm_en;
    reg [15:0] pwm_cnt;
    reg [31:0] wdg_cnt;
    reg wdg_en;
    reg [15:0] beep_reg; // 蜂鸣器寄存器

    wire [3:0] key_val;
    wire key_pressed;
    
    keyboard u_kbd(.clk(clk), .rst(rst), .col(col), .row(row), .key_out(key_val), .pressed(key_pressed));

    wire [15:0] addr_low = addr[15:0];

    // 读操作
    always @* begin
        rdata = 32'h0;
        case (addr_low)
            ADDR_SWITCH:  rdata = {8'b0, switches};
            ADDR_LED:     rdata = {8'b0, led_out};
            ADDR_KEY_VAL: rdata = {28'b0, key_val};
            ADDR_KEY_ST:  rdata = {31'b0, key_pressed};
            ADDR_T0_MODE: rdata = {15'b0, t0_flag};
            ADDR_T1_MODE: rdata = {15'b0, t1_flag};
            ADDR_T0_VAL:  rdata = {16'b0, t0_curr};
            ADDR_T1_VAL:  rdata = {16'b0, t1_curr};
            ADDR_SEG_L:   rdata = disp_data_reg;
            ADDR_BEEP:    rdata = {16'b0, beep_reg};
            default:      rdata = 32'h0;
        endcase
    end

    // 写操作
    always @(posedge clk) begin
        if (rst) begin
            led_out <= 0;
            disp_data_reg <= 0;
            t0_mode <= 0; t1_mode <= 0;
            t0_init <= 0; t1_init <= 0;
            pwm_max <= 16'hFFFF;
            pwm_cmp <= 16'h7FFF; pwm_en <= 0;
            wdg_en <= 0; wdg_rst_req <= 0;
            beep_reg <= 0; beep_out <= 0;
        end else begin
            wdg_rst_req <= (wdg_cnt == 0 && wdg_en);
            if (t0_flag && addr_low == ADDR_T0_MODE && !we) t0_flag <= 0;
            if (t1_flag && addr_low == ADDR_T1_MODE && !we) t1_flag <= 0;

            if (we) begin
                case (addr_low)
                    ADDR_LED: led_out <= wdata[23:0];
                    ADDR_SEG_L: begin
                        if(be[0]) disp_data_reg[7:0]   <= wdata[7:0];
                        if(be[1]) disp_data_reg[15:8]  <= wdata[15:8];
                    end
                    ADDR_SEG_H: disp_data_reg[31:16] <= wdata[15:0];
                    ADDR_T0_MODE: t0_mode <= wdata[15:0];
                    ADDR_T1_MODE: t1_mode <= wdata[15:0];
                    ADDR_T0_VAL:  begin t0_init <= wdata[15:0]; t0_curr <= wdata[15:0]; t0_flag <= 0; end
                    ADDR_T1_VAL:  begin t1_init <= wdata[15:0]; t1_curr <= wdata[15:0]; t1_flag <= 0; end
                    ADDR_PWM_MAX: pwm_max <= wdata[15:0];
                    ADDR_PWM_CMP: pwm_cmp <= wdata[15:0];
                    ADDR_PWM_CTL: pwm_en  <= wdata[0];
                    ADDR_WDG:     begin wdg_cnt <= 32'hFFFFFFFF; wdg_en <= 1; end
                    ADDR_BEEP:    beep_reg <= wdata[15:0];
                endcase
            end
            
            // 蜂鸣器驱动
            beep_out <= |beep_reg;

            // 定时器
            if (t0_curr > 0) t0_curr <= t0_curr - 1;
            else if (t0_mode[1]) begin t0_curr <= t0_init; t0_flag <= 1; end
            else t0_flag <= 1;

            if (t1_curr > 0) t1_curr <= t1_curr - 1;
            else if (t1_mode[1]) begin t1_curr <= t1_init; t1_flag <= 1; end
            
            // PWM
            if (pwm_en) begin
                if (pwm_cnt >= pwm_max) pwm_cnt <= 0;
                else pwm_cnt <= pwm_cnt + 1;
                pwm_out <= (pwm_cnt < pwm_cmp);
            end else pwm_out <= 0;

            // Watchdog
            if (wdg_en) begin
                if (wdg_cnt > 0) wdg_cnt <= wdg_cnt - 1;
            end else wdg_cnt <= 32'h05F5E100;
        end
    end
    
    assign timer_int = {t1_flag, t0_flag};
    
    // 数码管扫描
    reg [19:0] scan_cnt;
    reg [3:0]  hex_digit;
    always @(posedge clk) scan_cnt <= scan_cnt + 1;
    wire [2:0] scan_sel = scan_cnt[16:14];

    function [7:0] seg_decode;
        input [3:0] val;
        case (val)
            4'h0: seg_decode = 8'b1100_0000;
            4'h1: seg_decode = 8'b1111_1001;
            4'h2: seg_decode = 8'b1010_0100;
            4'h3: seg_decode = 8'b1011_0000;
            4'h4: seg_decode = 8'b1001_1001;
            4'h5: seg_decode = 8'b1001_0010;
            4'h6: seg_decode = 8'b1000_0010;
            4'h7: seg_decode = 8'b1111_1000;
            4'h8: seg_decode = 8'b1000_0000;
            4'h9: seg_decode = 8'b1001_0000;
            4'hA: seg_decode = 8'b1000_1000;
            4'hB: seg_decode = 8'b1000_0011;
            4'hC: seg_decode = 8'b1100_0110;
            4'hD: seg_decode = 8'b1010_0001;
            4'hE: seg_decode = 8'b1000_0110;
            4'hF: seg_decode = 8'b1000_1110;
            default: seg_decode = 8'b1111_1111;
        endcase
    endfunction

    always @* begin
        an_out = 8'b1111_1111;
        an_out[scan_sel] = 0; 
        case (scan_sel)
            3'd0: hex_digit = disp_data_reg[3:0];
            3'd1: hex_digit = disp_data_reg[7:4];
            3'd2: hex_digit = disp_data_reg[11:8];
            3'd3: hex_digit = disp_data_reg[15:12];
            3'd4: hex_digit = disp_data_reg[19:16];
            3'd5: hex_digit = disp_data_reg[23:20];
            3'd6: hex_digit = disp_data_reg[27:24];
            3'd7: hex_digit = disp_data_reg[31:28];
        endcase
        seg_out = seg_decode(hex_digit);
    end
endmodule