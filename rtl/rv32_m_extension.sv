// ============================================================================
// File        : rv32_m_extension.sv
// Description : Modular M-extension block for the RV32IM core.
//               Implements MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU.
//               This block is gated by m_valid and can be excluded from
//               synthesis for area reduction.
// Project     : 1-TOPS — Team Infinity
// Target      : 65nm SCL CMOS ASIC
// ============================================================================
//
// DESIGN NOTE — SINGLE-CYCLE MULTIPLICATION & DIVISION
// -----------------------------------------------------
// For single-cycle compliance, multiplication and division are implemented
// as combinational operators (* , / , %).  The synthesis tool will infer
// appropriate arithmetic cells (e.g., array multiplier, Booth multiplier,
// or DesignWare components for the 65nm library).
//
// Division-by-zero follows the RISC-V spec:
//   DIV  x, y, 0 → -1  (all ones)
//   DIVU x, y, 0 → 2^32 - 1
//   REM  x, y, 0 → x
//   REMU x, y, 0 → x
//
// Overflow case (signed only):
//   DIV  -2^31, -1 → -2^31
//   REM  -2^31, -1 → 0
// ============================================================================

import pkg_rv32_types::*;

module rv32_m_extension (
    input  logic             m_valid,      // Enable — 0 = block is inactive
    input  m_op_e            m_op,         // Operation select (funct3)
    input  logic [XLEN-1:0]  operand_a,   // rs1
    input  logic [XLEN-1:0]  operand_b,   // rs2

    output logic [XLEN-1:0]  m_result     // M-extension result
);

    // Internal 64-bit products for MULH variants
    logic signed [63:0] mul_ss;     // signed   × signed
    logic signed [63:0] mul_su;     // signed   × unsigned
    logic        [63:0] mul_uu;     // unsigned × unsigned

    // Signed / unsigned interpretations
    logic signed [XLEN-1:0] a_signed, b_signed;
    assign a_signed = $signed(operand_a);
    assign b_signed = $signed(operand_b);

    // Combinational products
    assign mul_ss = a_signed * b_signed;
    assign mul_su = a_signed * $signed({1'b0, operand_b});
    assign mul_uu = operand_a * operand_b;

    always @(*) begin
        m_result = {XLEN{1'b0}};

        if (m_valid) begin
            unique case (m_op)
                // -------------------------------------------------------
                // Multiplication
                // -------------------------------------------------------
                M_MUL   : m_result = mul_ss[XLEN-1:0];        // Lower 32 bits
                M_MULH  : m_result = mul_ss[2*XLEN-1:XLEN];   // Upper 32, signed×signed
                M_MULHSU: m_result = mul_su[2*XLEN-1:XLEN];   // Upper 32, signed×unsigned
                M_MULHU : m_result = mul_uu[2*XLEN-1:XLEN];   // Upper 32, unsigned×unsigned

                // -------------------------------------------------------
                // Division — with RISC-V mandated edge-case handling
                // -------------------------------------------------------
                M_DIV: begin
                    if (operand_b == {XLEN{1'b0}})
                        m_result = {XLEN{1'b1}};                       // Div by zero → -1
                    else if (operand_a == 32'h8000_0000 && operand_b == {XLEN{1'b1}})
                        m_result = 32'h8000_0000;                       // Overflow → -2^31
                    else
                        m_result = $unsigned($signed(operand_a) / $signed(operand_b));
                end

                M_DIVU: begin
                    if (operand_b == {XLEN{1'b0}})
                        m_result = {XLEN{1'b1}};                       // Div by zero → max unsigned
                    else
                        m_result = operand_a / operand_b;
                end

                // -------------------------------------------------------
                // Remainder
                // -------------------------------------------------------
                M_REM: begin
                    if (operand_b == {XLEN{1'b0}})
                        m_result = operand_a;                           // Rem by zero → dividend
                    else if (operand_a == 32'h8000_0000 && operand_b == {XLEN{1'b1}})
                        m_result = {XLEN{1'b0}};                       // Overflow → 0
                    else
                        m_result = $unsigned($signed(operand_a) % $signed(operand_b));
                end

                M_REMU: begin
                    if (operand_b == {XLEN{1'b0}})
                        m_result = operand_a;                           // Rem by zero → dividend
                    else
                        m_result = operand_a % operand_b;
                end

                default: m_result = {XLEN{1'b0}};
            endcase
        end
    end

endmodule : rv32_m_extension
