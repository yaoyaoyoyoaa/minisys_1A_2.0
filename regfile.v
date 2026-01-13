// 寄存器堆：32×32 位，端口简化，$zero 恒为 0（中文注释密集）
module regfile(
  input  wire        clk,
  input  wire        rst,
  input  wire [4:0]  raddr1,
  input  wire [4:0]  raddr2,
  output wire [31:0] rdata1,
  output wire [31:0] rdata2,
  input  wire        we,
  input  wire [4:0]  waddr,
  input  wire [31:0] wdata
);
  reg [31:0] mem [0:31];

  // 读口：异步读
  assign rdata1 = (raddr1 == 5'd0) ? 32'd0 : mem[raddr1];
  assign rdata2 = (raddr2 == 5'd0) ? 32'd0 : mem[raddr2];

  // 写口：时钟上升沿写入；$zero 不可写
  integer i;
  always @(posedge clk) begin
    if (rst) begin
      for (i=0; i<32; i=i+1) mem[i] <= 32'd0;
    end else if (we && (waddr != 5'd0)) begin
      mem[waddr] <= wdata;
    end
  end
endmodule

