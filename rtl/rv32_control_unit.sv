// ============================================================================
// File        : rv32_control_unit.sv
// Description : Main control decoder for the RV32IM single-cycle core.
//               Decodes opcode, funct3, funct7 → all datapath control signals.
// Project     : 1-TOPS — Team Infinity
// Target      : 65nm SCL CMOS ASIC
// ============================================================================
//
// CRITICAL TIMING NOTE — DECODE (critical-path link #2)
// -------------------------------------------------------
// The control unit is entirely combinational.  It receives the 32-bit
// instruction word from the SRAM read and must produce all control
// signals before the register file, ALU, and memory can proceed.
//
//   SRAM instruction → Control Unit → {reg_read, alu_op, mem_ctrl, …}
//
// Its delay is modest (a few levels of LUT logic), but it fans out to
// every downstream mux in the datapath.
// ============================================================================

import pkg_rv32_types::*;

module rv32_control_unit (
    input  logic [XLEN-1:0]  instruction,  // Full 32-bit instruction

    // ----- Datapath control outputs -----
    output logic             reg_write,     // Write-enable for register file
    output logic             mem_read,      // Load instruction
    output logic             mem_write,     // Store instruction
    output logic             alu_src,       // 0 = rs2,  1 = immediate
    output alu_op_e          alu_op,        // ALU operation select
    output wb_sel_e          wb_sel,        // Writeback mux select
    output logic             branch_en,     // Instruction is a branch
    output logic             jump,          // JAL or JALR
    output logic             is_jalr,       // Specifically JALR (base = rs1)
    output imm_type_e        imm_type,      // Immediate format
    output logic [2:0]       mem_size,      // Byte / Half / Word access
    output logic             m_valid,       // M-extension operation valid
    output logic [2:0]       m_op           // M-extension operation select
);

    // Instruction field extraction
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    assign opcode = instruction[6:0];
    assign funct3 = instruction[14:12];
    assign funct7 = instruction[31:25];

    // -------------------------------------------------------------------
    // Main decode — purely combinational
    // -------------------------------------------------------------------
    always @(*) begin
        // Safe defaults — NOP-like (do nothing, no writes)
        reg_write  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        alu_src    = 1'b0;
        alu_op     = ALU_ADD;
        wb_sel     = WB_ALU;
        branch_en  = 1'b0;
        jump       = 1'b0;
        is_jalr    = 1'b0;
        imm_type   = IMM_I;
        mem_size   = 3'b010;
        m_valid    = 1'b0;
        m_op       = 3'b000;

        case (opcode)

            // =============================================================
            // LUI — Load Upper Immediate
            // =============================================================
            OP_LUI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = ALU_PASS_B;   // Pass immediate through ALU
                wb_sel    = WB_ALU;
                imm_type  = IMM_U;
            end

            // =============================================================
            // AUIPC — Add Upper Immediate to PC
            // =============================================================
            OP_AUIPC: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;         // immediate as operand B
                alu_op    = ALU_ADD;       // PC + imm done in datapath
                wb_sel    = WB_ALU;
                imm_type  = IMM_U;
            end

            // =============================================================
            // JAL — Jump And Link
            // =============================================================
            OP_JAL: begin
                reg_write = 1'b1;
                jump      = 1'b1;
                wb_sel    = WB_PC4;       // rd ← PC + 4
                imm_type  = IMM_J;
            end

            // =============================================================
            // JALR — Jump And Link Register
            // =============================================================
            OP_JALR: begin
                reg_write = 1'b1;
                jump      = 1'b1;
                is_jalr   = 1'b1;
                alu_src   = 1'b1;         // rs1 + imm for target
                alu_op    = ALU_ADD;
                wb_sel    = WB_PC4;       // rd ← PC + 4
                imm_type  = IMM_I;
            end

            // =============================================================
            // BRANCH (BEQ, BNE, BLT, BGE, BLTU, BGEU)
            // =============================================================
            OP_BRANCH: begin
                branch_en = 1'b1;
                alu_src   = 1'b0;         // compare rs1 vs rs2
                alu_op    = ALU_SUB;      // (not used; branch_unit handles comparison)
                imm_type  = IMM_B;
            end

            // =============================================================
            // LOAD (LB, LH, LW, LBU, LHU)
            // =============================================================
            OP_LOAD: begin
                reg_write = 1'b1;
                mem_read  = 1'b1;
                alu_src   = 1'b1;         // rs1 + imm → address
                alu_op    = ALU_ADD;
                wb_sel    = WB_MEM;
                imm_type  = IMM_I;
                mem_size  = funct3;
            end

            // =============================================================
            // STORE (SB, SH, SW)
            // =============================================================
            OP_STORE: begin
                mem_write = 1'b1;
                alu_src   = 1'b1;         // rs1 + imm → address
                alu_op    = ALU_ADD;
                imm_type  = IMM_S;
                mem_size  = funct3;
            end

            // =============================================================
            // ALU Immediate (ADDI, SLTI, SLTIU, XORI, ORI, ANDI,
            //                SLLI, SRLI, SRAI)
            // =============================================================
            OP_IMM: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                imm_type  = IMM_I;
                wb_sel    = WB_ALU;

                case (funct3)
                    3'b000: alu_op = ALU_ADD;   // ADDI
                    3'b010: alu_op = ALU_SLT;   // SLTI
                    3'b011: alu_op = ALU_SLTU;  // SLTIU
                    3'b100: alu_op = ALU_XOR;   // XORI
                    3'b110: alu_op = ALU_OR;    // ORI
                    3'b111: alu_op = ALU_AND;   // ANDI
                    3'b001: alu_op = ALU_SLL;   // SLLI
                    3'b101: begin
                        if (funct7[5]) alu_op = ALU_SRA;
                        else           alu_op = ALU_SRL;
                    end // SRAI / SRLI
                    default: alu_op = ALU_ADD;
                endcase
            end

            // =============================================================
            // ALU Register (ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA,
            //               OR, AND  — and M-ext: MUL, MULH, …, REM, REMU)
            // =============================================================
            OP_REG: begin
                reg_write = 1'b1;
                alu_src   = 1'b0;
                wb_sel    = WB_ALU;

                if (funct7 == 7'b0000001) begin
                    // ---- M-extension operations ----
                    m_valid  = 1'b1;
                    m_op     = funct3;
                    wb_sel   = WB_MEXT;
                end else begin
                    // ---- Base RV32I register-register ----
                    case (funct3)
                        3'b000: begin
                            if (funct7[5]) alu_op = ALU_SUB;
                            else           alu_op = ALU_ADD;
                        end
                        3'b001: alu_op = ALU_SLL;
                        3'b010: alu_op = ALU_SLT;
                        3'b011: alu_op = ALU_SLTU;
                        3'b100: alu_op = ALU_XOR;
                        3'b101: begin
                            if (funct7[5]) alu_op = ALU_SRA;
                            else           alu_op = ALU_SRL;
                        end
                        3'b110: alu_op = ALU_OR;
                        3'b111: alu_op = ALU_AND;
                        default: alu_op = ALU_ADD;
                    endcase
                end
            end

            // =============================================================
            // FENCE — treated as NOP for this core
            // =============================================================
            OP_FENCE: begin
                // No operation
            end

            // =============================================================
            // SYSTEM (ECALL / EBREAK) — treated as NOP
            // =============================================================
            OP_SYSTEM: begin
                // No operation
            end

            default: begin
                // Unknown opcode — all signals remain at safe defaults
            end
        endcase
    end

endmodule : rv32_control_unit
