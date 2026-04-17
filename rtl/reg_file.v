// ============================================================
// reg_file.v
// Two 8-bit memory-mapped registers.
//   Address 0x00 -> reg0
//   Address 0x01 -> reg1
// Any other address reads back 0x00 and ignores writes.
// ============================================================
module reg_file (
    input  wire       clk,

    // Write port (from I2C slave)
    input  wire [7:0] waddr,
    input  wire [7:0] wdata,
    input  wire       we,

    // Read port (combinational, also for I2C slave)
    input  wire [7:0] raddr,
    output reg  [7:0] rdata,

    // Direct parallel outputs for the application logic
    output wire [7:0] reg0,
    output wire [7:0] reg1
);

    reg [7:0] r0 = 8'h00;
    reg [7:0] r1 = 8'h00;

    always @(posedge clk) begin
        if (we) begin
            case (waddr)
                8'h00: r0 <= wdata;
                8'h01: r1 <= wdata;
                default: ; // ignore
            endcase
        end
    end

    always @(*) begin
        case (raddr)
            8'h00:   rdata = r0;
            8'h01:   rdata = r1;
            default: rdata = 8'h00;
        endcase
    end

    assign reg0 = r0;
    assign reg1 = r1;

endmodule
