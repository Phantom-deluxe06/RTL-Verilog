// ============================================================================
// File        : rv32_ahb_lite_master.sv
// Description : AHB-Lite bus master interface for the RV32IM single-cycle core.
//               Converts CPU instruction-fetch and load/store requests into
//               AHB-Lite single-transfer transactions on the unified SRAM bus.
// Project     : 1-TOPS — Team Infinity
// Target      : 65nm SCL CMOS ASIC
// ============================================================================
//
// DESIGN NOTE — SINGLE-CYCLE MEMORY ACCESS
// ------------------------------------------
// In a single-cycle core every instruction completes in one clock period,
// which means both instruction fetch and data access must resolve within
// the same cycle.  For a unified memory this creates a structural hazard.
//
// Solution adopted here:
//   • Instruction fetch is given priority (HADDR = PC).
//   • Data access (load/store) shares the same port via a simple mux.
//   • The SoC top module handles the actual SRAM and presents a
//     zero-wait-state AHB-Lite slave (HREADY always high for SRAM reads).
//
// For the 65nm SCL target, the on-chip SRAM is expected to be single-
// cycle access.  HREADY is provided for AHB-Lite compliance and to
// stall the core if an external slow slave is attached in future.
// ============================================================================

import pkg_rv32_types::*;

module rv32_ahb_lite_master (
    input  logic             clk,
    input  logic             rst_n,

    // --- CPU-side interface (from datapath) ---
    input  logic [XLEN-1:0]  instr_addr,    // Instruction fetch address (PC)
    input  logic [XLEN-1:0]  data_addr,     // Load/store address (ALU result)
    input  logic [XLEN-1:0]  data_wdata,    // Store write data (rs2)
    input  logic             data_read,     // Load request
    input  logic             data_write,    // Store request
    input  mem_size_e        data_size,     // Byte / Half / Word

    output logic [XLEN-1:0]  instr_rdata,   // Fetched instruction word
    output logic [XLEN-1:0]  data_rdata,    // Load read data
    output logic             bus_stall,     // Stall CPU (slave not ready)

    // --- AHB-Lite Master ports (directly to slave / interconnect) ---
    output logic [XLEN-1:0]  HADDR,
    output logic [2:0]       HSIZE,
    output logic [1:0]       HTRANS,
    output logic             HWRITE,
    output logic [XLEN-1:0]  HWDATA,
    output logic [2:0]       HBURST,
    output logic [3:0]       HPROT,

    input  logic [XLEN-1:0]  HRDATA,
    input  logic             HREADY,
    input  logic             HRESP
);

    // -----------------------------------------------------------------
    // AHB-Lite constant signals for single-transfer operation
    // -----------------------------------------------------------------
    assign HBURST = 3'b000;          // SINGLE burst
    assign HPROT  = 4'b0011;         // Non-cacheable, non-bufferable, privileged, data

    // -----------------------------------------------------------------
    // Bus phases — simplified for single-cycle
    //
    // In a true AHB-Lite pipeline the address and data phases are
    // offset by one cycle.  For the single-cycle core we treat
    // instruction fetch as a combinational read (address → data in
    // the same cycle) and handle load/store as a second access.
    //
    // The SoC wrapper provides a dual-port or time-multiplexed SRAM
    // to resolve the structural hazard.  Here we expose two logical
    // accesses via a simple priority scheme.
    // -----------------------------------------------------------------

    // Instruction fetch is the default access
    // Data access overrides when a load or store is active

    logic data_access;
    assign data_access = data_read | data_write;

    // Address phase
    always_comb begin
        if (data_access) begin
            HADDR  = data_addr;
            HWRITE = data_write;
            HTRANS = AHB_NONSEQ;  // Single transfer
            unique case (data_size)
                MEM_BYTE, MEM_BYTE_U: HSIZE = AHB_SIZE_BYTE;
                MEM_HALF, MEM_HALF_U: HSIZE = AHB_SIZE_HALF;
                default:              HSIZE = AHB_SIZE_WORD;
            endcase
        end else begin
            HADDR  = instr_addr;
            HWRITE = 1'b0;
            HTRANS = AHB_NONSEQ;
            HSIZE  = AHB_SIZE_WORD;  // Instructions are always 32-bit
        end
    end

    // Data phase — write data
    assign HWDATA = data_wdata;

    // Read data routing
    assign instr_rdata = HRDATA;     // Instruction read from bus
    assign data_rdata  = HRDATA;     // Data read from bus

    // Stall when slave is not ready
    assign bus_stall = ~HREADY;

endmodule : rv32_ahb_lite_master
