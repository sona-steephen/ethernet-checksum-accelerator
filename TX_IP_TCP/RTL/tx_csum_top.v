`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.09.2026 11:15:41
// Design Name: 
// Module Name: tx_csum_top
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

module tx_csum_top (
    input  wire         clk,
    input  wire         rst_n,

    // ============================================================
    // AXI4-Stream Input
    // ============================================================
    input  wire [7:0]   s_axis_tdata,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire         s_axis_tlast,
    input  wire [127:0] s_axis_tuser,

    // ============================================================
    // AXI4-Stream Output
    // ============================================================
    output wire [7:0]   m_axis_tdata,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire         m_axis_tlast
);

    // ============================================================
    // Metadata Signals
    // ============================================================

    wire        is_ipv4;
    wire        tx_ip_csum_en;
    wire        tx_tcp_csum_en;
    wire [7:0]  l4_protocol;

    wire [7:0]  l3_offset;
    wire [7:0]  ip_hdr_len;

    wire [7:0]  tcp_offset;
    wire [7:0]  tcp_hdr_len;
    wire [15:0] tcp_length;

    wire [31:0] src_ip;
    wire [31:0] dst_ip;

    wire [7:0]  ip_checksum_offset;
    wire [7:0]  tcp_checksum_offset;


    // ============================================================
    // Packet Tracking
    // ============================================================

    wire [13:0] byte_count;
    wire        packet_start;
    wire        packet_end;
    wire [13:0] packet_length;
    wire        packet_complete;


// ============================================================
    // AXI Byte Acceptance & Hardware Backpressure
    // ============================================================
    
    reg ingress_ready_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ingress_ready_reg <= 1'b1;
        end else begin
            // LOCK: When a packet finishes entering the RAM, drop tready to 0.
            // This forces the upstream DMA to pause the next packet.
            if (s_axis_tvalid && ingress_ready_reg && s_axis_tlast) begin
                ingress_ready_reg <= 1'b0;
            end
            // UNLOCK: When a packet finishes exiting the RAM, raise tready to 1.
            // This tells the upstream DMA it is safe to send the next packet.
            else if (m_axis_tvalid && m_axis_tready && m_axis_tlast) begin
                ingress_ready_reg <= 1'b1;
            end
        end
    end

    assign s_axis_tready = ingress_ready_reg;

    wire byte_accept = s_axis_tvalid && s_axis_tready;




    // ============================================================
    // Checksum Results
    // ============================================================

    wire [15:0] ip_checksum;
    wire        ip_checksum_valid;

    wire [15:0] tcp_checksum;
    wire        tcp_checksum_valid;


    // ============================================================
    // Egress Ready Condition
    // ============================================================
    //
    // IMPORTANT:
    //
    // checksum_valid signals can remain HIGH from a previous
    // packet.
    //
    // Therefore egress is allowed to start only when:
    //
    //     packet_complete
    //         AND
    //     ip_checksum_valid
    //         AND
    //     tcp_checksum_valid
    //
    // This prevents the next packet from starting egress using
    // stale checksum-valid signals.
    //
    // ============================================================

    wire packet_ready_for_egress;

    assign packet_ready_for_egress =
           packet_complete &&
           ip_checksum_valid &&
           tcp_checksum_valid;


    // ============================================================
    // RAM Signals
    // ============================================================

    wire        rd_en;
    wire [13:0] rd_addr;
    wire [7:0]  ram_rd_data;


    // ============================================================
    // Egress Alignment
    // ============================================================

    wire [13:0] aligned_byte_count;


    // ============================================================
    // Checksum MUX Output
    // ============================================================

    wire [7:0] mux_data_out;


    // ============================================================
    // 1. Metadata Tracker
    // ============================================================

    tx_csum_meta_tracker u_meta_tracker (

        .clk                  (clk),
        .rst_n                (rst_n),

        // AXI input
        .s_axis_tdata         (s_axis_tdata),
        .s_axis_tvalid        (s_axis_tvalid),
        .s_axis_tready        (s_axis_tready),
        .s_axis_tlast         (s_axis_tlast),
        .s_axis_tuser         (s_axis_tuser),

        // Metadata
        .is_ipv4              (is_ipv4),
        .tx_ip_csum_en        (tx_ip_csum_en),
        .tx_tcp_csum_en       (tx_tcp_csum_en),
        .l4_protocol          (l4_protocol),

        .l3_offset            (l3_offset),
        .ip_hdr_len           (ip_hdr_len),

        .tcp_offset           (tcp_offset),
        .tcp_hdr_len          (tcp_hdr_len),
        .tcp_length           (tcp_length),

        .src_ip               (src_ip),
        .dst_ip               (dst_ip),

        .ip_checksum_offset  (ip_checksum_offset),
        .tcp_checksum_offset (tcp_checksum_offset),

        // Packet tracking
        .byte_count           (byte_count),
        .packet_start         (packet_start),
        .packet_end           (packet_end),
        .packet_length        (packet_length),
        .packet_complete      (packet_complete)
    );


    // ============================================================
    // 2. IPv4 Checksum Engine
    // ============================================================

    tx_csum_ip_engine u_ip_engine (

        .clk                 (clk),
        .rst_n               (rst_n),

        .tdata               (s_axis_tdata),
        .byte_accept         (byte_accept),
       
        .byte_count          (byte_count),
        .packet_start        (packet_start),

        // IPv4 information
        .is_ipv4             (is_ipv4),
        .tx_ip_csum_en       (tx_ip_csum_en),

        .l3_offset           (l3_offset),
        .ip_hdr_len          (ip_hdr_len),
        .ip_checksum_offset  (ip_checksum_offset),

        // Result
        .ip_checksum         (ip_checksum),
        .ip_checksum_valid   (ip_checksum_valid)
    );


    // ============================================================
    // 3. TCP Checksum Engine
    // ============================================================

    tx_csum_tcp_engine u_tcp_engine (

        .clk                  (clk),
        .rst_n                (rst_n),

        .tdata                (s_axis_tdata),
        .byte_accept          (byte_accept),
        .s_axis_tlast         (s_axis_tlast),
        .byte_count           (byte_count),
        .packet_start         (packet_start),

        // Protocol information
        .is_ipv4              (is_ipv4),
        .tx_tcp_csum_en       (tx_tcp_csum_en),
        .l4_protocol          (l4_protocol),

        // TCP information
        .tcp_offset           (tcp_offset),
        .tcp_length           (tcp_length),

        // IPv4 pseudo-header
        .src_ip               (src_ip),
        .dst_ip               (dst_ip),

        // TCP checksum location
        .tcp_checksum_offset  (tcp_checksum_offset),

        // Result
        .tcp_checksum         (tcp_checksum),
        .tcp_checksum_valid   (tcp_checksum_valid)
    );


    // ============================================================
    // 4. Store-and-Forward RAM
    // ============================================================
    //
    // IMPORTANT:
    //
    // This RAM does NOT have s_axis_tlast.
    //
    // It only needs:
    //
    //     write enable
    //     write address
    //     write data
    //
    // and:
    //
    //     read enable
    //     read address
    //     read data
    //
    // ============================================================

    tx_csum_ram_buffer u_ram (

        .clk       (clk),

        .wr_en     (byte_accept),
        .wr_addr   (byte_count),
        .wr_data   (s_axis_tdata),

        .rd_en     (rd_en),
        .rd_addr   (rd_addr),
        .rd_data   (ram_rd_data)
    );


    // ============================================================
    // 5. Egress Controller
    // ============================================================
    //
    // Your current egress controller does NOT have:
    //
    //     ram_data_out
    //     m_axis_tdata
    //
    // Therefore those signals are handled by the RAM and MUX
    // separately.
    //
    // The egress controller generates:
    //
    //     rd_en
    //     rd_addr
    //     aligned_byte_count
    //     m_axis_tvalid
    //     m_axis_tlast
    //
    // ============================================================
tx_csum_egress_ctrl u_egress_ctrl (

        .clk                  (clk),
        .rst_n                (rst_n),

        // NEW: Wire the packet_start signal here
        .packet_start         (packet_start),

        // Packet/checksum completion
        .checksums_ready      (packet_ready_for_egress),
        .packet_length        (packet_length),

        // RAM read control
        .rd_en                (rd_en),
        .rd_addr              (rd_addr),

        // Checksum insertion alignment
        .aligned_byte_count   (aligned_byte_count),

        // AXI output control
        .m_axis_tvalid        (m_axis_tvalid),
        .m_axis_tready        (m_axis_tready),
        .m_axis_tlast         (m_axis_tlast)
    );


    // ============================================================
    // 6. Checksum Insertion MUX
    // ============================================================
    //
    // RAM output is normally passed unchanged.
    //
    // IPv4 checksum is inserted when:
    //
    //     is_ipv4 && tx_ip_csum_en
    //
    // TCP checksum is inserted when:
    //
    //     is_ipv4 &&
    //     l4_protocol == 8'h06 &&
    //     tx_tcp_csum_en
    //
    // ============================================================

    tx_csum_insert_mux u_insert_mux (

        // Protocol
        .is_ipv4              (is_ipv4),
        .l4_protocol          (l4_protocol),

        // Enables
        .tx_ip_csum_en        (tx_ip_csum_en),
        .tx_tcp_csum_en       (tx_tcp_csum_en),

        // Checksum offsets
        .ip_checksum_offset   (ip_checksum_offset),
        .tcp_checksum_offset  (tcp_checksum_offset),

        // Calculated checksums
        .ip_checksum          (ip_checksum),
        .tcp_checksum         (tcp_checksum),

        // RAM data
        .ram_data_out         (ram_rd_data),

        // Aligned byte number
        .aligned_byte_count   (aligned_byte_count),

        // Output
        .mux_data_out         (mux_data_out)
    );


    // ============================================================
    // Final AXI4-Stream Output
    // ============================================================

    assign m_axis_tdata = mux_data_out;


endmodule

