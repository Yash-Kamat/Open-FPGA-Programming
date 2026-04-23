module reg_file (
    input  wire       clk,

    input  wire [7:0] waddr,
    input  wire [7:0] wdata,
    input  wire       we,

    input  wire [7:0] raddr,
    output reg  [7:0] rdata,

    output wire [7:0] cfgr,
    output wire [7:0] reg0,
    output wire [7:0] reg1
);

    reg [7:0] r_cfgr = 8'h00;   // NEW
    reg [7:0] r0     = 8'h00;
    reg [7:0] r1     = 8'h00;

    always @(posedge clk) begin
        if (we) begin
            case (waddr)
                8'h00: r_cfgr <= wdata;  // CFGR
                8'h01: if (!r_cfgr[0]) r0 <= wdata; // only writable in normal mode
                8'h02: if (!r_cfgr[0]) r1 <= wdata;
                default: ;
            endcase
        end
    end

    always @(*) begin
        case (raddr)
            8'h00: rdata = r_cfgr;
            8'h01: rdata = r0;
            8'h02: rdata = r1;
            default: rdata = 8'h00;
        endcase
    end

    assign cfgr = r_cfgr;
    assign reg0 = r0;
    assign reg1 = r1;

endmodule