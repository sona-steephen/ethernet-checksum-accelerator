`timescale 1ns / 1ps

module tb_tx_csum_top;

    reg clk;
    reg rst_n;

    reg  [7:0]   s_axis_tdata;
    reg          s_axis_tvalid;
    wire         s_axis_tready;
    reg          s_axis_tlast;
    reg  [127:0] s_axis_tuser;

    wire [7:0]   m_axis_tdata;
    wire         m_axis_tvalid;
    reg          m_axis_tready;
    wire         m_axis_tlast;

    reg [7:0] packet [0:62];
    reg [7:0] received [0:62];

    integer i;
    integer rx_count;

    tx_csum_top dut (
        .clk(clk),
        .rst_n(rst_n),

        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tuser(s_axis_tuser),

        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );


    // ================================================================
    // CLOCK
    // ================================================================

    always #5 clk = ~clk;


    // ================================================================
    // TEST
    // ================================================================

    initial begin

        clk = 0;
        rst_n = 0;

        s_axis_tdata  = 0;
        s_axis_tvalid = 0;
        s_axis_tlast  = 0;
        s_axis_tuser  = 0;

        m_axis_tready = 1;


        // Reset
        #20;
        rst_n = 1;

        // ------------------------------------------------------------
        // VLAN + IPv4 + TCP + 5 BYTE PAYLOAD
        //
        // Total:
        // 14 Ethernet
        //  4 VLAN
        // 20 IPv4
        // 20 TCP
        //  5 payload
        // =63 bytes
        // ------------------------------------------------------------

        // Ethernet destination
        packet[0]  = 8'h00;
        packet[1]  = 8'h11;
        packet[2]  = 8'h22;
        packet[3]  = 8'h33;
        packet[4]  = 8'h44;
        packet[5]  = 8'h55;

        // Ethernet source
        packet[6]  = 8'h66;
        packet[7]  = 8'h77;
        packet[8]  = 8'h88;
        packet[9]  = 8'h99;
        packet[10] = 8'hAA;
        packet[11] = 8'hBB;

        // VLAN
        packet[12] = 8'h81;
        packet[13] = 8'h00;
        packet[14] = 8'h00;
        packet[15] = 8'h0A;

        // IPv4 EtherType
        packet[16] = 8'h08;
        packet[17] = 8'h00;


        // ============================================================
        // IPv4 HEADER
        // Offset = 18
        // ============================================================

        packet[18] = 8'h45;
        packet[19] = 8'h00;

        // Total IP length = 20 + 20 + 5 = 45 = 0x002D
        packet[20] = 8'h00;
        packet[21] = 8'h2D;

        packet[22] = 8'h00;
        packet[23] = 8'h00;

        packet[24] = 8'h40;
        packet[25] = 8'h00;

        // TTL
        packet[26] = 8'h40;

        // TCP
        packet[27] = 8'h06;

        // IP checksum = zero initially
        packet[28] = 8'h00;
        packet[29] = 8'h00;

        // Source IP = 192.168.1.1
        packet[30] = 8'hC0;
        packet[31] = 8'hA8;
        packet[32] = 8'h01;
        packet[33] = 8'h01;

        // Destination IP = 192.168.1.2
        packet[34] = 8'hC0;
        packet[35] = 8'hA8;
        packet[36] = 8'h01;
        packet[37] = 8'h02;


        // ============================================================
        // TCP HEADER
        // Offset = 38
        // ============================================================

        // Source port = 1234
        packet[38] = 8'h04;
        packet[39] = 8'hD2;

        // Destination port = 80
        packet[40] = 8'h00;
        packet[41] = 8'h50;

        // Sequence number
        packet[42] = 8'h00;
        packet[43] = 8'h00;
        packet[44] = 8'h00;
        packet[45] = 8'h00;

        // Acknowledgment number
        packet[46] = 8'h00;
        packet[47] = 8'h00;
        packet[48] = 8'h00;
        packet[49] = 8'h00;

        // Data offset = 5, SYN
        packet[50] = 8'h50;
        packet[51] = 8'h02;

        // Window
        packet[52] = 8'h20;
        packet[53] = 8'h00;

        // TCP checksum = zero initially
        packet[54] = 8'h00;
        packet[55] = 8'h00;

        // Urgent pointer
        packet[56] = 8'h00;
        packet[57] = 8'h00;


        // ============================================================
        // ODD-LENGTH TCP PAYLOAD = "HELLO"
        // ============================================================

        packet[58] = 8'h48; // H
        packet[59] = 8'h45; // E
        packet[60] = 8'h4C; // L
        packet[61] = 8'h4C; // L
        packet[62] = 8'h4F; // O


        // ============================================================
        // TUSER
        // ============================================================

        s_axis_tuser = 128'd0;

        // IPv4
        s_axis_tuser[0] = 1'b1;

        // IP checksum enable
        s_axis_tuser[1] = 1'b1;

        // TCP checksum enable
        s_axis_tuser[2] = 1'b1;

        // TCP
        s_axis_tuser[10:3] = 8'h06;

        // L3 offset = 18
        s_axis_tuser[18:11] = 8'd18;

        // IP header length = 20
        s_axis_tuser[26:19] = 8'd20;

        // TCP offset = 38
        s_axis_tuser[34:27] = 8'd38;

        // TCP header length = 20
        s_axis_tuser[42:35] = 8'd20;

        // TCP length = 20 header + 5 payload
        s_axis_tuser[58:43] = 16'd25;

        // Source IP
        s_axis_tuser[90:59] = 32'hC0A80101;

        // Destination IP
        s_axis_tuser[122:91] = 32'hC0A80102;


        // ============================================================
        // SEND PACKET
        // ============================================================

        $display("\n==============================================");
        $display("TEST: VLAN + IPv4 + TCP + ODD PAYLOAD");
        $display("==============================================");

        for (i = 0; i < 63; i = i + 1) begin

            while (!s_axis_tready)
                @(posedge clk);

            s_axis_tdata  = packet[i];
            s_axis_tvalid = 1'b1;

            if (i == 62)
                s_axis_tlast = 1'b1;
            else
                s_axis_tlast = 1'b0;

            @(posedge clk);

        end


        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        s_axis_tdata  = 8'h00;


        // ============================================================
        // RECEIVE PACKET
        // ============================================================

        rx_count = 0;

        while (rx_count < 63) begin

            @(posedge clk);

            if (m_axis_tvalid && m_axis_tready) begin

                received[rx_count] = m_axis_tdata;

                rx_count = rx_count + 1;

                if (m_axis_tlast)
                    $display("[INFO] Packet transmission complete.");

            end

        end


        // ============================================================
        // DISPLAY RESULT
        // ============================================================

        $display("\n--- EGRESS PACKET ---");

        for (i = 0; i < 63; i = i + 1) begin

            if (i % 16 == 0 && i != 0)
                $write("\n");

            if ((i == 28) || (i == 29) ||
                (i == 54) || (i == 55))
                $write(">>%02X<< ", received[i]);
            else
                $write("%02X ", received[i]);

        end

        $write("\n");


        // ============================================================
        // CHECK CHECKSUM FIELDS
        // ============================================================

        $display("\n--- CHECKSUM RESULTS ---");

        $display("IP checksum   = 0x%02X%02X",
                 received[28],
                 received[29]);

        $display("TCP checksum  = 0x%02X%02X",
                 received[54],
                 received[55]);


        // ============================================================
        // CHECK PAYLOAD
        // ============================================================

        if ((received[58] == 8'h48) &&
            (received[59] == 8'h45) &&
            (received[60] == 8'h4C) &&
            (received[61] == 8'h4C) &&
            (received[62] == 8'h4F)) begin

            $display("Payload       = HELLO [PASS]");

        end
        else begin

            $display("Payload       = ERROR [FAIL]");

        end


        // ============================================================
        // CHECK NON-CHECKSUM BYTES
        // ============================================================

        for (i = 0; i < 63; i = i + 1) begin

            if ((i != 28) && (i != 29) &&
                (i != 54) && (i != 55)) begin

                if (received[i] !== packet[i])
                    $display("DATA ERROR at byte %0d", i);

            end

        end


        $display("\n==============================================");
        $display("ODD-LENGTH PAYLOAD TEST COMPLETE");
        $display("==============================================");

        #100;

        $finish;

    end

endmodule