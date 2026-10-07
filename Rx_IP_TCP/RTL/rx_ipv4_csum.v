`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 31.08.2026 11:43:55
// Design Name: 
// Module Name: rx_ipv4_csum
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

module rx_ipv4_csum (
    input  wire        clk,
    input  wire        rst_n,
    
    // Inputs from Parser
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
    
    // Explicit Status Outputs
    output reg         ipv4_csum_ok,
    output reg         ipv4_csum_error,
    output reg         ipv4_csum_unsupported
);

    // =========================================================================
    // STAGE 1: Capture IHL and Sum Header Fields (Explicitly Widened)
    // =========================================================================
    reg [31:0] stage1_sum;
    reg        stage1_valid;
    reg [3:0]  stage1_ihl;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_sum   <= 32'd0;
            stage1_valid <= 1'b0;
            stage1_ihl   <= 4'd0;
        end else begin
            stage1_valid <= m_ipv4_valid;
            
            if (m_ipv4_valid) begin
                stage1_ihl <= m_ipv4_ihl; 
                
                // Synthesis-safe, explicitly widened 32-bit adder tree
                stage1_sum <= 
                    {16'd0, {4'h4, m_ipv4_ihl, m_ipv4_dscp_ecn}} +
                    {16'd0, m_ipv4_total_length} +
                    {16'd0, m_ipv4_identification} +
                    {16'd0, {m_ipv4_flags, m_ipv4_fragment_offset}} +
                    {16'd0, {m_ipv4_ttl, m_ipv4_protocol}} +
                    {16'd0, m_ipv4_header_checksum} +
                    {16'd0, m_ipv4_src_ip[31:16]} +
                    {16'd0, m_ipv4_src_ip[15:0]} +
                    {16'd0, m_ipv4_dst_ip[31:16]} +
                    {16'd0, m_ipv4_dst_ip[15:0]};
            end
        end
    end

    // =========================================================================
    // STAGE 2: First Fold (32-bit to 17-bit)
    // =========================================================================
    reg [16:0] stage2_fold;
    reg        stage2_valid;
    reg [3:0]  stage2_ihl; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage2_fold  <= 17'd0;
            stage2_valid <= 1'b0;
            stage2_ihl   <= 4'd0;
        end else begin
            stage2_valid <= stage1_valid;
            stage2_ihl   <= stage1_ihl;
            if (stage1_valid) begin
                stage2_fold <= stage1_sum[15:0] + stage1_sum[31:16];
            end
        end
    end

    // =========================================================================
    // STAGE 3: Final Math & Explicit State Evaluation
    // =========================================================================
    wire [15:0] final_checksum = stage2_fold[15:0] + stage2_fold[16]; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ipv4_csum_ok          <= 1'b0;
            ipv4_csum_error       <= 1'b0;
            ipv4_csum_unsupported <= 1'b0;
        end else begin
            ipv4_csum_ok          <= 1'b0;
            ipv4_csum_error       <= 1'b0;
            ipv4_csum_unsupported <= 1'b0;
            
            if (stage2_valid) begin
                if (stage2_ihl < 4'h5) begin
                    ipv4_csum_error <= 1'b1;
                end 
                else if (stage2_ihl > 4'h5) begin
                    ipv4_csum_unsupported <= 1'b1;
                end 
                else begin
                    if (final_checksum == 16'hFFFF)
                        ipv4_csum_ok <= 1'b1;
                    else
                        ipv4_csum_error <= 1'b1;
                end
            end
        end
    end

endmodule