// ============================================================================
// File        : rv32_branch_unit.sv
// Description : Branch condition evaluator for the RV32IM single-cycle core.
//               Evaluates BEQ, BNE, BLT, BGE, BLTU, BGEU and outputs a
//               single branch_taken flag.
// Project     : 1-TOPS — Team Infinity
// Target      : 65nm SCL CMOS ASIC
// ============================================================================

import pkg_rv32_types::*;

module rv32_branch_unit (
    input  logic             branch_en,    // 1 = instruction is a branch
    input  logic [2:0]       funct3,       // Branch condition encoding
    input  logic [XLEN-1:0]  rs1_data,     // Source register 1
    input  logic [XLEN-1:0]  rs2_data,     // Source register 2

    output logic             branch_taken  // 1 = branch condition met
);

    // Signed interpretations for BLT / BGE
    logic signed [XLEN-1:0] rs1_signed, rs2_signed;
    assign rs1_signed = $signed(rs1_data);
    assign rs2_signed = $signed(rs2_data);

    always @(*) begin
        branch_taken = 1'b0;

        if (branch_en) begin
            case (funct3)
                3'b000: branch_taken = (rs1_data == rs2_data);            // BEQ
                3'b001: branch_taken = (rs1_data != rs2_data);            // BNE
                3'b100: branch_taken = (rs1_signed <  rs2_signed);        // BLT
                3'b101: branch_taken = (rs1_signed >= rs2_signed);        // BGE
                3'b110: branch_taken = (rs1_data   <  rs2_data);          // BLTU
                3'b111: branch_taken = (rs1_data   >= rs2_data);          // BGEU
                default: branch_taken = 1'b0;
            endcase
        end
    end

endmodule : rv32_branch_unit
