// Minimal bit-banged I2C slave for iCE40UP5K / VSDSquadron FM
// Address: 7-bit 0x42. Write-only (responds to i2cset).
// Captures one data byte into data_reg and drives LED from LSB.

module top_i2c_v2 (
    input  wire scl,
    inout  wire sda,
    output wire led
);

    // --- Slave address ---
    localparam [6:0] SLAVE_ADDR = 7'h42;

    // --- Internal 48 MHz clock ---
    wire clk;
    SB_HFOSC osc (
        .CLKHFPU(1'b1),
        .CLKHFEN(1'b1),
        .CLKHF(clk)
    );

    // --- SDA tri-state ---
    // In I2C, a slave only ever pulls SDA LOW (ACK). It never drives high;
    // the pull-up resistor does that. So sda_out is always 0 and we just
    // toggle the output-enable.
    reg sda_oe = 1'b0;
    assign sda = sda_oe ? 1'b0 : 1'bz;

    // --- Double-flop synchronizers for SCL and SDA ---
    reg [2:0] scl_s = 3'b111;
    reg [2:0] sda_s = 3'b111;
    always @(posedge clk) begin
        scl_s <= {scl_s[1:0], scl};
        sda_s <= {sda_s[1:0], sda};
    end

    wire scl_now     = scl_s[1];
    wire scl_prev    = scl_s[2];
    wire sda_now     = sda_s[1];
    wire sda_prev    = sda_s[2];

    wire scl_rising  = (scl_prev == 1'b0) && (scl_now == 1'b1);
    wire scl_falling = (scl_prev == 1'b1) && (scl_now == 1'b0);

    // START: SDA falls while SCL is high.
    // STOP : SDA rises while SCL is high.
    wire start_cond  = (sda_prev == 1'b1) && (sda_now == 1'b0) && scl_now;
    wire stop_cond   = (sda_prev == 1'b0) && (sda_now == 1'b1) && scl_now;

    // --- State machine ---
    localparam S_IDLE     = 3'd0,
               S_ADDR     = 3'd1,  // shifting in 7 addr bits + R/W
               S_ACK_ADDR = 3'd2,  // drive SDA low for one SCL period
               S_DATA     = 3'd3,  // shifting in 8 data bits
               S_ACK_DATA = 3'd4;  // drive SDA low for one SCL period

    reg [2:0] state    = S_IDLE;
    reg [3:0] bit_cnt  = 0;
    reg [7:0] shifter  = 0;
    reg [7:0] data_reg = 0;
    reg       addr_ok  = 0;

    always @(posedge clk) begin
        // STOP or START always resets framing
        if (stop_cond) begin
            state   <= S_IDLE;
            sda_oe  <= 1'b0;
        end else if (start_cond) begin
            state   <= S_ADDR;
            bit_cnt <= 0;
            shifter <= 0;
            sda_oe  <= 1'b0;
        end else begin
            case (state)

            S_IDLE: begin
                sda_oe <= 1'b0;
            end

            // --- Sample address+RW on each SCL rising edge ---
            S_ADDR: begin
                if (scl_rising) begin
                    shifter <= {shifter[6:0], sda_now};
                    bit_cnt <= bit_cnt + 1;
                end
                // After 8 bits have been clocked in, decide whether to ACK.
                // We act on the FALLING edge after bit 8 so that SDA is
                // stable well before the 9th SCL rising edge.
                if (scl_falling && bit_cnt == 8) begin
                    if (shifter[7:1] == SLAVE_ADDR) begin
                        sda_oe  <= 1'b1;     // pull SDA low = ACK
                        addr_ok <= 1'b1;
                        state   <= S_ACK_ADDR;
                    end else begin
                        sda_oe  <= 1'b0;     // NACK (leave Hi-Z)
                        addr_ok <= 1'b0;
                        state   <= S_IDLE;   // ignore rest of transaction
                    end
                    bit_cnt <= 0;
                end
            end

            // Hold ACK low through the 9th SCL pulse, release on its falling edge
            S_ACK_ADDR: begin
                if (scl_falling) begin
                    sda_oe  <= 1'b0;
                    shifter <= 0;
                    bit_cnt <= 0;
                    state   <= S_DATA;
                end
            end

            S_DATA: begin
                if (scl_rising) begin
                    shifter <= {shifter[6:0], sda_now};
                    bit_cnt <= bit_cnt + 1;
                end
                if (scl_falling && bit_cnt == 8) begin
                    data_reg <= shifter;     // latch the received byte
                    sda_oe   <= 1'b1;        // ACK the data byte
                    bit_cnt  <= 0;
                    state    <= S_ACK_DATA;
                end
            end

            S_ACK_DATA: begin
                if (scl_falling) begin
                    sda_oe <= 1'b0;
                    // Stay ready for another data byte, or for STOP/START
                    shifter <= 0;
                    bit_cnt <= 0;
                    state   <= S_DATA;
                end
            end

            default: state <= S_IDLE;
            endcase
        end
    end

    // --- LED drive ---
    // If pin 39 on your board is RGB0 (open-drain high-current LED),
    // you'll want SB_RGBA_DRV instead. For a plain LED on a GPIO this is fine.
    assign led = data_reg[0];

endmodule
