// ============================================================================
// File        : rv32_pc.sv
// Description : Program Counter for the RV32IM single-cycle core.
//               Supports sequential (PC+4), branch, jump (JAL/JALR),
//               and IRQ vector sources with a DMA stall input.
// Project     : 1-TOPS — Team Infinity
// Target      : 65nm SCL CMOS ASIC
// ============================================================================
//
// CRITICAL TIMING NOTE — FETCH STAGE (Start of the critical path)
// ---------------------------------------------------------------
// The PC output feeds directly into the instruction SRAM address.
// In a single-cycle design this is the FIRST link in the longest
// combinational chain:
//
//   PC_out  →  SRAM addr  →  instruction word  →  (decode + execute + WB)
//
// The PC register itself is fast (flop → mux → flop), but the downstream
// SRAM read latency is the dominant contributor at this stage.
// ============================================================================

import pkg_rv32_types::*;

module rv32_pc (
    input  logic             clk,
    input  logic             rst_n,        // Active-low synchronous reset
    input  pc_src_e          pc_src,       // Next-PC mux select
    input  logic [XLEN-1:0]  branch_target,// Computed branch / jump address
    input  logic [XLEN-1:0]  irq_vector,  // ISR entry address
    input  logic             stall,        // Hold PC (DMA or hazard)

    output logic [XLEN-1:0]  pc_out,      // Current instruction address
    output logic [XLEN-1:0]  pc_plus4     // Next sequential address
);

    // Next-PC combinational logic
    logic [XLEN-1:0] pc_next;

    // PC + 4 is always available for link-register writes (JAL/JALR)
    assign pc_plus4 = pc_out + 32'd4;

    // -----------------------------------------------------------------
    // Next-PC mux — selects among four sources.
    // In the critical path this mux resolves AFTER the branch unit and
    // ALU have determined whether a branch/jump is taken.
    // -----------------------------------------------------------------
    always @(*) begin
        unique case (pc_src)
            PC_PLUS4  : pc_next = pc_plus4;       // Normal sequential fetch
            PC_BRANCH : pc_next = branch_target;   // Conditional branch taken
            PC_JUMP   : pc_next = branch_target;   // JAL / JALR
            PC_IRQ    : pc_next = irq_vector;      // Interrupt service routine
            default   : pc_next = pc_plus4;
        endcase
    end

    // -----------------------------------------------------------------
    // PC register — rising-edge, synchronous reset, stall-able
    // -----------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n)
            pc_out <= RESET_VECTOR;
        else if (!stall)
            pc_out <= pc_next;
        // else: hold current value (DMA or external stall)
    end

endmodule : rv32_pc
