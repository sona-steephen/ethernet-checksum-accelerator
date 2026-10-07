`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.09.2026 11:06:54
// Design Name: 
// Module Name: tx_csum_insert_mux
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

module tx_csum_insert_mux (
    // ============================================================
    // Control Flags (from Metadata Tracker)
    // ============================================================
    input wire         is_ipv4,
    input wire [7:0]   l4_protocol,
    input wire         tx_ip_csum_en,
    input wire         tx_tcp_csum_en,

    // ============================================================
    // Offsets and Computed Checksums
    // ============================================================
    input wire [7:0]   ip_checksum_offset,
    input wire [7:0]   tcp_checksum_offset,

    input wire [15:0]  ip_checksum,
    input wire [15:0]  tcp_checksum,

    // ============================================================
    // Data Path
    // ============================================================
    input wire [7:0]   ram_data_out,
    input wire [13:0]  aligned_byte_count,

    output reg [7:0]   mux_data_out
);

    always @(*) begin

        // --------------------------------------------------------
        // Default: pass RAM data unchanged
        // --------------------------------------------------------
        mux_data_out = ram_data_out;

        // --------------------------------------------------------
        // IPv4 checksum insertion
        // --------------------------------------------------------
        //
        // Only insert the calculated IPv4 checksum when:
        //
        //      is_ipv4       = 1
        //      tx_ip_csum_en = 1
        //
        // IPv4 checksum occupies two bytes.
        // --------------------------------------------------------
        if (is_ipv4 && tx_ip_csum_en) begin

            // High byte
            if (aligned_byte_count == ip_checksum_offset) begin

                mux_data_out = ip_checksum[15:8];

            end

            // Low byte
            else if (aligned_byte_count ==
                     (ip_checksum_offset + 14'd1)) begin

                mux_data_out = ip_checksum[7:0];

            end
        end

        // --------------------------------------------------------
        // TCP checksum insertion
        // --------------------------------------------------------
        //
        // Only insert TCP checksum when:
        //
        //      is_ipv4       = 1
        //      l4_protocol    = TCP (0x06)
        //      tx_tcp_csum_en = 1
        //
        // TCP checksum occupies two bytes.
        // --------------------------------------------------------
        if (is_ipv4 &&
            (l4_protocol == 8'h06) &&
            tx_tcp_csum_en) begin

            // High byte
            if (aligned_byte_count == tcp_checksum_offset) begin

                mux_data_out = tcp_checksum[15:8];

            end

            // Low byte
            else if (aligned_byte_count ==
                     (tcp_checksum_offset + 14'd1)) begin

                mux_data_out = tcp_checksum[7:0];

            end
        end

    end

endmodule

