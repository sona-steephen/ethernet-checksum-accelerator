`timescale 1ns / 1ps

/* =============================================================================
   MODULE: rx_tcp_csum

   FUNCTION:
   ---------
   Verifies the TCP checksum for IPv4/TCP packets.

   ARCHITECTURAL CONTRACTS:
   ------------------------
   1. m_tcp_valid identifies the beginning of a new TCP packet.

   2. m_tcp_valid may occur in the same cycle as the first payload byte.
      This implementation does NOT discard that first byte.

   3. The parser provides:
        - IPv4 pseudo-header information
        - TCP header fields
        - TCP payload through AXI-Stream

   4. TCP Data Offset:
        < 5  -> malformed TCP header -> tcp_csum_error
        = 5  -> hardware fast path
        > 5  -> TCP options -> tcp_csum_unsupported

   5. Zero-byte TCP payload:
        tcp_length == tcp_header_length
      The checksum is evaluated one cycle after m_tcp_valid.

   6. Payload stream:
        m_axis_tvalid && m_axis_is_tcp_payload
      indicates a valid TCP payload byte.

   7. m_axis_tlast indicates the final TCP payload byte.

   8. m_axis_tuser = 1 indicates a bad Ethernet CRC.
      For packets containing payload, this causes tcp_csum_error.

   9. Status outputs are one-clock-cycle pulses.

============================================================================= */

module rx_tcp_csum (

    // =========================================================================
    // CLOCK AND RESET
    // =========================================================================

    input  wire        clk,
    input  wire        rst_n,


    // =========================================================================
    // IPv4 PSEUDO HEADER INFORMATION
    // =========================================================================

    input  wire        m_tcp_valid,

    input  wire [31:0] m_ipv4_src_ip,
    input  wire [31:0] m_ipv4_dst_ip,
    input  wire [7:0]  m_ipv4_protocol,
    input  wire [15:0] m_ipv4_total_length,
    input  wire [3:0]  m_ipv4_ihl,


    // =========================================================================
    // TCP HEADER INFORMATION
    // =========================================================================

    input  wire [15:0] m_tcp_src_port,
    input  wire [15:0] m_tcp_dst_port,
    input  wire [31:0] m_tcp_seq_num,
    input  wire [31:0] m_tcp_ack_num,
    input  wire [3:0]  m_tcp_data_offset,
    input  wire [7:0]  m_tcp_flags,
    input  wire [15:0] m_tcp_window,
    input  wire [15:0] m_tcp_checksum,
    input  wire [15:0] m_tcp_urg_ptr,


    // =========================================================================
    // TCP PAYLOAD AXI-STREAM
    // =========================================================================

    input  wire [7:0]  m_axis_tdata,
    input  wire        m_axis_tvalid,
    input  wire        m_axis_tlast,
    input  wire        m_axis_tuser,
    input  wire        m_axis_is_tcp_payload,


    // =========================================================================
    // CHECKSUM STATUS OUTPUTS
    // =========================================================================

    output reg         tcp_csum_ok,
    output reg         tcp_csum_error,
    output reg         tcp_csum_unsupported

);


    // =========================================================================
    // STAGE 1
    // IPv4 HEADER LENGTH
    // TCP LENGTH
    // TCP HEADER LENGTH
    // =========================================================================

    /*
       IPv4 IHL is number of 32-bit words.

       Header length = IHL * 4 bytes.
    */

    wire [15:0] ipv4_header_length =
                    {10'd0, m_ipv4_ihl, 2'b00};


    /*
       TCP length = IPv4 total length - IPv4 header length.

       This includes:
           TCP header + TCP payload
    */

    wire [15:0] tcp_length =
                    m_ipv4_total_length - ipv4_header_length;


    /*
       TCP Data Offset is also number of 32-bit words.

       TCP header length = Data Offset * 4 bytes.
    */

    wire [15:0] tcp_header_length =
                    {10'd0, m_tcp_data_offset, 2'b00};


    /*
       Detect malformed TCP length.

       If TCP length is smaller than TCP header length,
       the packet cannot contain a valid TCP header.
    */

    wire tcp_length_error =
                    (tcp_length < tcp_header_length);


    /*
       Zero payload occurs when:

           TCP length = TCP header length

       Therefore:

           payload length = 0
    */

    wire zero_payload_comb =
                    (tcp_length == tcp_header_length) &&
                    !tcp_length_error;


    // =========================================================================
    // TCP OFFSET + FLAGS WORD
    // =========================================================================

    /*
       TCP word:

       [15:12] Data Offset
       [11:8]  Reserved
       [7:0]   TCP Flags
    */

    wire [15:0] tcp_offset_flags =
                    {m_tcp_data_offset, 4'b0000, m_tcp_flags};


    // =========================================================================
    // STAGE 1 REGISTERS
    // =========================================================================

    reg [31:0] tcp_hdr_sum;

    reg [3:0]  saved_data_offset;

    reg        is_zero_payload;

    reg        saved_length_error;

    /*
       Generates a one-cycle pulse for zero-payload packets.
    */

    reg        eval_zero_payload_trigger;


    // =========================================================================
    // STAGE 1: HEADER CHECKSUM SUMMATION
    // =========================================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            tcp_hdr_sum               <= 32'd0;
            saved_data_offset         <= 4'd0;
            is_zero_payload           <= 1'b0;
            saved_length_error        <= 1'b0;
            eval_zero_payload_trigger <= 1'b0;

        end
        else begin

            /*
               Default:
               zero-payload evaluation is a one-cycle pulse.
            */

            eval_zero_payload_trigger <=
                    m_tcp_valid && zero_payload_comb;


            if (m_tcp_valid) begin

                /*
                   Save TCP Data Offset for evaluation when payload
                   finishes.
                */

                saved_data_offset <= m_tcp_data_offset;

                /*
                   Save zero-payload status.
                */

                is_zero_payload <= zero_payload_comb;

                /*
                   Save malformed length status.
                */

                saved_length_error <= tcp_length_error;


                /*
                   ---------------------------------------------------------
                   TCP PSEUDO HEADER + TCP HEADER
                   ---------------------------------------------------------

                   Every 16-bit checksum word is explicitly widened
                   to 32 bits.

                   This avoids unintended expression-width truncation
                   during synthesis.
                */

                tcp_hdr_sum <=

                    // IPv4 Source Address
                    {16'd0, m_ipv4_src_ip[31:16]} +
                    {16'd0, m_ipv4_src_ip[15:0]} +

                    // IPv4 Destination Address
                    {16'd0, m_ipv4_dst_ip[31:16]} +
                    {16'd0, m_ipv4_dst_ip[15:0]} +

                    // Protocol
                    {16'd0, {8'd0, m_ipv4_protocol}} +

                    // TCP Length
                    {16'd0, tcp_length} +

                    // TCP Source Port
                    {16'd0, m_tcp_src_port} +

                    // TCP Destination Port
                    {16'd0, m_tcp_dst_port} +

                    // TCP Sequence Number
                    {16'd0, m_tcp_seq_num[31:16]} +
                    {16'd0, m_tcp_seq_num[15:0]} +

                    // TCP Acknowledgment Number
                    {16'd0, m_tcp_ack_num[31:16]} +
                    {16'd0, m_tcp_ack_num[15:0]} +

                    // Data Offset + Flags
                    {16'd0, tcp_offset_flags} +

                    // Window
                    {16'd0, m_tcp_window} +

                    // TCP Checksum
                    {16'd0, m_tcp_checksum} +

                    // Urgent Pointer
                    {16'd0, m_tcp_urg_ptr};

            end

        end

    end


    // =========================================================================
    // STAGE 2
    // TCP PAYLOAD ACCUMULATOR
    // =========================================================================

    reg [31:0] tcp_payload_sum;

    /*
       Stores the first byte of a 16-bit checksum word.
    */

    reg [7:0] upper_byte;

    /*
       0 = waiting for first byte
       1 = upper byte already stored
    */

    reg byte_state;


    // =========================================================================
    // FINAL PAYLOAD WORD
    // =========================================================================

    /*
       If byte_state = 0:

           Current byte is treated as the first byte of
           a final odd-length word.

           Example:

               0xAB

           becomes:

               0xAB00


       If byte_state = 1:

           upper_byte + current byte form a 16-bit word.
    */

    wire [15:0] final_payload_word =

            (byte_state == 1'b0) ?
                {m_axis_tdata, 8'h00} :
                {upper_byte, m_axis_tdata};


    // =========================================================================
    // STAGE 2: PAYLOAD ACCUMULATION
    // =========================================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            tcp_payload_sum <= 32'd0;
            upper_byte      <= 8'd0;
            byte_state      <= 1'b0;

        end

        /*
           New packet starts.

           Reset the payload accumulator.

           IMPORTANT:
           If payload also arrives in this same cycle,
           process it instead of discarding it.
        */

        else if (m_tcp_valid) begin

            tcp_payload_sum <= 32'd0;
            upper_byte      <= 8'd0;
            byte_state      <= 1'b0;


            /*
               Same-cycle first payload byte support.

               For a normal payload packet, store the first byte.

               For zero payload, m_axis_is_tcp_payload should be 0.
            */

            if (m_axis_tvalid && m_axis_is_tcp_payload) begin

                upper_byte <= m_axis_tdata;
                byte_state <= 1'b1;

            end

        end

        /*
           Normal payload processing.
        */

        else if (m_axis_tvalid && m_axis_is_tcp_payload) begin

            /*
               First byte of 16-bit checksum word.
            */

            if (byte_state == 1'b0) begin

                upper_byte <= m_axis_tdata;
                byte_state <= 1'b1;

            end

            /*
               Second byte of 16-bit checksum word.
            */

            else begin

                /*
                   Do NOT add the final word to the registered
                   accumulator.

                   The final word is added combinationally through
                   final_payload_word.

                   This avoids a sequential timing race at tlast.
                */

                if (!m_axis_tlast) begin

                    tcp_payload_sum <=
                        tcp_payload_sum +
                        {16'd0, upper_byte, m_axis_tdata};

                end

                byte_state <= 1'b0;

            end

        end

    end


    // =========================================================================
    // STAGE 3
    // FINAL CHECKSUM ARITHMETIC
    // =========================================================================

    /*
       Payload contribution.

       For zero payload:

           active_payload = 0

       Otherwise:

           accumulated complete 16-bit words
           +
           final word
    */

    wire [32:0] active_payload =

            (is_zero_payload) ?

                33'd0 :

                {1'b0, tcp_payload_sum} +
                {17'd0, final_payload_word};


    /*
       Header sum + payload sum.

       33 bits are used to explicitly preserve the carry.
    */

    wire [32:0] grand_total =

            {1'b0, tcp_hdr_sum} +
            active_payload;


    /*
       First end-around carry fold.

       Lower 16 bits + upper 17 bits.
    */

    wire [16:0] fold_step1 =

            grand_total[15:0] +
            grand_total[32:16];


    /*
       Final end-around carry fold.
    */

    wire [15:0] final_checksum =

            fold_step1[15:0] +
            fold_step1[16];


    // =========================================================================
    // PACKET COMPLETION TRIGGER
    // =========================================================================

    wire tlast_trigger =

            m_axis_tvalid &&
            m_axis_is_tcp_payload &&
            m_axis_tlast;


    // =========================================================================
    // STAGE 3: CHECKSUM RESULT
    // =========================================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            tcp_csum_ok          <= 1'b0;
            tcp_csum_error       <= 1'b0;
            tcp_csum_unsupported <= 1'b0;

        end
        else begin

            /*
               Default clear.

               Outputs are one-clock-cycle pulses.
            */

            tcp_csum_ok          <= 1'b0;
            tcp_csum_error       <= 1'b0;
            tcp_csum_unsupported <= 1'b0;


            /*
               -------------------------------------------------------------
               CHECKSUM EVALUATION
               -------------------------------------------------------------

               Case 1:
                   Zero-byte payload.

               Case 2:
                   Normal payload ending with tlast.
            */

            if (eval_zero_payload_trigger || tlast_trigger) begin


                // ---------------------------------------------------------
                // 1. INVALID TCP LENGTH
                // ---------------------------------------------------------

                if (saved_length_error) begin

                    tcp_csum_error <= 1'b1;

                end


                // ---------------------------------------------------------
                // 2. INVALID TCP DATA OFFSET
                // ---------------------------------------------------------

                else if (saved_data_offset < 4'h5) begin

                    tcp_csum_error <= 1'b1;

                end


                // ---------------------------------------------------------
                // 3. TCP OPTIONS NOT SUPPORTED BY FAST PATH
                // ---------------------------------------------------------

                else if (saved_data_offset > 4'h5) begin

                    tcp_csum_unsupported <= 1'b1;

                end


                // ---------------------------------------------------------
                // 4. BAD ETHERNET CRC
                // ---------------------------------------------------------

                /*
                   m_axis_tuser is meaningful for an actual payload
                   stream.

                   For zero payload there may be no AXI payload cycle,
                   so do not depend on m_axis_tuser.
                */

                else if (!is_zero_payload &&
                         m_axis_tuser == 1'b1) begin

                    tcp_csum_error <= 1'b1;

                end


                // ---------------------------------------------------------
                // 5. HARDWARE FAST PATH
                // ---------------------------------------------------------

                else begin

                    if (final_checksum == 16'hFFFF) begin

                        tcp_csum_ok <= 1'b1;

                    end
                    else begin

                        tcp_csum_error <= 1'b1;

                    end

                end

            end

        end

    end

endmodule
