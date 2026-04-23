// ============================================================
// i2c_slave.v
// Bit-banged I2C slave with a register-file-facing interface.
//
// Protocol supported:
//   Write:  START | addr|W | reg_addr | data | STOP
//           (also accepts multi-byte writes; reg_addr auto-increments)
//   Read:   START | addr|W | reg_addr | RSTART | addr|R | data | NACK | STOP
//
// Interface to register file:
//   reg_addr_o  - which register is being accessed
//   reg_wdata_o - byte to write
//   reg_we_o    - 1-cycle pulse: latch reg_wdata_o into reg_addr_o
//   reg_rdata_i - register file provides the byte to send back
// ============================================================
module i2c_slave #(
    parameter [6:0] SLAVE_ADDR = 7'h42
)(
    input  wire       clk,
    input  wire       scl,
    inout  wire       sda,

    output reg  [7:0] reg_addr_o,
    output reg  [7:0] reg_wdata_o,
    output reg        reg_we_o,
    input  wire [7:0] reg_rdata_i
);

    // --- SDA open-drain: pull low or release ---
    reg sda_oe = 1'b0;
    assign sda = sda_oe ? 1'b0 : 1'bz;

    // --- Synchronizers (3 stages so we have prev/now for edge detect) ---
    reg [2:0] scl_s = 3'b111;
    reg [2:0] sda_s = 3'b111;
    always @(posedge clk) begin
        scl_s <= {scl_s[1:0], scl};
        sda_s <= {sda_s[1:0], sda};
    end
    wire scl_now  = scl_s[1];
    wire scl_prev = scl_s[2];
    wire sda_now  = sda_s[1];
    wire sda_prev = sda_s[2];

    wire scl_rising  = (scl_prev == 1'b0) && (scl_now == 1'b1);
    wire scl_falling = (scl_prev == 1'b1) && (scl_now == 1'b0);
    wire start_cond  = (sda_prev == 1'b1) && (sda_now == 1'b0) && scl_now;
    wire stop_cond   = (sda_prev == 1'b0) && (sda_now == 1'b1) && scl_now;

    // --- State machine ---
    localparam S_IDLE      = 4'd0,
               S_ADDR      = 4'd1,  // receiving 7-bit addr + R/W
               S_ACK_ADDR  = 4'd2,  // ack the address byte
               S_REG       = 4'd3,  // receiving register pointer (write phase)
               S_ACK_REG   = 4'd4,
               S_WDATA     = 4'd5,  // receiving data byte to write
               S_ACK_WDATA = 4'd6,
               S_RDATA     = 4'd7,  // sending byte out to master
               S_ACK_RDATA = 4'd8;  // sample master's (N)ACK

    reg [3:0] state   = S_IDLE;
    reg [3:0] bit_cnt = 0;
    reg [7:0] shifter = 0;
    reg       rw_bit  = 0;      // captured from address byte: 1 = master reads
    reg       ack_got = 0;      // latched master ACK during S_ACK_RDATA

    always @(posedge clk) begin
        // default: pulse signals low
        reg_we_o <= 1'b0;

        // START/STOP are asynchronous to our state
        if (stop_cond) begin
            state  <= S_IDLE;
            sda_oe <= 1'b0;
        end else if (start_cond) begin
            // Handles both initial START and repeated START
            state   <= S_ADDR;
            bit_cnt <= 0;
            shifter <= 0;
            sda_oe  <= 1'b0;
        end else begin
            case (state)

            S_IDLE: sda_oe <= 1'b0;

            // ---- Address phase ----
            S_ADDR: begin
                if (scl_rising) begin
                    shifter <= {shifter[6:0], sda_now};
                    bit_cnt <= bit_cnt + 1;
                end
                if (scl_falling && bit_cnt == 8) begin
                    bit_cnt <= 0;
                    if (shifter[7:1] == SLAVE_ADDR) begin
                        rw_bit <= shifter[0];
                        sda_oe <= 1'b1;          // ACK
                        state  <= S_ACK_ADDR;
                    end else begin
                        sda_oe <= 1'b0;
                        state  <= S_IDLE;        // not for us
                    end
                end
            end

            S_ACK_ADDR: begin
                if (scl_falling) begin
                    bit_cnt <= 0;
                    if (rw_bit == 1'b0) begin
                        sda_oe  <= 1'b0;           // release ACK
                        shifter <= 0;
                        state   <= S_REG;          // master is writing: next byte is reg pointer
                    end else begin
                        // Master is reading. The NEXT SCL-high is the master
                        // sampling bit 7 of our response, so we MUST drive it
                        // on THIS falling edge -- not wait for the next one.
                        // Load shifter with the byte shifted left by 1 (bit 7
                        // is now on the wire; remaining bits will follow).
                        sda_oe  <= ~reg_rdata_i[7];
                        shifter <= {reg_rdata_i[6:0], 1'b0};
                        bit_cnt <= 1;              // bit 7 already out; next edge sends bit 6
                        state   <= S_RDATA;
                    end
                end
            end

            // ---- Register-pointer byte ----
            S_REG: begin
                if (scl_rising) begin
                    shifter <= {shifter[6:0], sda_now};
                    bit_cnt <= bit_cnt + 1;
                end
                if (scl_falling && bit_cnt == 8) begin
                    reg_addr_o <= shifter;
                    sda_oe     <= 1'b1;          // ACK
                    bit_cnt    <= 0;
                    state      <= S_ACK_REG;
                end
            end

            S_ACK_REG: begin
                if (scl_falling) begin
                    sda_oe  <= 1'b0;
                    shifter <= 0;
                    bit_cnt <= 0;
                    state   <= S_WDATA;          // next byte is data (or master sends RSTART)
                end
            end

            // ---- Incoming data byte (write) ----
            S_WDATA: begin
                if (scl_rising) begin
                    shifter <= {shifter[6:0], sda_now};
                    bit_cnt <= bit_cnt + 1;
                end
                if (scl_falling && bit_cnt == 8) begin
                    reg_wdata_o <= shifter;
                    reg_we_o    <= 1'b1;         // 1-cycle write strobe
                    sda_oe      <= 1'b1;         // ACK
                    bit_cnt     <= 0;
                    state       <= S_ACK_WDATA;
                end
            end

            S_ACK_WDATA: begin
                if (scl_falling) begin
                    sda_oe     <= 1'b0;
                    shifter    <= 0;
                    bit_cnt    <= 0;
                    reg_addr_o <= reg_addr_o + 1; // auto-increment for bursts
                    state      <= S_WDATA;       // accept another byte (or STOP resets us)
                end
            end

            // ---- Outgoing data byte (read) ----
            // State entry: shifter is pre-loaded with the byte to send, bit_cnt=0.
            // On each SCL falling edge we drive the MSB of shifter, then left-
            // shift. After 8 falling edges all 8 bits have been placed, and the
            // NEXT falling edge is the moment to release SDA for the master ACK.
            S_RDATA: begin
                if (scl_falling) begin
                    if (bit_cnt == 8) begin
                        // 8 bits done; release SDA so master can drive ACK/NACK
                        sda_oe  <= 1'b0;
                        bit_cnt <= 0;
                        state   <= S_ACK_RDATA;
                    end else begin
                        // Drive MSB of shifter: '0' bit -> pull low, '1' -> release
                        sda_oe  <= ~shifter[7];
                        shifter <= {shifter[6:0], 1'b0};
                        bit_cnt <= bit_cnt + 1;
                    end
                end
            end

            // Sample master's ACK on the 9th SCL rising edge.
            //   SDA low  = ACK  -> master wants another byte; preload next
            //   SDA high = NACK -> master is done; go idle until STOP
            S_ACK_RDATA: begin
                if (scl_rising) begin
                    if (sda_now == 1'b0) begin
                        // ACK: advance pointer and preload the next byte.
                        // reg_rdata_i will update combinationally when
                        // reg_addr_o is incremented.
                        reg_addr_o <= reg_addr_o + 1;
                        ack_got    <= 1'b1;
                    end else begin
                        ack_got <= 1'b0;
                    end
                end
                if (scl_falling) begin
                    if (ack_got) begin
                        // Drive bit 7 of the next byte immediately -- the
                        // upcoming SCL-high is when master samples it.
                        sda_oe  <= ~reg_rdata_i[7];
                        shifter <= {reg_rdata_i[6:0], 1'b0};
                        bit_cnt <= 1;
                        state   <= S_RDATA;
                    end else begin
                        state <= S_IDLE;           // NACK: wait for STOP
                    end
                end
            end

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule