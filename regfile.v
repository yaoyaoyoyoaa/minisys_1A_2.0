// regfile.v
// 修改：增加内部前递逻辑，解决 WB/ID 阶段的数据相关 (Standard Compliance)
module regfile(
  input  wire        clk,
  input  wire        rst,
  input  wire [4:0]  raddr1,
  input  wire [4:0]  raddr2,
  output reg  [31:0] rdata1, // 改为 reg 以便在 always 块中赋值
  output reg  [31:0] rdata2, // 改为 reg
  input  wire        we,
  input  wire [4:0]  waddr,
  input  wire [31:0] wdata
);
  reg [31:0] mem [0:31];

  integer i;
  always @(posedge clk) begin
    if (rst) begin
      for (i=0; i<32; i=i+1) mem[i] <= 32'd0;
    end else if (we && (waddr != 5'd0)) begin
      mem[waddr] <= wdata;
    end
  end

  // 读端口 1 (参考标准 gpr.v 实现内部前递)
  always @(*) begin
    if (raddr1 == 5'd0) begin
        rdata1 = 32'd0;
    end else if (raddr1 == waddr && we) begin
        rdata1 = wdata; // 内部前递：正在写的数据直接由读口输出
    end else begin
        rdata1 = mem[raddr1];
    end
  end

  // 读端口 2
  always @(*) begin
    if (raddr2 == 5'd0) begin
        rdata2 = 32'd0;
    end else if (raddr2 == waddr && we) begin
        rdata2 = wdata; // 内部前递
    end else begin
        rdata2 = mem[raddr2];
    end
  end

endmodule

