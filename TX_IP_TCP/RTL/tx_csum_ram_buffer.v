`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.09.2026 10:57:14
// Design Name: 
// Module Name: tx_csum_ram_buffer
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

module tx_csum_ram_buffer #(
    parameter ADDR_WIDTH = 14,
    parameter DATA_WIDTH = 8
)(
    input  wire                  clk,
    
    // Write Port (Driven by Ingress)
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data,
    
    // Read Port (Driven by Egress FSM)
    input  wire                  rd_en,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output reg  [DATA_WIDTH-1:0] rd_data
);

    // =========================================================================
    // Behavioral RAM Array
    // This will be replaced by an SRAM Hard Macro during physical synthesis
    // =========================================================================
    localparam RAM_DEPTH = 1 << ADDR_WIDTH;
    
    reg [DATA_WIDTH-1:0] ram_array [0:RAM_DEPTH-1];

    // =========================================================================
    // Write Port Logic
    // =========================================================================
    always @(posedge clk) begin
        if (wr_en) begin
            ram_array[wr_addr] <= wr_data;
        end
    end

    // =========================================================================
    // Read Port Logic
    // =========================================================================
    // ASIC SRAM macros are almost always synchronous read, meaning the read 
    // address is sampled on the clock edge, and data appears on the next cycle.
    always @(posedge clk) begin
        if (rd_en) begin
            rd_data <= ram_array[rd_addr];
        end
    end

endmodule