`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.09.2026 10:50:18
// Design Name: 
// Module Name: tx_csum_meta_tracker
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

module tx_csum_meta_tracker (
    input  wire         clk,
    input  wire         rst_n,

    // ============================================================
    // AXI4-Stream Input
    // ============================================================
    input  wire [7:0]   s_axis_tdata,
    input  wire         s_axis_tvalid,
    input  wire         s_axis_tready,
    input  wire         s_axis_tlast,
    input  wire [127:0] s_axis_tuser,

    // ============================================================
    // Packet Metadata
    // ============================================================
    output reg          is_ipv4,
    output reg          tx_ip_csum_en,
    output reg          tx_tcp_csum_en,
    output reg  [7:0]   l4_protocol,

    output reg  [7:0]   l3_offset,
    output reg  [7:0]   ip_hdr_len,

    output reg  [7:0]   tcp_offset,
    output reg  [7:0]   tcp_hdr_len,
    output reg  [15:0]  tcp_length,

    output reg  [31:0]  src_ip,
    output reg  [31:0]  dst_ip,

    output reg  [7:0]   ip_checksum_offset,
    output reg  [7:0]   tcp_checksum_offset,

    // ============================================================
    // Packet Tracking
    // ============================================================
    output wire [13:0]  byte_count,
    output wire         packet_start,
    output wire         packet_end,
    output reg  [13:0]  packet_length,

    // High when the complete current packet has been received
    output reg          packet_complete
);

    // ============================================================
    // Internal Registers
    // ============================================================
    reg         in_packet_reg;
    reg [13:0]  byte_count_reg;
    reg [127:0] tuser_reg;

    // ============================================================
    // AXI4-Stream Byte Acceptance
    // ============================================================
    wire byte_accept;

    assign byte_accept = s_axis_tvalid && s_axis_tready;

    // ============================================================
    // Packet Boundary Detection
    // ============================================================

    // First accepted byte of a packet
    assign packet_start = byte_accept && !in_packet_reg;

    // Accepted final byte of a packet
    assign packet_end = byte_accept && s_axis_tlast;

    // Current byte index
    assign byte_count = byte_count_reg;

    // ============================================================
    // Packet Tracking and Metadata Capture
    // ============================================================
    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            in_packet_reg  <= 1'b0;
            byte_count_reg <= 14'd0;
            packet_length  <= 14'd0;
            packet_complete <= 1'b0;
            tuser_reg      <= 128'd0;

        end else begin

            // ----------------------------------------------------
            // New packet
            // ----------------------------------------------------
            if (packet_start) begin

                // Capture metadata associated with first byte
                tuser_reg <= s_axis_tuser;

                // A new packet is now being received.
                // Therefore the previous packet is no longer
                // considered complete.
                packet_complete <= 1'b0;
            end

            // ----------------------------------------------------
            // Accepted AXI byte
            // ----------------------------------------------------
            if (byte_accept) begin

                // ------------------------------------------------
                // Last byte of packet
                // ------------------------------------------------
                if (s_axis_tlast) begin

                    // Packet reception is complete
                    in_packet_reg <= 1'b0;

                    // Reset byte counter for next packet
                    byte_count_reg <= 14'd0;

                    // Current byte_count is zero-based.
                    // Therefore packet length = byte_count + 1.
                    packet_length <= byte_count_reg + 1'b1;

                    // Tell the rest of the design that the
                    // complete packet is now present in RAM.
                    packet_complete <= 1'b1;

                end else begin

                    // ------------------------------------------------
                    // Packet is still being received
                    // ------------------------------------------------
                    in_packet_reg <= 1'b1;

                    // Move to next byte index
                    byte_count_reg <= byte_count_reg + 1'b1;

                end
            end
        end
    end

    // ============================================================
    // Active Metadata
    // ============================================================
    //
    // On the first byte:
    //     use current tuser directly
    //
    // After the first byte:
    //     use captured tuser_reg
    //
    // This avoids a one-cycle delay in metadata availability.
    // ============================================================

    wire [127:0] active_tuser;

    assign active_tuser =
        packet_start ? s_axis_tuser : tuser_reg;

    // ============================================================
    // Metadata Field Extraction
    // ============================================================
    always @(*) begin

        // --------------------------------------------------------
        // Protocol information
        // --------------------------------------------------------
        is_ipv4       = active_tuser[0];
        tx_ip_csum_en = active_tuser[1];
        tx_tcp_csum_en = active_tuser[2];

        l4_protocol   = active_tuser[10:3];

        // --------------------------------------------------------
        // Header offsets and lengths
        // --------------------------------------------------------
        l3_offset     = active_tuser[18:11];
        ip_hdr_len    = active_tuser[26:19];

        tcp_offset    = active_tuser[34:27];
        tcp_hdr_len   = active_tuser[42:35];

        tcp_length    = active_tuser[58:43];

        // --------------------------------------------------------
        // IPv4 pseudo-header information
        // --------------------------------------------------------
        src_ip        = active_tuser[90:59];
        dst_ip        = active_tuser[122:91];

        // --------------------------------------------------------
        // Derived checksum field offsets
        // --------------------------------------------------------
        //
        // IPv4 checksum field:
        //     offset + 10 bytes
        //
        // TCP checksum field:
        //     TCP offset + 16 bytes
        //
        ip_checksum_offset =
            active_tuser[18:11] + 8'd10;

        tcp_checksum_offset =
            active_tuser[34:27] + 8'd16;

    end

endmodule

