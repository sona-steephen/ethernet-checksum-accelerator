`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 17.08.2026 18:05:05
// Design Name: 
// Module Name: tb_tx_crc
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

module tb_tx_crc;

    // ============================================================
    // CLOCK / RESET
    // ============================================================

    reg tx_clk;
    reg tx_rst;

    initial begin
        tx_clk = 1'b0;
        forever #5 tx_clk = ~tx_clk;       // 100 MHz
    end


    // ============================================================
    // AXI-STREAM INPUT
    // ============================================================

    reg  [7:0] s_axis_tdata;
    reg        s_axis_tvalid;
    reg        s_axis_tlast;
    wire       s_axis_tready;


    // ============================================================
    // GMII OUTPUT
    // ============================================================

    wire [7:0] gmii_txd;
    wire       gmii_tx_en;


    // ============================================================
    // DUT
    // ============================================================

    tx_crc dut (
        .tx_clk        (tx_clk),
        .tx_rst        (tx_rst),

        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tlast  (s_axis_tlast),
        .s_axis_tready (s_axis_tready),

        .gmii_txd      (gmii_txd),
        .gmii_tx_en    (gmii_tx_en)
    );


    // ============================================================
    // 41-BYTE PAYLOAD
    //
    // 123456789ABCDEF23234899534789123456795678
    // ============================================================

    reg [7:0] payload [0:40];

    integer i;

    initial begin

        payload[0]  = "1";
        payload[1]  = "2";
        payload[2]  = "3";
        payload[3]  = "4";
        payload[4]  = "5";
        payload[5]  = "6";
        payload[6]  = "7";
        payload[7]  = "8";
        payload[8]  = "9";

        payload[9]  = "A";
        payload[10] = "B";
        payload[11] = "C";
        payload[12] = "D";
        payload[13] = "E";
        payload[14] = "F";

        payload[15] = "2";
        payload[16] = "3";
        payload[17] = "2";
        payload[18] = "3";
        payload[19] = "4";
        payload[20] = "8";
        payload[21] = "9";
        payload[22] = "9";
        payload[23] = "5";

        payload[24] = "3";
        payload[25] = "4";
        payload[26] = "7";
        payload[27] = "8";
        payload[28] = "9";
        payload[29] = "1";
        payload[30] = "2";
        payload[31] = "3";
        payload[32] = "4";
        payload[33] = "5";
        payload[34] = "6";
        payload[35] = "7";

        payload[36] = "9";
        payload[37] = "5";
        payload[38] = "6";
        payload[39] = "7";
        payload[40] = "8";

    end


    // ============================================================
    // EXPECTED FCS
    //
    // CRC = 65282B22
    // Ethernet FCS = 22 2B 28 65
    // ============================================================

    localparam [31:0] EXPECTED_CRC = 32'h65282B22;

    reg [7:0] expected_fcs [0:3];

    initial begin
        expected_fcs[0] = 8'h22;
        expected_fcs[1] = 8'h2B;
        expected_fcs[2] = 8'h28;
        expected_fcs[3] = 8'h65;
    end


    // ============================================================
    // MONITOR VARIABLES
    // ============================================================

    integer gmii_count;
    integer preamble_count;
    integer payload_count;
    integer fcs_count;
    integer error_count;

    reg [7:0] received_fcs [0:3];


    // ============================================================
    // RESET
    // ============================================================

    initial begin

        tx_rst        = 1'b1;

        s_axis_tdata  = 8'h00;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;

        gmii_count    = 0;
        preamble_count = 0;
        payload_count = 0;
        fcs_count     = 0;
        error_count   = 0;

        repeat (5) @(posedge tx_clk);

        tx_rst = 1'b0;

    end


    // ============================================================
    // SEND COMPLETE AXI PACKET
    //
    // IMPORTANT:
    // tvalid remains HIGH continuously.
    // One payload byte is transferred per clock.
    // ============================================================

    task send_packet;

        begin

            // --------------------------------------------
            // Wait until TX enters PAYLOAD state
            // --------------------------------------------

            @(negedge tx_clk);

            while (!s_axis_tready) begin
                @(negedge tx_clk);
            end


            // --------------------------------------------
            // Send 41 bytes continuously
            // --------------------------------------------

            s_axis_tvalid = 1'b1;

            for (i = 0; i < 41; i = i + 1) begin

                s_axis_tdata = payload[i];

                if (i == 40)
                    s_axis_tlast = 1'b1;
                else
                    s_axis_tlast = 1'b0;

                // One AXI transfer per rising edge
                @(posedge tx_clk);

                // Change data for next transfer
                @(negedge tx_clk);

            end


            // --------------------------------------------
            // End AXI stream
            // --------------------------------------------

            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
            s_axis_tdata  = 8'h00;

        end

    endtask


    // ============================================================
    // GMII MONITOR
    //
    // Count only GMII cycles where tx_en = 1.
    // ============================================================

    always @(posedge tx_clk) begin

        if (!tx_rst) begin

            if (gmii_tx_en) begin

                $display(
                    "[GMII] time=%0t data=%02h",
                    $time,
                    gmii_txd
                );


                // =================================================
                // PREAMBLE
                // =================================================

                if (preamble_count < 7) begin

                    if (gmii_txd !== 8'h55) begin

                        $display(
                            "ERROR: Preamble byte %0d expected 55, got %02h",
                            preamble_count,
                            gmii_txd
                        );

                        error_count = error_count + 1;

                    end

                    preamble_count = preamble_count + 1;

                end


                // =================================================
                // SFD
                // =================================================

                else if (preamble_count == 7) begin

                    if (gmii_txd !== 8'hD5) begin

                        $display(
                            "ERROR: SFD expected D5, got %02h",
                            gmii_txd
                        );

                        error_count = error_count + 1;

                    end

                    preamble_count = 8;

                end


                // =================================================
                // PAYLOAD
                // =================================================

                else if (payload_count < 41) begin

                    if (gmii_txd !== payload[payload_count]) begin

                        $display(
                            "ERROR: Payload byte %0d expected=%02h actual=%02h",
                            payload_count,
                            payload[payload_count],
                            gmii_txd
                        );

                        error_count = error_count + 1;

                    end

                    payload_count = payload_count + 1;

                end


                // =================================================
                // FCS
                // =================================================

                else if (fcs_count < 4) begin

                    received_fcs[fcs_count] = gmii_txd;

                    if (gmii_txd !== expected_fcs[fcs_count]) begin

                        $display(
                            "ERROR: FCS byte %0d expected=%02h actual=%02h",
                            fcs_count,
                            expected_fcs[fcs_count],
                            gmii_txd
                        );

                        error_count = error_count + 1;

                    end

                    fcs_count = fcs_count + 1;

                end


                // =================================================
                // EXTRA DATA
                // =================================================

                else begin

                    $display(
                        "ERROR: Extra GMII byte = %02h",
                        gmii_txd
                    );

                    error_count = error_count + 1;

                end

            end

        end

    end


    // ============================================================
    // MAIN TEST
    // ============================================================

    initial begin

        wait (tx_rst == 1'b0);

        $display("");
        $display("====================================================");
        $display("          TX CRC LONG PAYLOAD TEST");
        $display("====================================================");

        $display("");
        $display("Payload:");
        $display(
            "123456789ABCDEF23234899534789123456795678"
        );

        $display("");
        $display("Payload length = 41 bytes");

        $display("");
        $display("Expected CRC = %08h", EXPECTED_CRC);

        $display(
            "Expected FCS = %02h %02h %02h %02h",
            expected_fcs[0],
            expected_fcs[1],
            expected_fcs[2],
            expected_fcs[3]
        );

        $display("");
        $display("[TB] Sending 41-byte AXI payload...");


        // ========================================================
        // SEND PACKET
        // ========================================================

        send_packet();


        // ========================================================
        // WAIT FOR FCS
        // ========================================================

        repeat (8) @(posedge tx_clk);


        // ========================================================
        // FINAL CHECKS
        // ========================================================

        $display("");
        $display("====================================================");
        $display("                 FINAL CHECKS");
        $display("====================================================");


        // --------------------------------------------------------
        // Preamble + SFD
        // --------------------------------------------------------

        if (preamble_count == 8) begin

            $display(
                "PASS: Preamble + SFD transmitted correctly"
            );

        end
        else begin

            $display(
                "FAIL: Preamble/SFD count = %0d",
                preamble_count
            );

            error_count = error_count + 1;

        end


        // --------------------------------------------------------
        // Payload
        // --------------------------------------------------------

        if (payload_count == 41) begin

            $display(
                "PASS: Payload bytes = %0d",
                payload_count
            );

        end
        else begin

            $display(
                "FAIL: Payload byte count expected 41, got %0d",
                payload_count
            );

            error_count = error_count + 1;

        end


        // --------------------------------------------------------
        // FCS
        // --------------------------------------------------------

        if (fcs_count == 4) begin

            $display(
                "PASS: FCS bytes = %0d",
                fcs_count
            );

        end
        else begin

            $display(
                "FAIL: FCS byte count expected 4, got %0d",
                fcs_count
            );

            error_count = error_count + 1;

        end


        // --------------------------------------------------------
        // Display FCS
        // --------------------------------------------------------

        $display(
            "Received FCS = %02h %02h %02h %02h",
            received_fcs[0],
            received_fcs[1],
            received_fcs[2],
            received_fcs[3]
        );


        // ========================================================
        // OVERALL RESULT
        // ========================================================

        $display("");
        $display("====================================================");

        if (error_count == 0) begin

            $display(
                "       TX LONG PAYLOAD TEST PASSED"
            );

        end
        else begin

            $display(
                "       TX LONG PAYLOAD TEST FAILED"
            );

            $display(
                "       Total errors = %0d",
                error_count
            );

        end

        $display("====================================================");
        $display("");

        $finish;

    end

endmodule