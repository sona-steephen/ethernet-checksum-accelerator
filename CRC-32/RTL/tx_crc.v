`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.08.2026 14:38:27
// Design Name: 
// Module Name: tx_crc
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


module tx_crc (
    input  wire        tx_clk,
    input  wire        tx_rst, // High-active reset

    // -----------------------------------------------------------
    // AXI-Stream Input (From your Data Parser / Network Stack)
    // -----------------------------------------------------------
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire        s_axis_tready,

    // -----------------------------------------------------------
    // GMII / PHY Output (To the Physical Transceiver Chip)
    // -----------------------------------------------------------
    output reg  [7:0]  gmii_txd,
    output reg         gmii_tx_en
);

    // FSM State Encodings
    localparam STATE_IDLE     = 2'd0;
    localparam STATE_PREAMBLE = 2'd1;
    localparam STATE_PAYLOAD  = 2'd2;
    localparam STATE_FCS      = 2'd3;

    // Internal Registers
    reg [1:0]  state;
    reg [2:0]  tx_byte_counter; // 3-bit counter (0-7) for Preamble and FCS
    reg [31:0] crc_reg;         // The running sum tracker

    // Internal Wires
    wire [31:0] next_crc_wire;
    wire [31:0] inverted_crc = ~crc_reg; // The standard Ethernet inversion

    // -----------------------------------------------------------
    // Combinational Valve: Only accept payload data in the Payload state
    // -----------------------------------------------------------
    assign s_axis_tready = (state == STATE_PAYLOAD);

    // -----------------------------------------------------------
    // Math Core Instantiation
    // -----------------------------------------------------------
    crc32_8bit_parallel u_crc_math (
        .current_crc(crc_reg),
        .data_in(s_axis_tdata),  // Feeds raw incoming data on the fly
        .next_crc(next_crc_wire)
    );

    // -----------------------------------------------------------
    // The TX Traffic Cop (Main FSM)
    // -----------------------------------------------------------
    always @(posedge tx_clk) begin
        if (tx_rst) begin
            state           <= STATE_IDLE;
            tx_byte_counter <= 3'd0;
            gmii_txd        <= 8'h00;
            gmii_tx_en      <= 1'b0;
            crc_reg         <= 32'hFFFFFFFF;
        end else begin
            
            case (state)
                // ==========================================
                // 1. IDLE: Wait for new packet from AXI
                // ==========================================
                STATE_IDLE: begin
                    gmii_tx_en      <= 1'b0;
                    gmii_txd        <= 8'h00;
                    tx_byte_counter <= 3'd0;
                    crc_reg         <= 32'hFFFFFFFF; // Reset seed
                    
                    if (s_axis_tvalid) begin
                        state <= STATE_PREAMBLE;
                    end
                end

                // ==========================================
                // 2. PREAMBLE: 7 bytes of 0x55, 1 byte of 0xD5
                // ==========================================
                STATE_PREAMBLE: begin
                    gmii_tx_en <= 1'b1;         // Turn on PHY wire
                    crc_reg    <= 32'hFFFFFFFF; // Freeze math core (ignore preamble)
                    
                    if (tx_byte_counter < 3'd7) begin
                        gmii_txd        <= 8'h55; 
                        tx_byte_counter <= tx_byte_counter + 1'b1;
                    end else begin
                        gmii_txd        <= 8'hD5; // SFD 
                        tx_byte_counter <= 3'd0;  // Reset counter for FCS phase
                        state           <= STATE_PAYLOAD;
                    end
                end

                // ==========================================
                // 3. PAYLOAD: Stream data & calculate CRC
                // ==========================================
                STATE_PAYLOAD: begin
                    gmii_tx_en <= 1'b1;
                    
                    // Only process data if the incoming stream is valid
                    if (s_axis_tvalid && s_axis_tready) begin
                        gmii_txd <= s_axis_tdata; // Forward straight to wire
                        crc_reg  <= next_crc_wire; // Tick the math core forward
                        
                        // If this is the final byte, transition to FCS next cycle
                        if (s_axis_tlast) begin
                            state <= STATE_FCS;
                            tx_byte_counter <= 3'd0;
                        end
                    end
                end

                // ==========================================
                // 4. FCS: Stop stream, append 4 checksum bytes
                // ==========================================
                STATE_FCS: begin
                    gmii_tx_en <= 1'b1;
                    tx_byte_counter <= tx_byte_counter + 1'b1;
                    
                    // Ethernet transmits the LSB of the checksum first
                    case (tx_byte_counter)
                        3'd0: gmii_txd <= inverted_crc[7:0];
                        3'd1: gmii_txd <= inverted_crc[15:8];
                        3'd2: gmii_txd <= inverted_crc[23:16];
                        3'd3: begin
                              gmii_txd <= inverted_crc[31:24];
                              state    <= STATE_IDLE; // End of transmission!
                        end
                        default: gmii_txd <= 8'h00;
                    endcase
                end
                
                // Fallback catch
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
