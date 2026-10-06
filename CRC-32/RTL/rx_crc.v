`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.08.2026 14:36:30
// Design Name: 
// Module Name: rx_crc
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


module rx_crc (
    input  wire        rx_clk,
    input  wire        rx_rst,

    // ============================================================
    // GMII RX INPUT
    // ============================================================
    input  wire [7:0]  gmii_rxd,
    input  wire        gmii_rx_dv,

    // ============================================================
    // AXI4-STREAM OUTPUT
    // ============================================================
    output reg  [7:0]  m_axis_tdata,
    output reg         m_axis_tvalid,
    output reg         m_axis_tlast,

    // 0 = CRC PASS
    // 1 = CRC FAIL / PACKET ERROR
    output reg         m_axis_tuser,

    input  wire        m_axis_tready
);

    // ============================================================
    // FSM STATES
    // ============================================================

    localparam STATE_IDLE    = 3'd0;
    localparam STATE_PREAMBLE = 3'd1;
    localparam STATE_SFD     = 3'd2;
    localparam STATE_PAYLOAD = 3'd3;

    // ============================================================
    // ETHERNET CRC-32 RESIDUE
    // ============================================================

    localparam CRC_RESIDUE = 32'hDEBB20E3;

    // Initial CRC value
    localparam CRC_INIT = 32'hFFFFFFFF;

    // ============================================================
    // INTERNAL REGISTERS
    // ============================================================

    reg [2:0]  state;
    reg [3:0]  preamble_cnt;

    // CRC state
    reg [31:0] crc_reg;

    // ============================================================
    // FIVE-BYTE BUFFER
    //
    // Purpose:
    // Keep the last 4 bytes as FCS.
    // One additional byte is retained as the final payload byte.
    //
    // At the end of the frame:
    //
    // buffer[0] = final payload byte
    // buffer[1] = FCS byte 0
    // buffer[2] = FCS byte 1
    // buffer[3] = FCS byte 2
    // buffer[4] = FCS byte 3
    // ============================================================

    reg [7:0] data_buf [0:4];

    // Number of bytes received after SFD
    reg [3:0] rx_byte_count;

    // ============================================================
    // CRC PARALLEL CORE
    // ============================================================

    wire [31:0] next_crc_wire;

    crc32_8bit_parallel u_crc_math (
        .current_crc(crc_reg),
        .data_in    (gmii_rxd),
        .next_crc   (next_crc_wire)
    );

    // ============================================================
    // MAIN RX FSM
    // ============================================================

    always @(posedge rx_clk) begin

        if (rx_rst) begin

            state         <= STATE_IDLE;
            preamble_cnt  <= 4'd0;

            crc_reg       <= CRC_INIT;

            rx_byte_count <= 4'd0;

            data_buf[0]   <= 8'h00;
            data_buf[1]   <= 8'h00;
            data_buf[2]   <= 8'h00;
            data_buf[3]   <= 8'h00;
            data_buf[4]   <= 8'h00;

            m_axis_tdata  <= 8'h00;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            m_axis_tuser  <= 1'b0;

        end
        else begin

            // ====================================================
            // DEFAULT AXI OUTPUTS
            // ====================================================

            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            m_axis_tuser  <= 1'b0;


            // ====================================================
            // FRAME END
            //
            // gmii_rx_dv falling edge means the complete frame
            // including the 4-byte FCS has been received.
            // ====================================================

            if (!gmii_rx_dv) begin

                if (state == STATE_PAYLOAD) begin

                    // ------------------------------------------------
                    // The five-byte buffer contains:
                    //
                    // buffer[0] = FINAL PAYLOAD BYTE
                    // buffer[1] = FCS[0]
                    // buffer[2] = FCS[1]
                    // buffer[3] = FCS[2]
                    // buffer[4] = FCS[3]
                    //
                    // Therefore only buffer[0] is forwarded.
                    // ------------------------------------------------

                    if (rx_byte_count >= 5) begin

                        m_axis_tdata  <= data_buf[0];
                        m_axis_tvalid <= 1'b1;
                        m_axis_tlast  <= 1'b1;

                        // ------------------------------------------------
                        // CRC register has already processed the
                        // complete payload + 4-byte FCS.
                        // ------------------------------------------------

                        if (crc_reg == CRC_RESIDUE)
                            m_axis_tuser <= 1'b0;
                        else
                            m_axis_tuser <= 1'b1;

                    end

                end

                // Return to idle after frame
                state         <= STATE_IDLE;
                preamble_cnt  <= 4'd0;
                rx_byte_count <= 4'd0;

            end

            // ====================================================
            // GMII RX ACTIVE
            // ====================================================

            else begin

                case (state)

                    // =================================================
                    // IDLE
                    // =================================================

                    STATE_IDLE: begin

                        crc_reg       <= CRC_INIT;
                        rx_byte_count <= 4'd0;

                        if (gmii_rxd == 8'h55) begin

                            state        <= STATE_PREAMBLE;
                            preamble_cnt <= 4'd1;

                        end

                    end


                    // =================================================
                    // PREAMBLE
                    //
                    // Ethernet preamble = 7 x 55
                    //
                    // We allow >=7 consecutive 55 bytes before D5.
                    // This makes the detector tolerant to the extra
                    // 55 observed in the previous simulation trace.
                    // =================================================

                    STATE_PREAMBLE: begin

                        crc_reg <= CRC_INIT;

                        if (gmii_rxd == 8'h55) begin

                            if (preamble_cnt < 4'd7)
                                preamble_cnt <= preamble_cnt + 1'b1;
                            else
                                preamble_cnt <= preamble_cnt;

                        end

                        else if ((gmii_rxd == 8'hD5) &&
                                 (preamble_cnt >= 4'd7)) begin

                            // Correct SFD detected
                            state         <= STATE_PAYLOAD;
                            crc_reg       <= CRC_INIT;
                            rx_byte_count <= 4'd0;

                        end

                        else begin

                            // Invalid preamble
                            state        <= STATE_IDLE;
                            preamble_cnt <= 4'd0;

                        end

                    end


                    // =================================================
                    // PAYLOAD + FCS
                    //
                    // CRC is calculated over:
                    //
                    //     PAYLOAD + FCS
                    //
                    // The final CRC must equal DEBB20E3.
                    // =================================================

                    STATE_PAYLOAD: begin

                        // ------------------------------------------------
                        // CRC update
                        // ------------------------------------------------

                        crc_reg <= next_crc_wire;


                        // ------------------------------------------------
                        // Shift five-byte buffer
                        // ------------------------------------------------

                        data_buf[0] <= data_buf[1];
                        data_buf[1] <= data_buf[2];
                        data_buf[2] <= data_buf[3];
                        data_buf[3] <= data_buf[4];
                        data_buf[4] <= gmii_rxd;


                        // ------------------------------------------------
                        // Once 5 bytes have been received, the oldest
                        // byte is guaranteed to be payload rather than
                        // one of the final 4 FCS bytes.
                        //
                        // Therefore output data_buf[0].
                        // ------------------------------------------------

                        if (rx_byte_count >= 5) begin

                            if (m_axis_tready) begin

                                m_axis_tdata  <= data_buf[0];
                                m_axis_tvalid <= 1'b1;
                                m_axis_tlast  <= 1'b0;
                                m_axis_tuser  <= 1'b0;

                            end

                        end


                        // ------------------------------------------------
                        // Increment byte count
                        // ------------------------------------------------

                        if (rx_byte_count < 15)
                            rx_byte_count <= rx_byte_count + 1'b1;

                    end


                    // =================================================
                    // DEFAULT
                    // =================================================

                    default: begin

                        state         <= STATE_IDLE;
                        preamble_cnt  <= 4'd0;
                        rx_byte_count <= 4'd0;
                        crc_reg       <= CRC_INIT;

                    end

                endcase

            end

        end

    end

endmodule