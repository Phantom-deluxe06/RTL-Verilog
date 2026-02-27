// ============================================================================
// File        : pkg_rv32_types.sv
// Description : Shared type definitions, enums, and parameters for the
//               RV32IM single-cycle RISC-V CPU core.
// Project     : 1-TOPS — Team Infinity
// Target      : 65nm SCL CMOS ASIC
// ============================================================================

package pkg_rv32_types;

  // --------------------------------------------------------------------------
  // Global Parameters
  // --------------------------------------------------------------------------
  parameter int XLEN       = 32;           // Data width
  parameter int ALEN       = 32;           // Address width
  parameter int MEM_DEPTH  = 16384;        // 64 KB / 4 bytes = 16384 words
  parameter int REG_ADDR_W = 5;            // Register address width (x0–x31)

  // Reset / IRQ vectors
  parameter logic [XLEN-1:0] RESET_VECTOR = 32'h0000_0000;
  parameter logic [XLEN-1:0] IRQ_VECTOR   = 32'h0000_0100;  // Default IRQ entry

  // --------------------------------------------------------------------------
  // Opcode Enumeration (inst[6:0])
  // --------------------------------------------------------------------------
  typedef enum logic [6:0] {
    OP_LUI      = 7'b0110111,   // Load Upper Immediate
    OP_AUIPC    = 7'b0010111,   // Add Upper Immediate to PC
    OP_JAL      = 7'b1101111,   // Jump And Link
    OP_JALR     = 7'b1100111,   // Jump And Link Register
    OP_BRANCH   = 7'b1100011,   // Conditional Branch (BEQ/BNE/BLT/BGE/BLTU/BGEU)
    OP_LOAD     = 7'b0000011,   // Load (LB/LH/LW/LBU/LHU)
    OP_STORE    = 7'b0100011,   // Store (SB/SH/SW)
    OP_IMM      = 7'b0010011,   // ALU Immediate (ADDI/SLTI/ANDI/ORI/…)
    OP_REG      = 7'b0110011,   // ALU Register-Register (ADD/SUB/MUL/…)
    OP_FENCE    = 7'b0001111,   // FENCE (treated as NOP)
    OP_SYSTEM   = 7'b1110011    // ECALL / EBREAK (treated as NOP for now)
  } opcode_e;

  // --------------------------------------------------------------------------
  // ALU Operation Enumeration
  // --------------------------------------------------------------------------
  typedef enum logic [3:0] {
    ALU_ADD   = 4'b0000,
    ALU_SUB   = 4'b0001,
    ALU_AND   = 4'b0010,
    ALU_OR    = 4'b0011,
    ALU_XOR   = 4'b0100,
    ALU_SLL   = 4'b0101,
    ALU_SRL   = 4'b0110,
    ALU_SRA   = 4'b0111,
    ALU_SLT   = 4'b1000,
    ALU_SLTU  = 4'b1001,
    ALU_PASS_B= 4'b1010   // Pass operand B (used for LUI)
  } alu_op_e;

  // --------------------------------------------------------------------------
  // M-Extension Operation Enumeration
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    M_MUL     = 3'b000,
    M_MULH    = 3'b001,
    M_MULHSU  = 3'b010,
    M_MULHU   = 3'b011,
    M_DIV     = 3'b100,
    M_DIVU    = 3'b101,
    M_REM     = 3'b110,
    M_REMU    = 3'b111
  } m_op_e;

  // --------------------------------------------------------------------------
  // Immediate Format Enumeration
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    IMM_I = 3'b000,
    IMM_S = 3'b001,
    IMM_B = 3'b010,
    IMM_U = 3'b011,
    IMM_J = 3'b100
  } imm_type_e;

  // --------------------------------------------------------------------------
  // Writeback Source Mux Select
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    WB_ALU    = 3'b000,   // ALU result
    WB_MEM    = 3'b001,   // Memory read data
    WB_PC4    = 3'b010,   // PC + 4 (JAL/JALR link)
    WB_IMM    = 3'b011,   // Upper immediate (LUI)
    WB_MEXT   = 3'b100    // M-extension result
  } wb_sel_e;

  // --------------------------------------------------------------------------
  // PC Source Mux Select
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    PC_PLUS4  = 2'b00,    // Sequential: PC + 4
    PC_BRANCH = 2'b01,    // Branch target
    PC_JUMP   = 2'b10,    // JAL / JALR target
    PC_IRQ    = 2'b11     // Interrupt vector
  } pc_src_e;

  // --------------------------------------------------------------------------
  // Memory Access Size (funct3 for loads/stores)
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    MEM_BYTE   = 3'b000,  // LB  / SB
    MEM_HALF   = 3'b001,  // LH  / SH
    MEM_WORD   = 3'b010,  // LW  / SW
    MEM_BYTE_U = 3'b100,  // LBU
    MEM_HALF_U = 3'b101   // LHU
  } mem_size_e;

  // --------------------------------------------------------------------------
  // AHB-Lite Transfer Type
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    AHB_IDLE   = 2'b00,
    AHB_BUSY   = 2'b01,
    AHB_NONSEQ = 2'b10,
    AHB_SEQ    = 2'b11
  } ahb_trans_e;

  // --------------------------------------------------------------------------
  // AHB-Lite Response
  // --------------------------------------------------------------------------
  typedef enum logic {
    AHB_OKAY  = 1'b0,
    AHB_ERROR = 1'b1
  } ahb_resp_e;

  // --------------------------------------------------------------------------
  // AHB-Lite Burst Size (HSIZE encoding for 8/16/32 bit)
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    AHB_SIZE_BYTE = 3'b000,
    AHB_SIZE_HALF = 3'b001,
    AHB_SIZE_WORD = 3'b010
  } ahb_size_e;

endpackage : pkg_rv32_types
