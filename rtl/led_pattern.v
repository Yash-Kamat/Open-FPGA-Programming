// ============================================================
// led_pattern.v
// Walks through the 16 bits of {reg1, reg0} one at a time,
// displaying each bit on the LED output for TICK_HZ interval.
//
// With LEDS=1 (default): serial display — one bit shown at a time,
// cycling through all 16 positions.
// With LEDS=16: parallel display — all bits shown at once on 16 LEDs,
// no cycling needed (the "pattern" is static from the data).
// ============================================================
module led_pattern #(
    parameter CLK_HZ     = 48_000_000,  // SB_HFOSC default
    parameter INTERVAL_MS = 250,        // time per bit
    parameter LEDS        = 1
)(
    input  wire            clk,
    input  wire      [7:0] reg0,
    input  wire      [7:0] reg1,
    output wire [LEDS-1:0] led
);

    localparam integer TICKS = (CLK_HZ / 1000) * INTERVAL_MS;

    reg [$clog2(TICKS)-1:0] tick_cnt = 0;
    reg [3:0]               bit_idx  = 0;   // 0..15

    wire [15:0] data = {reg1, reg0};

    always @(posedge clk) begin
        if (tick_cnt == TICKS - 1) begin
            tick_cnt <= 0;
            bit_idx  <= bit_idx + 1;        // wraps 15 -> 0 automatically
        end else begin
            tick_cnt <= tick_cnt + 1;
        end
    end

    generate
        if (LEDS == 1) begin : serial_out
            // Show the currently-selected bit
            assign led = data[bit_idx];
        end else if (LEDS == 16) begin : parallel_out
            // Show all bits at once; bit_idx unused for display,
            // but the walker could gate it for a scanning effect.
            assign led = data;
        end else begin : windowed_out
            // Show a window of LEDS bits starting at bit_idx
            assign led = data >> bit_idx;
        end
    endgenerate

endmodule
