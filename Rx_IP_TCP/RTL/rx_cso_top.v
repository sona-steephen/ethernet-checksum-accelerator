
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 31.08.2026 11:46:12
// Design Name: 
// Module Name: rx_cso_top
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

/* =============================================================================
   MODULE: rx_cso_top (Receive Checksum Offload Engine)
   
   ARCHITECTURAL CONTRACTS & INTEGRATION GUIDE:
   1. Packet Context: The Parser must guarantee that `m_ipv4_valid` and/or 
      `m_tcp_valid` (the header context) are pulsed BEFORE or ON THE SAME CYCLE 
      as the first byte of the corresponding AXI payload stream.
   2. Zero-Overlap: The Parser must NOT pulse a new valid signal until the 
      previous packet has fully completed processing. 
   3. Zero Payload: For TCP packets with 0 payload bytes (e.g., pure ACKs), 
      the Parser only needs to pulse `m_tcp_valid`. The hardware will auto-detect
      the zero-payload state via the IP/TCP length fields and evaluate instantly.
   4. Status Flags (Per Protocol):
      - _ok: Math is perfect, packet is within fast-path limits.
      - _error: Math failed, CRC failed, or packet is physically malformed.
      - _unsupported: Packet contains Options (IHL > 5 or Data Offset > 5).
        These must be routed to the CPU/Software slow-path.
============================================================================= */

module rx_cso_top (
    // -------------------------------------------------------------------------
    // System Clock and Reset
    // -------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // IPv4 Parallel Interface (From Parser)
    // -------------------------------------------------------------------------
    input  wire        m_ipv4_valid,
    input  wire [31:0] m_ipv4_src_ip,
    input  wire [31:0] m_ipv4_dst_ip,
    input  wire [7:0]  m_ipv4_protocol,
    input  wire [15:0] m_ipv4_total_length,
    input  wire [3:0]  m_ipv4_ihl,
    input  wire [7:0]  m_ipv4_dscp_ecn,
    input  wire [15:0] m_ipv4_identification,
    input  wire [2:0]  m_ipv4_flags,
    input  wire [12:0] m_ipv4_fragment_offset,
    input  wire [7:0]  m_ipv4_ttl,
    input  wire [15:0] m_ipv4_header_checksum,

    // -------------------------------------------------------------------------
    // TCP Parallel Interface (From Parser)
    // -------------------------------------------------------------------------
    input  wire        m_tcp_valid,
    input  wire [15:0] m_tcp_src_port,
    input  wire [15:0] m_tcp_dst_port,
    input  wire [31:0] m_tcp_seq_num,
    input  wire [31:0] m_tcp_ack_num,
    input  wire [3:0]  m_tcp_data_offset, 
    input  wire [7:0]  m_tcp_flags,
    input  wire [15:0] m_tcp_window,
    input  wire [15:0] m_tcp_checksum,
    input  wire [15:0] m_tcp_urg_ptr,

    // -------------------------------------------------------------------------
    // Delayed Payload AXI-Stream (From Parser FIFO)
    // -------------------------------------------------------------------------
    input  wire [7:0]  m_axis_tdata,
    input  wire        m_axis_tvalid,
    input  wire        m_axis_tlast,
    input  wire        m_axis_tuser,          // 1 = Bad CRC, drop packet
    input  wire        m_axis_is_tcp_payload, // 1 = Data is TCP payload

    // -------------------------------------------------------------------------
    // CSO Output Flags (To Next Stage / CPU Driver)
    // -------------------------------------------------------------------------
    // IPv4 Status
    output wire        ipv4_csum_ok,
    output wire        ipv4_csum_error,
    output wire        ipv4_csum_unsupported,
    
    // TCP Status
    output wire        tcp_csum_ok,
    output wire        tcp_csum_error,
    output wire        tcp_csum_unsupported
);

    // =========================================================================
    // INSTANTIATION 1: IPv4 Checksum Verifier
    // =========================================================================
    rx_ipv4_csum u_rx_ipv4_csum (
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        .m_ipv4_valid           (m_ipv4_valid),
        .m_ipv4_src_ip          (m_ipv4_src_ip),
        .m_ipv4_dst_ip          (m_ipv4_dst_ip),
        .m_ipv4_protocol        (m_ipv4_protocol),
        .m_ipv4_total_length    (m_ipv4_total_length),
        .m_ipv4_ihl             (m_ipv4_ihl),
        .m_ipv4_dscp_ecn        (m_ipv4_dscp_ecn),
        .m_ipv4_identification  (m_ipv4_identification),
        .m_ipv4_flags           (m_ipv4_flags),
        .m_ipv4_fragment_offset (m_ipv4_fragment_offset),
        .m_ipv4_ttl             (m_ipv4_ttl),
        .m_ipv4_header_checksum (m_ipv4_header_checksum),
        
        // Explicit Outputs
        .ipv4_csum_ok           (ipv4_csum_ok),
        .ipv4_csum_error        (ipv4_csum_error),
        .ipv4_csum_unsupported  (ipv4_csum_unsupported)
    );

    // =========================================================================
    // INSTANTIATION 2: TCP Checksum Verifier
    // =========================================================================
    rx_tcp_csum u_rx_tcp_csum (
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        // Parallel Headers shared from IP and TCP
        .m_tcp_valid            (m_tcp_valid),
        .m_ipv4_src_ip          (m_ipv4_src_ip),
        .m_ipv4_dst_ip          (m_ipv4_dst_ip),
        .m_ipv4_protocol        (m_ipv4_protocol),
        .m_ipv4_total_length    (m_ipv4_total_length),
        .m_ipv4_ihl             (m_ipv4_ihl),
        
        .m_tcp_src_port         (m_tcp_src_port),
        .m_tcp_dst_port         (m_tcp_dst_port),
        .m_tcp_seq_num          (m_tcp_seq_num),
        .m_tcp_ack_num          (m_tcp_ack_num),
        .m_tcp_data_offset      (m_tcp_data_offset), 
        .m_tcp_flags            (m_tcp_flags),
        .m_tcp_window           (m_tcp_window),
        .m_tcp_checksum         (m_tcp_checksum),
        .m_tcp_urg_ptr          (m_tcp_urg_ptr),
        
        // AXI-Stream Payload
        .m_axis_tdata           (m_axis_tdata),
        .m_axis_tvalid          (m_axis_tvalid),
        .m_axis_tlast           (m_axis_tlast),
        .m_axis_tuser           (m_axis_tuser),
        .m_axis_is_tcp_payload  (m_axis_is_tcp_payload),
        
        // Explicit Outputs
        .tcp_csum_ok            (tcp_csum_ok),
        .tcp_csum_error         (tcp_csum_error),
        .tcp_csum_unsupported   (tcp_csum_unsupported)
    );

endmodule
