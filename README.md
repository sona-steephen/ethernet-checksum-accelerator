

# Ethernet Checksum Accelerator

> **ASIC-based Ethernet packet-processing accelerator implementing CRC-32, IPv4 checksum, and TCP checksum generation and verification for NIC TX/RX datapaths.**

This project implements dedicated hardware accelerators for key Ethernet packet-processing operations commonly offloaded in Network Interface Controllers (NICs).

The design consists of three independently implemented packet-processing blocks:

* **CRC-32 TX/RX Engine**
* **TX IPv4/TCP Checksum Offload Engine**
* **RX IPv4/TCP Checksum Verification Engine**

The project covers the complete digital hardware development flow from **Verilog RTL design and functional verification to synthesis, physical implementation, post-route timing/power analysis, and physical verification**.

> **Implementation scope:** The ASIC flow was carried through post-route analysis. GDSII generation was not included.

---

## 📌 Project Overview

Modern NICs can offload packet-processing operations such as:

* Ethernet CRC generation and verification
* IPv4 checksum calculation
* TCP checksum calculation
* Packet integrity verification
* Checksum insertion during transmission

This project focuses specifically on these packet-processing functions rather than implementing a complete NIC containing PCIe, DMA, PHY, and MAC subsystems.

### System-Level Concept

```text
                    Ethernet Packet
                           |
                           v
                +----------------------+
                |   Packet Processing  |
                +----------------------+
                           |
          +----------------+----------------+
          |                |                |
          v                v                v
     CRC-32 Engine    TX Checksum       RX Checksum
       TX / RX        Offload Engine    Verification
          |                |                |
          v                v                v
      FCS Gen.        IPv4 / TCP        IPv4 / TCP
      / Verify         Checksum          Checksum
                       Insertion         Verification
```

---

# 🚀 Design Architecture

The project is divided into three independent hardware designs.

| Design             | Function                                   | Interface / Architecture                 |
| ------------------ | ------------------------------------------ | ---------------------------------------- |
| CRC-32 TX/RX       | Ethernet FCS generation and verification   | 8-bit streaming datapath                 |
| TX IP/TCP Checksum | IPv4/TCP checksum generation and insertion | AXI4-Stream + metadata                   |
| RX IP/TCP Checksum | IPv4/TCP checksum verification             | Parser/PCG metadata + streaming datapath |

---

# 1. CRC-32 TX/RX Engine

## Overview

The CRC-32 design implements Ethernet frame CRC generation on the transmit side and CRC verification on the receive side.

An **8-bit parallel CRC architecture** is used so that one byte can be processed per clock cycle.

The reflected Ethernet CRC-32 polynomial is:

```text
32'hEDB88320
```

The same CRC computation is used for both TX generation and RX verification.

---

## CRC Architecture

```text
                     CRC-32 Engine
                          |
             +------------+------------+
             |                         |
             v                         v
          TX CRC                    RX CRC
             |                         |
             v                         v
      CRC Generation          CRC Verification
             |                         |
             v                         v
       Final CRC              CRC Residue Check
             |                         |
             v                         v
        FCS Output                PASS / FAIL
```

---

## TX CRC Operation

```text
AXI4-Stream Input
       |
       v
Frame Detection
       |
       v
Initialize CRC State
       |
       v
8-bit CRC Computation
       |
       v
CRC State Register
       |
       v
Detect Final Payload Byte
       |
       v
Final CRC
       |
       v
Bitwise Inversion
       |
       v
Ethernet FCS
```

### TX Processing

1. Detect the beginning of a frame.
2. Initialize the CRC state.
3. Process one byte per clock cycle.
4. Update the CRC state for every accepted byte.
5. Detect the final payload byte.
6. Generate the final CRC/FCS.
7. Transmit the FCS in Ethernet byte order.

---

## RX CRC Operation

```text
Received Ethernet Frame
          |
          v
        Payload
          |
          v
   CRC-32 Computation
          |
          v
      CRC Residue
          |
      +---+---+
      |       |
      v       v
    PASS     FAIL
```

The received FCS is included in the CRC calculation.

For a valid Ethernet frame, the expected CRC residue is:

```text
32'hDEBB20E3
```

---

## CRC Design Assumptions

* Ethernet CRC-32
* Reflected polynomial: `32'hEDB88320`
* CRC processing begins after the Ethernet SFD
* 8-bit datapath
* One byte processed per clock cycle
* TX FCS generated from the final CRC state
* RX verification uses residue `32'hDEBB20E3`
* Higher-layer protocols are not interpreted by the CRC block
* AXI4-Stream interfaces are used for packet-data transfer

---

## CRC Functional Verification

The standard CRC test vector was used:

```text
Input:
123456789

Expected CRC-32:
CBF43926
```

| Parameter           | Result      |
| ------------------- | ----------- |
| Test Input          | `123456789` |
| Expected CRC-32     | `CBF43926`  |
| RX Expected Residue | `DEBB20E3`  |
| Result              | PASS        |

---

# 2. TX IPv4/TCP Checksum Offload

## Overview

The TX checksum design generates IPv4 and TCP checksums for outgoing packets and inserts the calculated values into the transmitted packet.

The architecture uses a **metadata-driven store-and-forward approach**.

Packet data is temporarily stored in an SRAM-based packet buffer while checksum computation is performed. During packet readback, the checksum fields are replaced with the calculated values.

---

## TX Architecture

```text
             AXI4-Stream Packet
                     |
                     v
             +---------------+
             | Metadata      |
             | Tracker       |
             +-------+-------+
                     |
          +----------+----------+
          |                     |
          v                     v
 +------------------+   +------------------+
 | IPv4 Checksum    |   | TCP Checksum     |
 | Engine           |   | Engine           |
 +---------+--------+   +---------+--------+
           |                      |
           +----------+-----------+
                      |
                      v
             +----------------+
             | Packet Buffer  |
             | 16 KB SRAM     |
             +-------+--------+
                     |
                     v
             +----------------+
             | Egress Control |
             +-------+--------+
                     |
                     v
             +----------------+
             | Checksum Insert|
             | MUX            |
             +-------+--------+
                     |
                     v
               AXI4-Stream TX
```

---

## TX Processing Sequence

```text
Receive Packet
      |
      v
Track Packet Metadata
      |
      v
Store Packet in SRAM
      |
      v
Calculate IPv4 Checksum
      |
      +-------> Calculate TCP Checksum
      |
      v
Wait for Packet Completion
      |
      v
Read Packet from SRAM
      |
      v
Insert Calculated Checksums
      |
      v
Transmit Packet
```

---

## TX Design Assumptions

* 8-bit AXI4-Stream datapath
* One byte per successful transfer
* Byte accepted when:

```text
tvalid && tready
```

* `tlast` identifies the final byte
* Packet context supplied through `tuser` metadata
* IPv4 header length supplied through metadata
* TCP checksum covers:

  * IPv4 pseudo-header
  * TCP header
  * TCP payload
* Existing checksum fields treated as zero during calculation
* Packet size limited to 16 KB
* One packet processed at a time
* Packet bytes processed in network byte order
* Synchronous 100 MHz clock
* Active-low reset

---

## TX Functional Verification

The TX testbench verified:

* Standard Ethernet + IPv4 + TCP packets
* VLAN-tagged packets
* Odd-length TCP payloads
* IPv4 checksum generation
* TCP checksum generation
* Checksum insertion
* Preservation of non-checksum packet bytes
* Metadata-driven header offsets

### Verification Results

| Test | Packet Type                     | Length | L3 Offset | TCP Offset | IPv4 Checksum | TCP Checksum | Result |
| ---- | ------------------------------- | -----: | --------: | ---------: | ------------: | -----------: | ------ |
| 1    | Ethernet + IPv4 + TCP           |   54 B |        14 |         34 |        `B77C` |       `076D` | PASS   |
| 2    | VLAN + IPv4 + TCP               |   58 B |        18 |         38 |        `B77C` |       `076D` | PASS   |
| 3    | VLAN + IPv4 + TCP + Odd Payload |   63 B |        18 |         38 |        `B777` |       `23D6` | PASS   |

---

# 3. RX IPv4/TCP Checksum Verification

## Overview

The RX checksum design verifies IPv4 and TCP checksums on received packets.

Unlike the TX design, the RX checksum block does **not duplicate packet parsing**.

Required protocol metadata is supplied by an upstream parser/PCG interface.

The architecture contains dedicated IPv4 and TCP checksum engines.

---

## RX Architecture

```text
             Parser / PCG Metadata
                     |
                     v
             +---------------+
             | RX Checksum   |
             | Top           |
             +-------+-------+
                     |
          +----------+----------+
          |                     |
          v                     v
 +------------------+   +------------------+
 | IPv4 Checksum    |   | TCP Checksum     |
 | Engine           |   | Engine           |
 +---------+--------+   +---------+--------+
           |                      |
           v                      v
      IPv4 Status            TCP Status
           |                      |
           +----------+-----------+
                      |
                      v
                   PASS / FAIL
```

---

## IPv4 Checksum

The IPv4 checksum engine verifies the **16-bit one's-complement checksum** of the IPv4 header.

The implemented fast path supports the standard 20-byte IPv4 header.

IPv4 options are reported as unsupported.

---

## TCP Checksum

The TCP checksum is calculated over:

```text
IPv4 Pseudo-Header
        +
TCP Header
        +
TCP Payload
```

The TCP checksum datapath uses carry-save arithmetic for intermediate accumulation to reduce carry propagation in the arithmetic path.

---

## RX Design Assumptions

* 8-bit payload stream
* Required IPv4/TCP metadata supplied by parser/PCG
* Valid metadata signals indicate IPv4/TCP headers
* Standard 20-byte IPv4 headers supported
* IPv4 options unsupported
* Standard 20-byte TCP headers supported
* TCP options unsupported
* TCP checksum includes:

  * IPv4 pseudo-header
  * TCP header
  * TCP payload
* TCP payload identified using payload-valid/context interface
* `tlast` identifies final TCP payload byte
* Even- and odd-length TCP payloads supported
* Malformed header lengths reported as checksum errors
* One packet context processed at a time
* Single synchronous clock
* Active-low reset

---

## RX Functional Verification

The RX design was verified using normal and boundary-condition packets.

| Test Case | Packet Configuration                         | Expected Result     | Status |
| --------- | -------------------------------------------- | ------------------- | ------ |
| TC1       | 20-byte IPv4 + 20-byte TCP + 10-byte payload | IPv4 PASS, TCP PASS | PASS   |
| TC2       | 20-byte IPv4 + 20-byte TCP + 9-byte payload  | TCP checksum PASS   | PASS   |

The odd-length payload test verifies correct handling of the final unpaired byte during one's-complement checksum accumulation.

---

# 4. ASIC Implementation Flow

All three designs were independently implemented using a common RTL-to-post-route ASIC methodology.

```text
             Verilog RTL
                  |
                  v
        RTL Functional Verification
                  |
                  v
           Logic Synthesis
           Cadence Genus
                  |
                  v
            Floorplanning
                  |
                  v
            Power Planning
                  |
                  v
              Placement
                  |
                  v
      Clock Tree Synthesis (CTS)
                  |
                  v
               Routing
                  |
                  v
       Post-Route RC Extraction
                  |
                  v
       Post-Route Static Timing
                  |
                  v
        Post-Route Power Analysis
                  |
                  v
        Physical Verification
```

---

## Tools & Technologies

| Stage                   | Tool / Technology      |
| ----------------------- | ---------------------- |
| RTL Design              | Verilog HDL            |
| RTL Simulation          | Xilinx Vivado / XSIM   |
| Logic Synthesis         | Cadence Genus          |
| Physical Implementation | Cadence Innovus        |
| Static Timing Analysis  | Cadence Flow / Innovus |
| Floorplanning           | Cadence Innovus        |
| Power Planning          | Cadence Innovus        |
| Placement               | Cadence Innovus        |
| CTS                     | Cadence Innovus        |
| Routing                 | Cadence Innovus        |
| RC Extraction           | Cadence Innovus        |
| Physical Verification   | Cadence Innovus        |

---

# 5. Common ASIC Constraints

| Parameter        |   Value |
| ---------------- | ------: |
| Target Frequency | 100 MHz |
| Clock Period     |   10 ns |
| Maximum Fanout   |      16 |

---

# 6. Floorplanning

The synthesized netlists were imported into Cadence Innovus.

Floorplanning considered:

* Standard-cell area
* Routing resources
* Power distribution
* SRAM macro placement
* Timing requirements
* Congestion
* Core utilization

### Floorplan Characteristics

| Parameter       |         CRC-32 |            TX IP/TCP |     RX IP/TCP |
| --------------- | -------------: | -------------------: | ------------: |
| Floorplan       |         Square |               Square |        Square |
| Size            | 98.4 × 95.0 µm | 1299.76 × 1299.76 µm | ~150 × 150 µm |
| Utilization     |     70% target |           SRAM-aware |      Moderate |
| SRAM Macros     |              0 |                    2 |             0 |
| Buffer Capacity |              — |                16 KB |             — |

The TX design requires significantly more physical area because of its two SRAM packet-buffer macros.

---

# 7. Power Planning

Power planning was performed using VDD/VSS power rings and stripes.

```text
             Power Network
                  |
       +----------+----------+
       |                     |
       v                     v
   VDD Ring               VSS Ring
       |                     |
       +----------+----------+
                  |
                  v
            Power Stripes
                  |
                  v
        Standard Cell / SRAM
          Power Connections
```

The power network was designed to provide reliable supply connectivity while balancing routing-resource usage.

---

# 8. Placement

Timing- and routability-aware placement was performed using Cadence Innovus.

| Parameter             | CRC-32 | TX IP/TCP | RX IP/TCP |
| --------------------- | -----: | --------: | --------: |
| Placed Standard Cells |    476 |      1704 |      1811 |
| SRAM Macros           |      0 |         2 |         0 |
| Unplaced Cells        |      0 |         0 |         0 |
| Routing Overflow      |      0 |         0 |         0 |
| Placement WNS         |      — | +0.007 ns | +0.006 ns |

The RX implementation used moderate placement density to provide routing and timing margin.

---

# 9. Clock Tree Synthesis

Clock Tree Synthesis was performed using Cadence Innovus.

The CTS stage focused on:

* Clock skew
* Insertion delay
* Transition
* Fanout
* Setup timing
* Hold timing

Clock buffers were introduced where required to obtain a controlled clock distribution network.

---

# 10. Routing

Global and detailed routing were performed after CTS.

| Check            |   CRC-32 | TX IP/TCP | RX IP/TCP |
| ---------------- | -------: | --------: | --------: |
| Route Failures   |        0 |         0 |         0 |
| Routing Overflow |        0 |         0 |         0 |
| Connectivity     | Verified |  Verified |  Verified |

---

# 11. Post-Route Analysis

After routing, physical parasitic resistance and capacitance were extracted.

The extracted RC information was used for:

* Post-route Static Timing Analysis
* Setup analysis
* Hold analysis
* Post-route power analysis

Post-route analysis provides a more realistic assessment of timing and power because physical interconnect parasitics are included.

---

# 12. Physical Verification

The final routed implementations were checked for:

* Routing completion
* Routing overflow
* Design-rule compliance
* Connectivity
* Timing closure

The reported implementations achieved **zero routing overflow**.

> **Important:** The reported implementation scope ended at post-route analysis and did not include GDSII generation.

---

# 📊 PPA Results

## Final Post-Route Summary

| Metric           |             CRC-32 |       TX IP/TCP |     RX IP/TCP |
| ---------------- | -----------------: | --------------: | ------------: |
| Technology       |              45 nm |          180 nm |         45 nm |
| Frequency        |            100 MHz |         100 MHz |       100 MHz |
| Area             |      1,731.888 µm² | 818,304.049 µm² | 7,783.578 µm² |
| Power            |         167.141 µW |      11.1401 mW |   0.700232 mW |
| Setup WNS        | +5.853 / +7.086 ns |       +0.051 ns |     +0.210 ns |
| Hold WNS         | +0.018 / +0.008 ns |       +0.132 ns |     +0.001 ns |
| Routing Overflow |                  0 |               0 |             0 |
| DRC              |                  0 |               — |             0 |

### ⚠️ Comparison Note

The three designs were implemented using different technology libraries and physical configurations.

Therefore, the absolute area and power values **should not be treated as a direct apples-to-apples comparison**.

The PPA values are primarily useful for evaluating each design's own implementation and architectural trade-offs.

---

# 13. CRC-32 PPA Analysis

| Metric                |        Result |
| --------------------- | ------------: |
| Technology            |         45 nm |
| Standard-Cell Count   |           476 |
| Standard-Cell Area    | 1,731.888 µm² |
| Approx. Die Area      |     9,348 µm² |
| Total Power           |    167.141 µW |
| Total Capacitance     |      3.116 pF |
| TX Setup Slack        |     +5.853 ns |
| RX Setup Slack        |     +7.086 ns |
| TX Hold Slack         |     +0.018 ns |
| RX Hold Slack         |     +0.008 ns |
| Horizontal Congestion |          1.5% |
| Vertical Congestion   |          1.9% |
| Routing Overflow      |             0 |
| DRC Violations        |             0 |

### Interpretation

The 8-bit parallel CRC architecture trades additional combinational logic for one-byte-per-cycle processing.

The 70% target utilization provides a balance between physical area and routing resources.

The final implementation achieved:

* Positive setup slack
* Positive hold slack
* Zero routing overflow
* Zero reported DRC violations
* Low routing congestion

---

# 14. TX IP/TCP PPA Analysis

| Metric           |          Result |
| ---------------- | --------------: |
| Technology       |          180 nm |
| Physical Area    | 818,304.049 µm² |
| Power            |      11.1401 mW |
| Setup WNS        |       +0.051 ns |
| Hold WNS         |       +0.132 ns |
| Routing Overflow |               0 |

### Area Distribution

| Block             | Area (µm²) | Contribution |
| ----------------- | ---------: | -----------: |
| SRAM Buffer       | 60,306.709 |       47.90% |
| TCP Engine        | 22,212.050 |       17.65% |
| Metadata Tracker  | 19,371.469 |       15.25% |
| IP Engine         | 14,144.609 |       11.08% |
| Egress Controller |  7,263.211 |        5.69% |
| Checksum MUX      |  2,835.701 |        2.22% |

### Interpretation

The TX design is physically dominated by the packet-buffer SRAM macros.

The TCP checksum arithmetic is the primary timing-critical logic.

The architecture trades additional memory area for:

* Store-and-forward processing
* Packet buffering
* Checksum insertion during readback
* Reduced need for packet rewriting

The final implementation achieved positive setup and hold timing at the 100 MHz target.

---

# 15. RX IP/TCP PPA Analysis

| Metric            |        Result |
| ----------------- | ------------: |
| Technology        |         45 nm |
| Cell Area         | 7,783.578 µm² |
| Power             |   0.700232 mW |
| Setup WNS         |     +0.210 ns |
| Hold WNS          |     +0.001 ns |
| Setup TNS         |          0 ns |
| Hold TNS          |          0 ns |
| Placement Density |       46.071% |
| Routing Overflow  |            0% |
| DRC Violations    |             0 |

The TCP checksum arithmetic datapath was identified as the timing-critical portion of the RX subsystem.

The physical implementation and optimization flow was used to recover timing margin after placement and routing.

---

# ⚖️ Design Trade-offs

## CRC-32

| Design Aspect    | Selected Approach | Reason                        |
| ---------------- | ----------------- | ----------------------------- |
| CRC Architecture | 8-bit parallel    | One byte per cycle            |
| Floorplan        | Square            | Balanced geometry             |
| Utilization      | 70% target        | Area/routability balance      |
| Clocking         | Balanced CTS      | Controlled clock distribution |
| Final Analysis   | Post-route RC     | Captures physical effects     |
| Frequency        | 100 MHz           | Meets target timing           |

---

## TX IP/TCP Checksum

| Design Aspect       | Selected Approach         | Trade-off                                             |
| ------------------- | ------------------------- | ----------------------------------------------------- |
| Packet Processing   | Metadata / TUSER          | Less parsing hardware but depends on correct metadata |
| Checksum Processing | Separate IPv4/TCP engines | More logic, better processing efficiency              |
| Packet Storage      | Two SRAM macros           | Efficient storage but large physical footprint        |
| TCP Accumulator     | Sequential accumulator    | Lower arithmetic depth, additional sequential logic   |
| Pseudo-header       | FSM-based accumulation    | Reduced combinational depth                           |
| Checksum Insertion  | MUX during SRAM readout   | Avoids packet rewrite                                 |
| Physical Design     | Lower-density placement   | More area, improved routing margin                    |
| Clocking            | CCOpt-based CTS           | Additional clock resources                            |

---

## RX IP/TCP Checksum

| Design Aspect      | Selected Approach          | Trade-off                         |
| ------------------ | -------------------------- | --------------------------------- |
| Packet Information | Parser-provided metadata   | Avoids duplicate parsing          |
| IPv4 Checksum      | Dedicated engine           | Simple independent datapath       |
| TCP Checksum       | Carry-save arithmetic      | Improved timing, additional logic |
| Accumulation       | Hybrid sequential/parallel | Area/timing compromise            |
| Payload            | Dedicated payload stream   | Avoids parser duplication         |
| Placement          | Moderate density           | More area, better routability     |
| Clocking           | Balanced CTS               | Additional clock resources        |

---

# 🧪 Verification Summary

| Design       | Main Verification                     |
| ------------ | ------------------------------------- |
| CRC-32 TX/RX | CRC functional simulation             |
| TX IP/TCP    | Standard, VLAN and odd-length packets |
| RX IP/TCP    | Normal and odd-length TCP payloads    |

Verification focused on both normal operating conditions and boundary cases.

### Verification Coverage

* CRC generation
* CRC verification
* IPv4 checksum generation
* IPv4 checksum verification
* TCP checksum generation
* TCP checksum verification
* VLAN packet handling
* Odd-length payload handling
* Packet boundary detection
* Checksum insertion

---

# ⚠️ Limitations

## CRC-32

* Ethernet CRC-32 only
* 8-bit datapath
* Higher-layer protocol parsing is outside the CRC block

## TX IP/TCP

* IPv4 and TCP checksum processing
* 16 KB packet buffer
* One packet processed at a time
* Requires packet metadata from upstream interface

## RX IP/TCP

* IPv4 checksum verification
* TCP checksum verification
* Standard 20-byte IPv4 header fast path
* Standard 20-byte TCP header
* IPv4 options unsupported
* TCP options unsupported
* One packet context at a time

---

# 🔮 Future Work

## Protocol Extensions

Future versions can investigate:

* IPv6 checksum support
* UDP checksum support
* TCP option support
* IPv4 option support
* Additional Ethernet packet formats

---

## CRC Throughput Improvements

The current CRC architecture processes 8 bits per cycle.

A wider parallel architecture could be explored:

```text
8-bit
  |
  v
16-bit
  |
  v
32-bit
  |
  v
64-bit
```

The objective would be to increase throughput while evaluating the associated:

* Area
* Power
* Timing
* Routing complexity

---

## IP/TCP Checksum Improvements

Potential improvements include:

* Wider checksum datapaths
* Pipelined checksum arithmetic
* Higher-throughput processing
* Back-to-back packet processing
* SRAM organization optimization
* TCP critical-path optimization
* Alternative buffering architectures

---

# 🔧 PPA Optimization Opportunities

## CRC-32

* Optimize XOR network
* Explore wider CRC architectures
* Evaluate area versus throughput
* Evaluate dynamic power versus parallelism

## TX IP/TCP

* Optimize SRAM organization
* Reduce memory-related power
* Optimize TCP critical path
* Investigate alternative buffering architectures
* Explore pipelined checksum processing

## RX IP/TCP

* Optimize TCP checksum arithmetic
* Explore wider/pipelined datapaths
* Improve timing margin
* Reduce arithmetic switching activity
* Optimize clocking resources

---

# 🧪 Future Verification

Future verification can include:

* Constrained-random packet generation
* Larger packet-size coverage
* Back-to-back packets
* VLAN corner cases
* Malformed packets
* IPv4 options
* TCP options
* Fragmented packets
* Additional protocol combinations
* Parser/PCG integration testing
* Formal verification of checksum arithmetic

---

# 🏗️ Future System-Level NIC Integration

The implemented engines can form part of a larger NIC packet-processing architecture.

```text
                         NIC
                          |
          +---------------+---------------+
          |               |               |
          v               v               v
       Parser            DMA             MAC
          |               |               |
          +-------+-------+-------+-------+
                  |               |
                  v               v
           TX Checksum       RX Checksum
              Engine            Engine
                  |               |
                  +-------+-------+
                          |
                          v
                    CRC-32 Engine
                      TX / RX
```

A future complete NIC implementation could integrate:

* Ethernet MAC
* Packet parser
* DMA engine
* Host interface
* TX/RX descriptors
* CRC offload
* IPv4/TCP/UDP checksum offload
* Packet filtering
* End-to-end NIC datapath

---

# 📁 Repository Structure

```text
ethernet-checksum-accelerator/
│
├── README.md
│
├── CRC-32/
│   ├── RTL/
│   │   ├── crc_tx.v
│   │   └── crc_rx.v
│   │
│   └── Testbench/
│       └── tb_crc.v
│
├── TX-IP-TCP-Checksum/
│   ├── RTL/
│   │   ├── tx_checksum_top.v
│   │   ├── ipv4_checksum.v
│   │   ├── tcp_checksum.v
│   │   ├── packet_buffer.v
│   │   └── ...
│   │
│   └── Testbench/
│       └── tb_tx_checksum.v
│
├── RX-IP-TCP-Checksum/
│   ├── RTL/
│   │   ├── rx_checksum_top.v
│   │   ├── ipv4_checksum.v
│   │   ├── tcp_checksum.v
│   │   └── ...
│   │
│   └── Testbench/
│       └── tb_rx_checksum.v
│
└── ASIC/
    ├── Genus/
    ├── Innovus/
    ├── constraints/
    └── reports/
```

> Update the filenames and directories to match the actual RTL files in the repository.

---

# 🛠️ Tools & Technologies

### Hardware Description

* Verilog HDL
* RTL Design
* FSM-based Control
* Streaming Datapaths
* Checksum Arithmetic
* CRC-32 Arithmetic

### Simulation

* Xilinx Vivado
* Vivado XSIM

### ASIC Design

* Cadence Genus
* Cadence Innovus

### ASIC Flow

* RTL Synthesis
* Floorplanning
* Power Planning
* Placement
* Clock Tree Synthesis
* Routing
* Post-route RC Extraction
* Static Timing Analysis
* Post-route Power Analysis
* Physical Verification

---

# ⭐ Project Highlights

* 3 independent packet-processing hardware designs
* Ethernet CRC-32 TX/RX implementation
* IPv4/TCP checksum TX offload
* IPv4/TCP checksum RX verification
* AXI4-Stream based packet processing
* SRAM-based packet buffering
* Carry-save TCP checksum arithmetic
* RTL functional verification
* Cadence Genus synthesis
* Cadence Innovus physical implementation
* Floorplanning and power planning
* Placement and CTS
* Routing
* Post-route RC extraction
* Static timing analysis
* PPA analysis
* Physical verification
* 100 MHz target implementation

---

# 📈 Key Takeaways

This project demonstrates an end-to-end digital hardware design workflow:

```text
Protocol Understanding
        ↓
Hardware Architecture
        ↓
Verilog RTL
        ↓
Functional Verification
        ↓
Logic Synthesis
        ↓
Floorplanning
        ↓
Power Planning
        ↓
Placement
        ↓
Clock Tree Synthesis
        ↓
Routing
        ↓
Post-Route Timing / Power
        ↓
Physical Verification
        ↓
PPA Analysis
```

The project demonstrates how architectural decisions involving:

* Parallelism
* Packet buffering
* Metadata-driven processing
* Arithmetic architecture
* Placement utilization
* Clock-tree


Protocol Understanding
        |
        v
Hardware Architecture
        |
        v
Verilog RTL
        |
        v
Functional Verification
        |
        v
Logic Synthesis
        |
        v
Floorplanning
        |
        v
Power Planning
        |
        v
Placement
        |
        v
Clock Tree Synthesis
        |
        v
Routing
        |
        v
Post-Route Timing / Power
        |
        v
Physical Verification
The project demonstrates how architectural decisions involving:

Parallelism
Packet buffering
Metadata-driven processing
Arithmetic architecture
Placement utilization
Clock-tree implementation
Routing resources

affect the final Performance, Power, Area, and Routability (PPA) of a hardware design.

## 🎯 Key Takeaways

This project demonstrates how architectural and physical-design decisions affect the final **Performance, Power, Area, and Routability (PPA)** of a hardware design.

### Key Design Factors

| Design Factor | Impact |
|---|---|
| **Parallelism** | Determines processing throughput and affects logic area |
| **Packet Buffering** | Enables store-and-forward processing but increases memory area |
| **Metadata-Driven Processing** | Reduces duplicate parsing hardware |
| **Arithmetic Architecture** | Influences timing, area, and power |
| **Placement Utilization** | Affects area, congestion, and routability |
| **Clock-Tree Implementation** | Impacts skew, timing, and clock power |
| **Routing Resources** | Affects congestion, timing, and physical feasibility |

These architectural choices demonstrate the relationship between **RTL architecture and physical implementation results**.

---

## 👩‍💻 Author

### Sona Steephen

**B.Tech – Applied Electronics & Instrumentation Engineering**

### Areas of Interest

```text
RTL Design
ASIC Design
FPGA Design
Digital VLSI
Computer Architecture
Network Hardware
Hardware Acceleration
