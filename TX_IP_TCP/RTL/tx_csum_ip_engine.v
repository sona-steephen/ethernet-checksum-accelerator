
`timescale 1ns / 1ps

module tx_csum_ip_engine (
    input wire clk,
    input wire rst_n,

    input wire packet_start,
    input wire byte_accept,
    input wire [13:0] byte_count,

    input wire is_ipv4,
    input wire tx_ip_csum_en,

    input wire [7:0] l3_offset,
    input wire [7:0] ip_hdr_len,
    input wire [7:0] ip_checksum_offset,

    input wire [7:0] tdata,

    output reg [15:0] ip_checksum,
    output reg ip_checksum_valid
);

    // ============================================================
    // State machine
    // ============================================================

    localparam STATE_IDLE  = 2'd0;
    localparam STATE_ACCUM = 2'd1;
    localparam STATE_FOLD  = 2'd2;
    localparam STATE_DONE  = 2'd3;

    reg [1:0] state;


    // ============================================================
    // Optimized checksum accumulator
    //
    // Instead of a 32-bit accumulator, keep a 16-bit one's
    // complement sum plus carry.
    // ============================================================

    reg [16:0] sum;


    // ============================================================
    // Registered packet metadata
    // ============================================================

    reg [13:0] ip_start_r;
    reg [13:0] ip_end_r;
    reg [13:0] checksum_offset_r;

    reg        ipv4_enable_r;


    // ============================================================
    // Byte-pair registers
    // ============================================================

    reg [7:0] upper_byte;
    reg       have_upper_byte;


    // ============================================================
    // Current IP header region
    // ============================================================

    wire in_ip_header;

    assign in_ip_header =
        (byte_count >= ip_start_r) &&
        (byte_count <= ip_end_r);


    // ============================================================
    // IPv4 checksum field
    //
    // The checksum field itself must be treated as zero.
    // ============================================================

    wire is_csum_byte;

    assign is_csum_byte =
        (byte_count == checksum_offset_r) ||
        (byte_count == (checksum_offset_r + 14'd1));


    wire [7:0] active_byte;

    assign active_byte =
        is_csum_byte ? 8'h00 : tdata;


    // ============================================================
    // Current 16-bit word
    // ============================================================

    wire [15:0] current_word;

    assign current_word = {upper_byte, active_byte};


    // ============================================================
    // One's-complement addition
    //
    // 16-bit + 16-bit -> 17-bit
    //
    // Then fold carry back into bit 0.
    //
    // This keeps the accumulator bounded and removes the
    // unnecessary 32-bit carry chain from the original design.
    // ============================================================

    wire [16:0] add_word_temp;
    wire [16:0] add_word_folded;

    assign add_word_temp =
        {1'b0, sum[15:0]} +
        {1'b0, current_word};

    assign add_word_folded =
        {1'b0, add_word_temp[15:0]} +
        add_word_temp[16];


    // ============================================================
    // Main sequential logic
    // ============================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= STATE_IDLE;

            sum <= 17'd0;

            ip_start_r <= 14'd0;
            ip_end_r <= 14'd0;
            checksum_offset_r <= 14'd0;

            ipv4_enable_r <= 1'b0;

            upper_byte <= 8'd0;
            have_upper_byte <= 1'b0;

            ip_checksum <= 16'd0;
            ip_checksum_valid <= 1'b0;

        end

        else begin

            // ====================================================
            // START OF PACKET
            // ====================================================

            if (packet_start) begin

                // Capture metadata once.
                //
                // packet_start is generated from the first accepted
                // AXI byte, so this does NOT consume that byte for
                // the IP checksum. This preserves the behavior of
                // the original engine.

                ip_start_r <= {6'd0, l3_offset};

                ip_end_r <=
                    {6'd0, l3_offset} +
                    {6'd0, ip_hdr_len} -
                    14'd1;

                checksum_offset_r <=
                    {6'd0, ip_checksum_offset};

                ipv4_enable_r <=
                    is_ipv4 && tx_ip_csum_en;


                // Clear checksum state
                sum <= 17'd0;

                upper_byte <= 8'd0;
                have_upper_byte <= 1'b0;

                ip_checksum <= 16'd0;
                ip_checksum_valid <= 1'b0;


                // No IP checksum required
                if (!(is_ipv4 && tx_ip_csum_en)) begin

                    ip_checksum <= 16'd0;
                    ip_checksum_valid <= 1'b1;

                    state <= STATE_DONE;

                end

                else begin

                    state <= STATE_ACCUM;

                end

            end


            // ====================================================
            // NORMAL OPERATION
            // ====================================================

            else begin

                case (state)

                    // ------------------------------------------------
                    // IDLE
                    // ------------------------------------------------

                    STATE_IDLE: begin

                        // Wait for packet_start

                    end


                    // ------------------------------------------------
                    // ACCUMULATE
                    // ------------------------------------------------

                    STATE_ACCUM: begin

                        if (byte_accept && in_ip_header) begin

                            // ----------------------------------------
                            // First byte of 16-bit word
                            // ----------------------------------------

                            if (!have_upper_byte) begin

                                upper_byte <= active_byte;
                                have_upper_byte <= 1'b1;

                            end


                            // ----------------------------------------
                            // Second byte of 16-bit word
                            // ----------------------------------------

                            else begin

                                // One's-complement accumulation
                                sum <= add_word_folded;

                                have_upper_byte <= 1'b0;


                                // Last byte of IP header
                                if (byte_count == ip_end_r) begin

                                    state <= STATE_FOLD;

                                end

                            end

                        end

                    end


                    // ------------------------------------------------
                    // FINAL FOLD
                    // ------------------------------------------------

                    STATE_FOLD: begin

                        // IPv4 header length is normally even
                        // (IHL * 4), so normally have_upper_byte
                        // is already zero here.
                        //
                        // The following handles an odd-length
                        // region defensively.

                        if (have_upper_byte) begin

                            sum <=
                                {1'b0, sum[15:0]} +
                                {1'b0, {upper_byte, 8'h00}};

                            have_upper_byte <= 1'b0;

                        end

                        state <= STATE_DONE;

                    end


                    // ------------------------------------------------
                    // DONE
                    // ------------------------------------------------

                    STATE_DONE: begin

                        if (!ip_checksum_valid) begin

                            // Final one's-complement operation
                            ip_checksum <= ~sum[15:0];

                            ip_checksum_valid <= 1'b1;

                        end

                    end


                    // ------------------------------------------------
                    // DEFAULT
                    // ------------------------------------------------

                    default: begin

                        state <= STATE_IDLE;

                    end

                endcase

            end

        end

    end

endmodule
