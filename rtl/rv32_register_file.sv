// ============================================================================
// File        : rv32_register_file.sv
// Description : 32-entry × 32-bit RISC-V integer register file.
//               x0 is hardwired to zero.  Storage uses logic [31:0] reg_file
//               [31:1] (31 entries) for area-efficient synthesis.
//               Two asynchronous read ports, one synchronous write port.
// Project     : 1-TOPS — Team Infinity
// Target      : 65nm SCL CMOS ASIC
// ============================================================================
//
// CRITICAL TIMING NOTE — REGISTER READ (critical-path link #3)
// -------------------------------------------------------------
// After instruction decode, rs1/rs2 addresses feed into this file.
// The read is purely combinational (async), so the delay is simply
// a mux tree from 31 registers.  This path is:
//
//   instruction[19:15] → rs1_data → ALU operand A
//   instruction[24:20] → rs2_data → ALU operand B  (or store data)
//
// Write-back happens at the END of the cycle (posedge clk).
// ============================================================================

import pkg_rv32_types::*;

module rv32_register_file (
    input  logic                   clk,
    input  logic                   rst_n,

    // Read port 1 (rs1) — asynchronous
    input  logic [REG_ADDR_W-1:0]  rs1_addr,
    output logic [XLEN-1:0]        rs1_data,

    // Read port 2 (rs2) — asynchronous
    input  logic [REG_ADDR_W-1:0]  rs2_addr,
    output logic [XLEN-1:0]        rs2_data,

    // Write port (rd) — synchronous, rising edge
    input  logic                   wr_en,
    input  logic [REG_ADDR_W-1:0]  rd_addr,
    input  logic [XLEN-1:0]        rd_data
);

    // -----------------------------------------------------------------
    // Register storage — 31 registers (x1 – x31).
    // x0 is NOT stored; reads from address 0 return 32'b0.
    // Using [31:1] indexing keeps the array minimal for synthesis.
    // -----------------------------------------------------------------
    logic [XLEN-1:0] reg_file [31:1];

    // -----------------------------------------------------------------
    // Asynchronous reads — combinational mux with x0 = 0 guard
    // -----------------------------------------------------------------
    assign rs1_data = (rs1_addr == 5'b0) ? {XLEN{1'b0}} : reg_file[rs1_addr];
    assign rs2_data = (rs2_addr == 5'b0) ? {XLEN{1'b0}} : reg_file[rs2_addr];

    // -----------------------------------------------------------------
    // Synchronous write — write-enable gated, x0 writes are ignored
    //
    // CRITICAL TIMING NOTE — WRITE-BACK (critical-path link #6, final)
    // The write data arrives from the writeback mux, which is the LAST
    // stage of the single-cycle chain.  This data must meet setup time
    // at the reg_file flip-flops, making it the timing-critical endpoint.
    // -----------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (wr_en && (rd_addr != 5'b0)) begin
            reg_file[rd_addr] <= rd_data;
        end
    end

endmodule : rv32_register_file
