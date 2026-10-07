`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 17.08.2026 13:01:11
// Design Name: 
// Module Name: tb_rx_crc
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


`timescale 1ns/1ps

`timescale 1ns/1ps

module tb_rx_crc;

    // ============================================================
    // Clock and Reset
    // ============================================================

    reg rx_clk;
    reg rx_rst;

    initial begin
        rx_clk = 1'b0;
        forever #5 rx_clk = ~rx_clk;       // 100 MHz
    end


    // ============================================================
    // GMII Interface
    // ============================================================

    reg [7:0] gmii_rxd;
    reg       gmii_rx_dv;


    // ============================================================
    // AXI4-Stream Interface
    // ============================================================

    wire [7:0] m_axis_tdata;
    wire       m_axis_tvalid;
    wire       m_axis_tlast;
    wire       m_axis_tuser;

    reg        m_axis_tready;


    // ============================================================
    // DUT
    // ============================================================

    rx_crc dut (
        .rx_clk        (rx_clk),
        .rx_rst        (rx_rst),

        .gmii_rxd      (gmii_rxd),
        .gmii_rx_dv    (gmii_rx_dv),

        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tlast  (m_axis_tlast),
        .m_axis_tuser  (m_axis_tuser),

        .m_axis_tready (m_axis_tready)
    );


    // ============================================================
    // Expected Payload
    //
    // ASCII:
    // "123456789"
    //
    // 31 32 33 34 35 36 37 38 39
    // ============================================================

    reg [7:0] expected_payload [0:8];

    reg [7:0] expected_fcs [0:3];

    integer i;


    initial begin

        expected_payload[0] = 8'h31;
        expected_payload[1] = 8'h32;
        expected_payload[2] = 8'h33;
        expected_payload[3] = 8'h34;
        expected_payload[4] = 8'h35;
        expected_payload[5] = 8'h36;
        expected_payload[6] = 8'h37;
        expected_payload[7] = 8'h38;
        expected_payload[8] = 8'h39;

        // Ethernet FCS
        expected_fcs[0] = 8'h26;
        expected_fcs[1] = 8'h39;
        expected_fcs[2] = 8'hF4;
        expected_fcs[3] = 8'hCB;

    end


    // ============================================================
    // Test Variables
    // ============================================================

    integer axi_count;
    integer error_count;

    reg saw_tlast;
    reg [7:0] last_axi_byte;


    // ============================================================
    // Reset
    // ============================================================

    initial begin

        rx_rst         = 1'b1;

        gmii_rxd       = 8'h00;
        gmii_rx_dv     = 1'b0;

        // For this design/test:
        // AXI receiver is always ready.
        m_axis_tready  = 1'b1;

        axi_count      = 0;
        error_count    = 0;
        saw_tlast      = 1'b0;
        last_axi_byte  = 8'h00;

        repeat (5) @(posedge rx_clk);

        rx_rst = 1'b0;

    end


    // ============================================================
    // GMII BYTE TRANSMISSION
    //
    // IMPORTANT:
    // One byte is presented for exactly ONE clock cycle.
    // ============================================================

    task send_gmii_byte;

        input [7:0] data;

        begin

            @(negedge rx_clk);

            gmii_rxd   = data;
            gmii_rx_dv = 1'b1;

        end

    endtask


    // ============================================================
    // End GMII Frame
    // ============================================================

    task end_frame;

        begin

            @(negedge rx_clk);

            gmii_rxd   = 8'h00;
            gmii_rx_dv = 1'b0;

        end

    endtask


    // ============================================================
    // AXI MONITOR
    // ============================================================

    always @(posedge rx_clk) begin

        if (!rx_rst) begin

            if (m_axis_tvalid && m_axis_tready) begin

                $display(
                    "[AXI] time=%0t data=%02h tlast=%b tuser=%b",
                    $time,
                    m_axis_tdata,
                    m_axis_tlast,
                    m_axis_tuser
                );


                // ------------------------------------------------
                // Check AXI payload
                // ------------------------------------------------

                if (axi_count < 9) begin

                    if (m_axis_tdata !== expected_payload[axi_count]) begin

                        $display(
                            "ERROR: AXI byte %0d: expected=%02h actual=%02h",
                            axi_count,
                            expected_payload[axi_count],
                            m_axis_tdata
                        );

                        error_count = error_count + 1;

                    end

                end
                else begin

                    $display(
                        "ERROR: Extra AXI transfer: data=%02h",
                        m_axis_tdata
                    );

                    error_count = error_count + 1;

                end


                // ------------------------------------------------
                // Good frame -> TUSER must be 0
                // ------------------------------------------------

                if (m_axis_tuser !== 1'b0) begin

                    $display(
                        "ERROR: TUSER asserted unexpectedly"
                    );

                    error_count = error_count + 1;

                end


                // ------------------------------------------------
                // TLAST
                // ------------------------------------------------

                if (m_axis_tlast) begin

                    saw_tlast = 1'b1;

                    if (m_axis_tdata !== 8'h39) begin

                        $display(
                            "ERROR: TLAST on wrong byte. Expected 39, got %02h",
                            m_axis_tdata
                        );

                        error_count = error_count + 1;

                    end

                end


                last_axi_byte = m_axis_tdata;

                axi_count = axi_count + 1;

            end

        end

    end


    // ============================================================
    // MAIN TEST
    // ============================================================

    initial begin

        wait (rx_rst == 1'b0);

        $display("");
        $display("====================================================");
        $display("           RX CRC GOOD FRAME TEST");
        $display("====================================================");


        // ========================================================
        // 1. Ethernet PREAMBLE
        // ========================================================

        $display("[TB] Sending 7-byte preamble...");

        for (i = 0; i < 7; i = i + 1) begin

            send_gmii_byte(8'h55);

        end


        // ========================================================
        // 2. SFD
        // ========================================================

        $display("[TB] Sending SFD = D5");

        send_gmii_byte(8'hD5);


        // ========================================================
        // 3. PAYLOAD
        // ========================================================

        $display("[TB] Sending payload = 123456789");

        for (i = 0; i < 1; i = i + 1) begin

            send_gmii_byte(expected_payload[i]);

        end


        // ========================================================
        // 4. FCS
        // ========================================================

        $display("[TB] Sending FCS = 26 39 F4 CB");

        for (i = 0; i < 4; i = i + 1) begin

            send_gmii_byte(expected_fcs[i]);

        end


        // ========================================================
        // 5. End of Frame
        // ========================================================

        $display("[TB] Ending frame...");

        end_frame();


        // Give DUT enough time to generate final AXI output
        repeat (5) @(posedge rx_clk);


        // ========================================================
        // FINAL CHECKS
        // ========================================================

        $display("");
        $display("====================================================");
        $display("                 FINAL CHECKS");
        $display("====================================================");


        // --------------------------------------------------------
        // Check CRC residue
        // --------------------------------------------------------

        if (dut.crc_reg === 32'hDEBB20E3) begin

            $display(
                "PASS: CRC residue = %08h",
                dut.crc_reg
            );

        end
        else begin

            $display(
                "FAIL: CRC residue expected DEBB20E3, got %08h",
                dut.crc_reg
            );

            error_count = error_count + 1;

        end


        // --------------------------------------------------------
        // Check AXI transfer count
        // --------------------------------------------------------

        if (axi_count == 9) begin

            $display(
                "PASS: AXI transfer count = %0d",
                axi_count
            );

        end
        else begin

            $display(
                "FAIL: AXI transfer count expected 9, got %0d",
                axi_count
            );

            error_count = error_count + 1;

        end


        // --------------------------------------------------------
        // Check TLAST
        // --------------------------------------------------------

        if (saw_tlast) begin

            $display("PASS: TLAST detected");

        end
        else begin

            $display("FAIL: TLAST not detected");

            error_count = error_count + 1;

        end


        // --------------------------------------------------------
        // Check final payload byte
        // --------------------------------------------------------

        if (last_axi_byte === 8'h39) begin

            $display(
                "PASS: Last AXI byte = %02h",
                last_axi_byte
            );

        end
        else begin

            $display(
                "FAIL: Last AXI byte expected 39, got %02h",
                last_axi_byte
            );

            error_count = error_count + 1;

        end


        // ========================================================
        // Overall Result
        // ========================================================

        $display("");
        $display("====================================================");

        if (error_count == 0) begin

            $display("             RX CRC TEST PASSED");

        end
        else begin

            $display(
                "             RX CRC TEST FAILED"
            );

            $display(
                "             Total errors = %0d",
                error_count
            );

        end

        $display("====================================================");
        $display("");

        $finish;

    end

endmodule
