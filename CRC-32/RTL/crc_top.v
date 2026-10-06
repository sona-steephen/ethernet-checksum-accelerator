`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.08.2026 14:40:18
// Design Name: 
// Module Name: crc_top
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

module crc_top (
    // System Signals
    input  wire       tx_clk,
    input  wire       tx_rst,
    input  wire       rx_clk,
    input  wire       rx_rst,

    // PHY-side (Physical Interface)
    input  wire [7:0] gmii_rxd,
    input  wire       gmii_rx_dv,
    output wire [7:0] gmii_txd,
    output wire       gmii_tx_en,

    // Network Stack-side (AXI-Stream Interface)
    // Transmit (From Network Stack -> MAC -> PHY)
    input  wire [7:0] s_axis_tdata,
    input  wire       s_axis_tvalid,
    input  wire       s_axis_tlast,
    output wire       s_axis_tready,

    // Receive (From PHY -> MAC -> Network Stack)
    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tvalid,
    output wire       m_axis_tlast,
    output wire       m_axis_tuser  // CRC Pass/Fail
);

    // 1. Instantiate Transmit (TX) Side
    tx_crc u_tx (
        .tx_clk(tx_clk),
        .tx_rst(tx_rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .gmii_txd(gmii_txd),
        .gmii_tx_en(gmii_tx_en)
    );

    // 2. Instantiate Receive (RX) Side
    rx_crc u_rx (
        .rx_clk(rx_clk),
        .rx_rst(rx_rst),
        .gmii_rxd(gmii_rxd),
        .gmii_rx_dv(gmii_rx_dv),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser),
        .m_axis_tready(1'b1) // RX is a 'push' interface, so we tie ready high
    );

endmodule