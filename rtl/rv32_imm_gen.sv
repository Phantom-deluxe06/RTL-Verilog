// ============================================================================
// File        : rv32_imm_gen.sv
// Description : Immediate value generator for the RV32IM core.
//               Extracts and sign-extends the immediate field for all five
//               instruction formats: I, S, B, U, J.
// Project     : 1-TOPS — Team Infinity
// Target      : 65nm SCL CMOS ASIC
// ============================================================================

import pkg_rv32_types::*;

module rv32_imm_gen (
    input  logic [XLEN-1:0]  instruction,   // Full 32-bit instruction word
    input  imm_type_e        imm_type,       // Format selector from control unit

    output logic [XLEN-1:0]  imm_out        // Sign-extended immediate
);

    always @(*) begin
        unique case (imm_type)
            // ---------------------------------------------------------------
            // I-type: inst[31:20]  (12 bits, sign-extended)
            //   Used by: ADDI, SLTI, ANDI, ORI, XORI, LW, LH, LB, JALR
            // ---------------------------------------------------------------
            IMM_I: imm_out = {{20{instruction[31]}}, instruction[31:20]};

            // ---------------------------------------------------------------
            // S-type: {inst[31:25], inst[11:7]}  (12 bits, sign-extended)
            //   Used by: SW, SH, SB
            // ---------------------------------------------------------------
            IMM_S: imm_out = {{20{instruction[31]}}, instruction[31:25],
                              instruction[11:7]};

            // ---------------------------------------------------------------
            // B-type: {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}
            //   13-bit signed offset, LSB always 0 (half-word aligned)
            //   Used by: BEQ, BNE, BLT, BGE, BLTU, BGEU
            // ---------------------------------------------------------------
            IMM_B: imm_out = {{19{instruction[31]}}, instruction[31],
                              instruction[7], instruction[30:25],
                              instruction[11:8], 1'b0};

            // ---------------------------------------------------------------
            // U-type: {inst[31:12], 12'b0}  (upper 20 bits)
            //   Used by: LUI, AUIPC
            // ---------------------------------------------------------------
            IMM_U: imm_out = {instruction[31:12], 12'b0};

            // ---------------------------------------------------------------
            // J-type: {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
            //   21-bit signed offset, LSB always 0
            //   Used by: JAL
            // ---------------------------------------------------------------
            IMM_J: imm_out = {{11{instruction[31]}}, instruction[31],
                              instruction[19:12], instruction[20],
                              instruction[30:21], 1'b0};

            default: imm_out = {XLEN{1'b0}};
        endcase
    end

endmodule : rv32_imm_gen
