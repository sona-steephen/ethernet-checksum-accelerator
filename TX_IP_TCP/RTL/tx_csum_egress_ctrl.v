`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.09.2026 11:11:08
// Design Name: 
// Module Name: tx_csum_egress_ctrl
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

module tx_csum_egress_ctrl (
    input  wire         clk,
    input  wire         rst_n,

    // NEW: Packet request trigger to prevent infinite re-transmission loops
    input  wire         packet_start,

    // Status from Ingress / Math Engines
    input  wire         checksums_ready, 
    input  wire [13:0]  packet_length,   
    
    // Control to Store-and-Forward RAM
    output wire         rd_en,
    output reg  [13:0]  rd_addr,
    
    // Control to Insertion MUX
    output reg  [13:0]  aligned_byte_count,
    
    // Egress AXI-Stream Control
    output reg          m_axis_tvalid,
    input  wire         m_axis_tready,
    output reg          m_axis_tlast
);

    // =========================================================================
    // Explicit FSM States
    // =========================================================================
    localparam STATE_IDLE     = 2'd0;
    localparam STATE_PREFETCH = 2'd1;
    localparam STATE_OUTPUT   = 2'd2;

    reg [1:0] state;

    // =========================================================================
    // Pipeline Advance Logic
    // =========================================================================
    wire advance_pipeline = (!m_axis_tvalid) || (m_axis_tvalid && m_axis_tready);

    assign rd_en = (state == STATE_PREFETCH) || 
                   ((state == STATE_OUTPUT) && advance_pipeline && (rd_addr < packet_length));

    // =========================================================================
    // NEW: Egress Arming Logic (Prevents infinite loops)
    // =========================================================================
    reg packet_req;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            packet_req <= 1'b0;
        end else begin
            if (packet_start) begin
                // Arm the egress controller when a new packet starts
                packet_req <= 1'b1;
            end else if (state == STATE_OUTPUT && m_axis_tlast && advance_pipeline) begin
                // Disarm the egress controller the moment the packet finishes sending
                packet_req <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Sequential Logic: Egress State Machine
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= STATE_IDLE;
            rd_addr            <= 14'd0;
            aligned_byte_count <= 14'd0;
            m_axis_tvalid      <= 1'b0;
            m_axis_tlast       <= 1'b0;
        end else begin
            case (state)
                
                STATE_IDLE: begin
                    // MUST have both checksums ready AND an armed packet request
                    if (checksums_ready && packet_req) begin
                        state         <= STATE_PREFETCH;
                        rd_addr       <= 14'd0;
                        m_axis_tvalid <= 1'b0;
                    end
                end

                STATE_PREFETCH: begin
                    rd_addr            <= rd_addr + 1'b1;
                    aligned_byte_count <= 14'd0; 
                    m_axis_tvalid      <= 1'b1;
                    
                    if (packet_length == 14'd1) begin
                        m_axis_tlast <= 1'b1;
                    end else begin
                        m_axis_tlast <= 1'b0;
                    end
                    
                    state <= STATE_OUTPUT;
                end

                STATE_OUTPUT: begin
                    if (advance_pipeline) begin
                        
                        if (m_axis_tlast) begin
                            m_axis_tvalid <= 1'b0;
                            m_axis_tlast  <= 1'b0;
                            state         <= STATE_IDLE;
                            
                        end else begin
                            aligned_byte_count <= rd_addr;
                            
                            if (rd_addr == (packet_length - 1'b1)) begin
                                m_axis_tlast <= 1'b1;
                            end else begin
                                m_axis_tlast <= 1'b0;
                            end
                            
                            rd_addr       <= rd_addr + 1'b1;
                            m_axis_tvalid <= 1'b1;
                        end
                    end
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule