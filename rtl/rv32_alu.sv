// ============================================================================
// File        : rv32_alu.sv
// Description : Arithmetic Logic Unit for the RV32I base integer ISA.
//               Supports ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU,
//               and PASS_B (for LUI).
// Project     : 1-TOPS — Team Infinity
// Target      : 65nm SCL CMOS ASIC
// ============================================================================
//
// CRITICAL TIMING NOTE — EXECUTE (critical-path link #4)
// -------------------------------------------------------
// The ALU sits in the middle of the single-cycle combinational chain.
// Its inputs come from the register file (operand A) and the ALU-src
// mux (operand B = rs2 or immediate).  Its output feeds both the
// data-memory address (for loads/stores) and the writeback mux.
//
//   reg_file_read → ALU → data_mem_addr / writeback_mux
//
// The adder/subtractor and the barrel shifter are the slowest paths
// inside this unit.  For 65nm SCL, the 32-bit adder is typically
// synthesised as a carry-lookahead or Brent-Kung tree.
// ============================================================================

import pkg_rv32_types::*;

module rv32_alu (
    input  alu_op_e          alu_op,       // Operation select
    input  logic [XLEN-1:0]  operand_a,   // Source 1 (rs1)
    input  logic [XLEN-1:0]  operand_b,   // Source 2 (rs2 or immediate)

    output logic [XLEN-1:0]  result,      // ALU result
    output logic             zero_flag    // result == 0
);

    // Shift amount is always the lower 5 bits of operand_b
    logic [4:0] shamt;
    assign shamt = operand_b[4:0];

    always_comb begin
        unique case (alu_op)
            ALU_ADD   : result = operand_a + operand_b;
            ALU_SUB   : result = operand_a - operand_b;
            ALU_AND   : result = operand_a & operand_b;
            ALU_OR    : result = operand_a | operand_b;
            ALU_XOR   : result = operand_a ^ operand_b;
            ALU_SLL   : result = operand_a << shamt;
            ALU_SRL   : result = operand_a >> shamt;
            ALU_SRA   : result = $signed(operand_a) >>> shamt;
            ALU_SLT   : result = {31'b0, ($signed(operand_a) < $signed(operand_b))};
            ALU_SLTU  : result = {31'b0, (operand_a < operand_b)};
            ALU_PASS_B: result = operand_b;   // LUI: pass immediate straight through
            default   : result = {XLEN{1'b0}};
        endcase
    end

    assign zero_flag = (result == {XLEN{1'b0}});

endmodule : rv32_alu
