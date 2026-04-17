module top (
    output led
);

wire clk;

SB_HFOSC osc (
    .CLKHFPU(1'b1),
    .CLKHFEN(1'b1),
    .CLKHF(clk)
);

reg [23:0] counter = 0;

always @(posedge clk) begin
    counter <= counter + 1;
end

assign led = counter[23];

endmodule
