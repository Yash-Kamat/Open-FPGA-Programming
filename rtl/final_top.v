// ============================================================
// final_top.v
// Top-level: SB_HFOSC + I2C slave + reg file + LED pattern.
// Slave address: 0x42. Registers: 0x00 (reg0), 0x01 (reg1).
//
// Write example (from the Pi):
//   i2cset -y 1 0x42 0x00 0xAA   # load reg0 = 0xAA
//   i2cset -y 1 0x42 0x01 0x55   # load reg1 = 0x55
// Read example:
//   i2cget -y 1 0x42 0x00        # read reg0
// ============================================================
module final_top (
    input  wire scl,
    inout  wire sda,
    output wire led
);

    // 12 MHz internal oscillator (48 MHz / 4).
    // Plenty of oversampling for 100–400 kHz I2C and gives timing headroom.
    wire clk;
    SB_HFOSC #(
        .CLKHF_DIV("0b10")    // "0b00"=48, "0b01"=24, "0b10"=12, "0b11"=6 MHz
    ) osc (
        .CLKHFPU(1'b1),
        .CLKHFEN(1'b1),
        .CLKHF  (clk)
    );

    // I2C <-> reg file wires
    wire [7:0] reg_waddr;
    wire [7:0] reg_wdata;
    wire       reg_we;
    wire [7:0] reg_rdata;

    // reg file parallel outputs to the application
    wire [7:0] r0, r1;

    i2c_slave #(
        .SLAVE_ADDR(7'h42)
    ) u_i2c (
        .clk         (clk),
        .scl         (scl),
        .sda         (sda),
        .reg_addr_o  (reg_waddr),
        .reg_wdata_o (reg_wdata),
        .reg_we_o    (reg_we),
        .reg_rdata_i (reg_rdata)
    );

    // The I2C slave uses reg_addr_o for both reads and writes,
    // so we feed it back into the read port as well.
    reg_file u_regs (
        .clk   (clk),
        .waddr (reg_waddr),
        .wdata (reg_wdata),
        .we    (reg_we),
        .raddr (reg_waddr),
        .rdata (reg_rdata),
        .reg0  (r0),
        .reg1  (r1)
    );

    led_pattern #(
        .CLK_HZ     (12_000_000),
        .INTERVAL_MS(250),
        .LEDS       (1)
    ) u_leds (
        .clk  (clk),
        .reg0 (r0),
        .reg1 (r1),
        .led  (led)
    );

endmodule