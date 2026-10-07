`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 31.08.2026 11:47:32
// Design Name: 
// Module Name: tb_rx_cso_top
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

module tb_rx_cso_top();

    // =========================================================================
    // 1. SYSTEM SIGNALS
    // =========================================================================
    reg clk;
    reg rst_n;
    
    // 100MHz Clock (10ns period)
    always #5 clk = ~clk;

    // =========================================================================
    // 2. DUT INPUT REGISTERS
    // =========================================================================
    // IPv4 Interface
    reg         m_ipv4_valid;
    reg  [31:0] m_ipv4_src_ip;
    reg  [31:0] m_ipv4_dst_ip;
    reg  [7:0]  m_ipv4_protocol;
    reg  [15:0] m_ipv4_total_length;
    reg  [3:0]  m_ipv4_ihl;
    reg  [7:0]  m_ipv4_dscp_ecn;
    reg  [15:0] m_ipv4_identification;
    reg  [2:0]  m_ipv4_flags;
    reg  [12:0] m_ipv4_fragment_offset;
    reg  [7:0]  m_ipv4_ttl;
    reg  [15:0] m_ipv4_header_checksum;

    // TCP Interface
    reg         m_tcp_valid;
    reg  [15:0] m_tcp_src_port;
    reg  [15:0] m_tcp_dst_port;
    reg  [31:0] m_tcp_seq_num;
    reg  [31:0] m_tcp_ack_num;
    reg  [3:0]  m_tcp_data_offset;
    reg  [7:0]  m_tcp_flags;
    reg  [15:0] m_tcp_window;
    reg  [15:0] m_tcp_checksum;
    reg  [15:0] m_tcp_urg_ptr;

    // AXI-Stream Payload Interface
    reg  [7:0]  m_axis_tdata;
    reg         m_axis_tvalid;
    reg         m_axis_tlast;
    reg         m_axis_tuser;
    reg         m_axis_is_tcp_payload;

    // =========================================================================
    // 3. DUT OUTPUT WIRES
    // =========================================================================
    wire ipv4_csum_ok;
    wire ipv4_csum_error;
    wire ipv4_csum_unsupported;
    
    wire tcp_csum_ok;
    wire tcp_csum_error;
    wire tcp_csum_unsupported;

    // =========================================================================
    // 4. DUT INSTANTIATION
    // =========================================================================
    rx_cso_top uut (
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
        
        .m_tcp_valid            (m_tcp_valid), 
        .m_tcp_src_port         (m_tcp_src_port),
        .m_tcp_dst_port         (m_tcp_dst_port), 
        .m_tcp_seq_num          (m_tcp_seq_num),
        .m_tcp_ack_num          (m_tcp_ack_num), 
        .m_tcp_data_offset      (m_tcp_data_offset),
        .m_tcp_flags            (m_tcp_flags), 
        .m_tcp_window           (m_tcp_window),
        .m_tcp_checksum         (m_tcp_checksum), 
        .m_tcp_urg_ptr          (m_tcp_urg_ptr),
        
        .m_axis_tdata           (m_axis_tdata), 
        .m_axis_tvalid          (m_axis_tvalid),
        .m_axis_tlast           (m_axis_tlast), 
        .m_axis_tuser           (m_axis_tuser),
        .m_axis_is_tcp_payload  (m_axis_is_tcp_payload),
        
        .ipv4_csum_ok           (ipv4_csum_ok), 
        .ipv4_csum_error        (ipv4_csum_error), 
        .ipv4_csum_unsupported  (ipv4_csum_unsupported),
        .tcp_csum_ok            (tcp_csum_ok), 
        .tcp_csum_error         (tcp_csum_error), 
        .tcp_csum_unsupported   (tcp_csum_unsupported)
    );

    // =========================================================================
    // 5. STATUS LATCHES (To catch the 1-cycle pulses)
    // =========================================================================
    reg ip_ok_latch, tcp_ok_latch;
    reg ip_err_latch, tcp_err_latch;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            ip_ok_latch <= 0; ip_err_latch <= 0;
            tcp_ok_latch <= 0; tcp_err_latch <= 0;
        end else begin
            if (ipv4_csum_ok)    ip_ok_latch <= 1;
            if (ipv4_csum_error) ip_err_latch <= 1;
            if (tcp_csum_ok)     tcp_ok_latch <= 1;
            if (tcp_csum_error)  tcp_err_latch <= 1;
        end
    end

    // =========================================================================
    // 6. MAIN TEST STIMULUS
    // =========================================================================
    initial begin
        // Initialize everything to 0
        clk = 0; rst_n = 0;
        m_ipv4_valid = 0; m_tcp_valid = 0; 
        m_axis_tvalid = 0; m_axis_tlast = 0; m_axis_tuser = 0; m_axis_is_tcp_payload = 0;
        m_axis_tdata = 8'h00;
        
        $display("\n============================================================");
        $display("   RX CSO TEST: TC1 - THE GOLDEN PACKET");
        $display("============================================================\n");

        // Release Reset
        #20 rst_n = 1; 
        repeat(2) @(negedge clk);

        // ---------------------------------------------------------------------
        // PREPARE GOLDEN HEADER DATA (Valid 50-Byte Packet)
        // ---------------------------------------------------------------------
        m_ipv4_src_ip          = 32'hC0A80101; 
        m_ipv4_dst_ip          = 32'h0A000001; 
        m_ipv4_protocol        = 8'h06;
        m_ipv4_total_length    = 16'h0032; // 50 bytes total
        m_ipv4_ihl             = 4'h5;     // 20-byte IP header
        m_ipv4_dscp_ecn        = 8'h00; 
        m_ipv4_identification  = 16'h1234;
        m_ipv4_flags           = 3'b000; 
        m_ipv4_fragment_offset = 13'h0000; 
        m_ipv4_ttl             = 8'h40;
        m_ipv4_header_checksum = 16'h9CE8; // Perfect IP Checksum

        m_tcp_src_port         = 16'h1234; 
        m_tcp_dst_port         = 16'h0050; 
        m_tcp_seq_num          = 32'h00000001;
        m_tcp_ack_num          = 32'h00000002; 
        m_tcp_data_offset      = 4'h5;     // 20-byte TCP header
        m_tcp_flags            = 8'h18;
        m_tcp_window           = 16'h1000; 
        m_tcp_urg_ptr          = 16'h0000;
        m_tcp_checksum         = 16'h31AD; // Perfect TCP Checksum

        // ---------------------------------------------------------------------
        // STEP 1: TRIGGER HEADERS
        // ---------------------------------------------------------------------
        $display("[Time: %0t] Sending Valid IP and TCP Headers...", $time);
        @(negedge clk);
        m_ipv4_valid = 1; 
        m_tcp_valid  = 1; 
        
        @(negedge clk);
        m_ipv4_valid = 0; 
        m_tcp_valid  = 0;

        // ---------------------------------------------------------------------
        // STEP 2: STREAM 10-BYTE PAYLOAD
        // ---------------------------------------------------------------------
        $display("[Time: %0t] Streaming 10-Byte AXI Payload...", $time);
        m_axis_is_tcp_payload = 1; 
        m_axis_tvalid         = 1;
        
        m_axis_tdata = 8'hA1; @(negedge clk); 
        m_axis_tdata = 8'hB2; @(negedge clk);
        m_axis_tdata = 8'hC3; @(negedge clk); 
        m_axis_tdata = 8'hD4; @(negedge clk);
        m_axis_tdata = 8'hE5; @(negedge clk); 
        m_axis_tdata = 8'hF6; @(negedge clk);
        m_axis_tdata = 8'h11; @(negedge clk); 
        m_axis_tdata = 8'h22; @(negedge clk);
        m_axis_tdata = 8'h33; @(negedge clk); 
        
        // Final Byte + TLAST
        m_axis_tdata = 8'h44; 
        m_axis_tlast = 1; 
        @(negedge clk);
        
        // Turn off stream
        m_axis_tvalid = 0; 
        m_axis_tlast  = 0; 
        m_axis_is_tcp_payload = 0;
        
        // Wait a few cycles for combinational logic to fold and latch
        repeat(3) @(negedge clk);

        // ---------------------------------------------------------------------
        // STEP 3: VERIFY RESULTS
        // ---------------------------------------------------------------------
        $display("\n============================================================");
        $display("   RESULTS");
        $display("============================================================");

        // Check IPv4
        if (ip_ok_latch && !ip_err_latch) 
            $display(" [PASS] IPv4 Checksum OK");
        else 
            $display(" [FAIL] IPv4 Checksum ERROR (Expected OK)");

        // Check TCP
        if (tcp_ok_latch && !tcp_err_latch) 
            $display(" [PASS] TCP Checksum OK");
        else 
            $display(" [FAIL] TCP Checksum ERROR (Expected OK)");
            
        $display("============================================================\n");
        $finish;
    end

endmodule