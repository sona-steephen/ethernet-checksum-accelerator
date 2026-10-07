`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.09.2026 09:49:49
// Design Name: 
// Module Name: tx_csum_tcp_engine
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////



`timescale 1ns / 1ps

module tx_csum_tcp_engine (
    input wire clk,
    input wire rst_n,

    input wire [7:0]  tdata,
    input wire        byte_accept,
    input wire        s_axis_tlast,

    input wire [13:0] byte_count,
    input wire        packet_start,

    input wire        is_ipv4,
    input wire        tx_tcp_csum_en,
    input wire [7:0]  l4_protocol,

    input wire [7:0]  tcp_offset,
    input wire [15:0] tcp_length,

    input wire [31:0] src_ip,
    input wire [31:0] dst_ip,

    input wire [7:0]  tcp_checksum_offset,

    output reg [15:0] tcp_checksum,
    output reg        tcp_checksum_valid
);

    // ============================================================
    // States
    // ============================================================

    localparam STATE_IDLE  = 2'd0;
    localparam STATE_ACCUM = 2'd1;
    localparam STATE_FOLD  = 2'd2;
    localparam STATE_DONE  = 2'd3;

    reg [1:0] state;


    // ============================================================
    // 17-bit one's-complement accumulator
    //
    // Original design used:
    //
    //     reg [31:0] sum;
    //
    // The accumulator is now bounded to 16 bits + carry.
    // ============================================================

    reg [16:0] sum;


    // ============================================================
    // Registered packet metadata
    //
    // Capture metadata once at packet_start.
    // This prevents the accumulator datapath from depending
    // directly on changing metadata signals.
    // ============================================================

    reg        ipv4_r;
    reg        tcp_enable_r;

    reg [7:0]  protocol_r;

    reg [13:0] tcp_start_r;
    reg [13:0] tcp_end_r;

    reg [13:0] checksum_offset_r;


    // ============================================================
    // Registered pseudo-header sum
    //
    // Instead of:
    //
    //     src_hi + src_lo + dst_hi + dst_lo
    //       + protocol + tcp_length
    //
    // all being one large combinational expression, calculate
    // the pseudo-header sum sequentially at packet_start.
    // ============================================================

    reg [16:0] pseudo_sum_r;

    reg [1:0]  pseudo_state;

    localparam PH_IDLE = 2'd0;
    localparam PH_SRC  = 2'd1;
    localparam PH_DST  = 2'd2;
    localparam PH_LEN  = 2'd3;


    // ============================================================
    // Byte-pair handling
    // ============================================================

    reg [7:0] upper_byte;
    reg       have_upper_byte;


    // ============================================================
    // Current TCP region
    // ============================================================

    wire in_tcp_region;

    assign in_tcp_region =
        (byte_count >= tcp_start_r) &&
        (byte_count <= tcp_end_r);


    // ============================================================
    // TCP checksum field
    // ============================================================

    wire is_csum_byte;

    assign is_csum_byte =
        (byte_count == checksum_offset_r) ||
        (byte_count == (checksum_offset_r + 14'd1));


    wire [7:0] active_byte;

    assign active_byte =
        is_csum_byte ? 8'h00 : tdata;


    // ============================================================
    // Current 16-bit TCP data word
    // ============================================================

    wire [15:0] current_word;

    assign current_word =
        {upper_byte, active_byte};


    // ============================================================
    // One's-complement addition
    //
    // 16-bit sum + 16-bit word
    //          |
    //          v
    //       17 bits
    //          |
    //          v
    //  add carry back to bit 0
    // ============================================================

    wire [16:0] data_add_temp;
    wire [16:0] data_add_folded;

    assign data_add_temp =
        {1'b0, sum[15:0]} +
        {1'b0, current_word};

    assign data_add_folded =
        {1'b0, data_add_temp[15:0]} +
        data_add_temp[16];


    // ============================================================
    // Pseudo-header addition helper
    // ============================================================

    wire [16:0] pseudo_add_temp;
    wire [16:0] pseudo_add_folded;

    assign pseudo_add_temp =
        {1'b0, pseudo_sum_r[15:0]} +
        {1'b0, 16'h0000};

    assign pseudo_add_folded =
        {1'b0, pseudo_add_temp[15:0]} +
        pseudo_add_temp[16];


    // ============================================================
    // Main sequential block
    // ============================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= STATE_IDLE;

            sum <= 17'd0;

            pseudo_sum_r <= 17'd0;
            pseudo_state <= PH_IDLE;

            ipv4_r <= 1'b0;
            tcp_enable_r <= 1'b0;

            protocol_r <= 8'd0;

            tcp_start_r <= 14'd0;
            tcp_end_r <= 14'd0;

            checksum_offset_r <= 14'd0;

            upper_byte <= 8'd0;
            have_upper_byte <= 1'b0;

            tcp_checksum <= 16'd0;
            tcp_checksum_valid <= 1'b0;

        end

        else begin

            // ====================================================
            // NEW PACKET
            // ====================================================

            if (packet_start) begin

                // -----------------------------------------------
                // Capture packet metadata
                // -----------------------------------------------

                ipv4_r <= is_ipv4;

                tcp_enable_r <= tx_tcp_csum_en;

                protocol_r <= l4_protocol;


                tcp_start_r <=
                    {6'd0, tcp_offset};

                tcp_end_r <=
                    {6'd0, tcp_offset} +
                    {6'd0, tcp_length} -
                    14'd1;


                checksum_offset_r <=
                    {6'd0, tcp_checksum_offset};


                // -----------------------------------------------
                // Clear data checksum state
                // -----------------------------------------------

                sum <= 17'd0;

                upper_byte <= 8'd0;
                have_upper_byte <= 1'b0;

                tcp_checksum <= 16'd0;
                tcp_checksum_valid <= 1'b0;


                // -----------------------------------------------
                // Start pseudo-header calculation
                // -----------------------------------------------

                //
                // Pseudo-header:
                //
                //     Source IP       32 bits
                //     Destination IP  32 bits
                //     Zero             8 bits
                //     Protocol         8 bits
                //     TCP length      16 bits
                //
                // We calculate it over several cycles instead of
                // using one large six-input combinational adder.
                //

                pseudo_sum_r <= 17'd0;

                if (is_ipv4 &&
                    tx_tcp_csum_en &&
                    (l4_protocol == 8'h06)) begin

                    pseudo_state <= PH_SRC;

                    state <= STATE_ACCUM;

                end

                else begin

                    tcp_checksum <= 16'd0;
                    tcp_checksum_valid <= 1'b1;

                    pseudo_state <= PH_IDLE;

                    state <= STATE_DONE;

                end

            end


            // ====================================================
            // NORMAL OPERATION
            // ====================================================

            else begin

                // =================================================
                // PSEUDO HEADER CALCULATION
                // =================================================

                case (pseudo_state)

                    PH_SRC: begin

                        // Source IP high 16 bits

                        pseudo_sum_r <=
                            {1'b0, src_ip[31:16]};

                        pseudo_state <= PH_DST;

                    end


                    PH_DST: begin

                        // Source IP low 16 bits + destination
                        // IP high 16 bits

                        pseudo_sum_r <=
                            {1'b0, pseudo_sum_r[15:0]} +
                            {1'b0, src_ip[15:0]} +
                            {1'b0, dst_ip[31:16]};

                        pseudo_state <= PH_LEN;

                    end


                    PH_LEN: begin

                        // Destination IP low 16 bits
                        // + protocol
                        // + TCP length
                        //
                        // Protocol occupies the low byte.

                        pseudo_sum_r <=
                            {1'b0, pseudo_sum_r[15:0]} +
                            {1'b0, dst_ip[15:0]} +
                            {1'b0, {8'h00, protocol_r}} +
                            {1'b0, tcp_length};

                        pseudo_state <= PH_IDLE;

                    end


                    default: begin

                        pseudo_state <= PH_IDLE;

                    end

                endcase


                // =================================================
                // TCP DATA ACCUMULATION
                // =================================================

                if (state == STATE_ACCUM) begin

                    if (byte_accept && in_tcp_region) begin

                        // -----------------------------------------
                        // First byte of word
                        // -----------------------------------------

                        if (!have_upper_byte) begin

                            upper_byte <= active_byte;

                            have_upper_byte <= 1'b1;

                        end


                        // -----------------------------------------
                        // Second byte of word
                        // -----------------------------------------

                        else begin

                            sum <= data_add_folded;

                            have_upper_byte <= 1'b0;


                            // Last byte of TCP region
                            if (byte_count == tcp_end_r) begin

                                state <= STATE_FOLD;

                            end

                        end

                    end

                end


                // =================================================
                // FINAL FOLD
                // =================================================

                if (state == STATE_FOLD) begin

                    // Add the registered pseudo-header sum to
                    // the TCP data checksum.
                    //
                    // Both are already one's-complement sums.

                    sum <=
                        {1'b0, sum[15:0]} +
                        {1'b0, pseudo_sum_r[15:0]};

                    state <= STATE_DONE;

                end


                // =================================================
                // DONE
                // =================================================

                if (state == STATE_DONE) begin

                    if (!tcp_checksum_valid) begin

                        tcp_checksum <= ~sum[15:0];

                        tcp_checksum_valid <= 1'b1;

                    end

                end

            end

        end

    end

endmodule

