module led_pattern #(
    parameter CLK_HZ     = 48_000_000,
    parameter INTERVAL_MS = 200
)(
    input  wire        clk,
    input  wire [7:0]  cfgr,
    input  wire [7:0]  reg0,
    input  wire [7:0]  reg1,
    output reg  [8:0]  led   // 9 LEDs now
);

    localparam integer TICKS = (CLK_HZ / 1000) * INTERVAL_MS;

    reg [$clog2(TICKS)-1:0] tick_cnt = 0;
    reg [3:0] idx = 0;

    // S-pattern mapping (IMPORTANT)
    wire [8:0] s_map [0:8];

    assign s_map[0] = 9'b000000001;
    assign s_map[1] = 9'b000000010;
    assign s_map[2] = 9'b000000100;
    assign s_map[3] = 9'b000001000;
    assign s_map[4] = 9'b000010000;
    assign s_map[5] = 9'b000100000;
    assign s_map[6] = 9'b001000000;
    assign s_map[7] = 9'b010000000;
    assign s_map[8] = 9'b100000000;

    wire [8:0] direct = {reg1[0], reg0}; // 9 LEDs mapping

    always @(posedge clk) begin
        if (tick_cnt == TICKS-1) begin
            tick_cnt <= 0;
            idx <= (idx == 8) ? 0 : idx + 1;
        end else begin
            tick_cnt <= tick_cnt + 1;
        end

        if (cfgr[0] == 1'b0) begin
            led <= direct;          // NORMAL MODE
        end else begin
            led <= s_map[idx];      // RUNNER MODE
        end
    end

endmodule