// ============================================================================
// File        : rv32_core.sv
// Description : Top-level single-cycle RISC-V RV32IM CPU core.
//               Instantiates and wires all sub-modules: PC, register file,
//               immediate generator, control unit, ALU, M-extension,
//               branch unit, and AHB-Lite bus master.
// Project     : 1-TOPS — Team Infinity
// Target      : 65nm SCL CMOS ASIC
// ============================================================================
//
// ╔═══════════════════════════════════════════════════════════════════════════╗
// ║                  CRITICAL TIMING PATH  — Instruction Fetch to Write Back ║
// ╠═══════════════════════════════════════════════════════════════════════════╣
// ║                                                                         ║
// ║  The entire single-cycle datapath must settle within ONE clock period.   ║
// ║  The longest combinational chain is:                                    ║
// ║                                                                         ║
// ║  ┌───────────────────────────────────────────────────────────────────┐   ║
// ║  │  LINK #1: INSTRUCTION FETCH                                      │   ║
// ║  │    PC register → SRAM read (via AHB-Lite) → 32-bit instruction   │   ║
// ║  │    Delay: ~1.5 ns (flop-to-Q) + ~2.0 ns (SRAM access)           │   ║
// ║  ├───────────────────────────────────────────────────────────────────┤   ║
// ║  │  LINK #2: DECODE                                                 │   ║
// ║  │    instruction → control_unit → all control signals              │   ║
// ║  │    instruction → imm_gen → sign-extended immediate               │   ║
// ║  │    Delay: ~0.5 ns (combinational LUT decode)                     │   ║
// ║  ├───────────────────────────────────────────────────────────────────┤   ║
// ║  │  LINK #3: REGISTER READ                                          │   ║
// ║  │    rs1_addr / rs2_addr → register_file → rs1_data / rs2_data     │   ║
// ║  │    Delay: ~0.4 ns (mux tree from 31 entries)                     │   ║
// ║  ├───────────────────────────────────────────────────────────────────┤   ║
// ║  │  LINK #4: EXECUTE                                                │   ║
// ║  │    operands → ALU (add/sub/shift) → result                       │   ║
// ║  │    Delay: ~1.5 ns (32-bit adder or barrel shifter)               │   ║
// ║  ├───────────────────────────────────────────────────────────────────┤   ║
// ║  │  LINK #5: DATA MEMORY ACCESS (loads/stores only)                 │   ║
// ║  │    ALU result → SRAM address → SRAM read → data_rdata            │   ║
// ║  │    Delay: ~2.0 ns (SRAM access, dominant for load instructions)  │   ║
// ║  ├───────────────────────────────────────────────────────────────────┤   ║
// ║  │  LINK #6: WRITE-BACK                                             │   ║
// ║  │    writeback_mux (ALU / MEM / PC+4 / IMM / M-ext) → reg_file WR │   ║
// ║  │    Delay: ~0.3 ns (mux) + setup time at destination flop         │   ║
// ║  └───────────────────────────────────────────────────────────────────┘   ║
// ║                                                                         ║
// ║  TOTAL estimated worst-case (LW instruction):                           ║
// ║    ~1.5 + 2.0 + 0.5 + 0.4 + 1.5 + 2.0 + 0.3 ≈ 8.2 ns                 ║
// ║    → Maximum clock frequency ≈ 120 MHz at 65nm typical corner           ║
// ║                                                                         ║
// ╚═══════════════════════════════════════════════════════════════════════════╝
// ============================================================================

import pkg_rv32_types::*;

module rv32_core (
    input  logic             clk,
    input  logic             rst_n,

    // --- External signals ---
    input  logic             irq,           // Interrupt request (from AI Accelerator)
    input  logic             dma_stall,     // DMA bus-hold: stall CPU

    // --- AHB-Lite master ports (connect to SoC interconnect) ---
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

    // =================================================================
    //  Internal wires
    // =================================================================

    // PC
    logic [XLEN-1:0] pc_out, pc_plus4;
    pc_src_e         pc_src;

    // Instruction
    logic [XLEN-1:0] instruction;

    // Control signals
    logic             reg_write;
    logic             mem_read, mem_write;
    logic             alu_src_sel;
    alu_op_e          alu_op;
    wb_sel_e          wb_sel;
    logic             branch_en, jump, is_jalr;
    imm_type_e        imm_type;
    logic [2:0]      mem_size;
    logic             m_valid;
    logic [2:0]      m_op;

    // Register file
    logic [REG_ADDR_W-1:0] rs1_addr, rs2_addr, rd_addr;
    logic [XLEN-1:0]       rs1_data, rs2_data, rd_data;

    // Immediate
    logic [XLEN-1:0] imm_val;

    // ALU
    logic [XLEN-1:0] alu_operand_a, alu_operand_b, alu_result;
    logic             alu_zero;

    // M-extension
    logic [XLEN-1:0] m_result;

    // Branch
    logic             branch_taken;

    // AHB / memory
    logic [XLEN-1:0] data_rdata;
    logic             bus_stall;

    // Combined stall
    logic             stall;
    assign stall = dma_stall | bus_stall;

    // Branch target address
    logic [XLEN-1:0] branch_target;

    // =================================================================
    //  Instruction field extraction
    // =================================================================
    assign rs1_addr = instruction[19:15];
    assign rs2_addr = instruction[24:20];
    assign rd_addr  = instruction[11:7];

    // =================================================================
    //  PC source mux logic
    // =================================================================
    always @(*) begin
        if (irq)
            pc_src = PC_IRQ;
        else if (jump)
            pc_src = PC_JUMP;
        else if (branch_en && branch_taken)
            pc_src = PC_BRANCH;
        else
            pc_src = PC_PLUS4;
    end

    // =================================================================
    //  Branch / Jump target computation
    //
    //  • Branch: PC + imm_B
    //  • JAL:    PC + imm_J
    //  • JALR:   (rs1 + imm_I) & ~1
    // =================================================================
    always @(*) begin
        if (is_jalr)
            branch_target = (rs1_data + imm_val) & ~32'd1;   // JALR: mask LSB
        else
            branch_target = pc_out + imm_val;                 // Branch / JAL
    end

    // =================================================================
    //  ALU operand muxes
    //
    //  Operand A: for AUIPC, source is PC; otherwise rs1
    //  Operand B: if alu_src=1, use immediate; else rs2
    // =================================================================
    logic is_auipc;
    assign is_auipc = (instruction[6:0] == OP_AUIPC);

    assign alu_operand_a = is_auipc ? pc_out : rs1_data;
    assign alu_operand_b = alu_src_sel ? imm_val : rs2_data;

    // =================================================================
    //  Writeback mux — select data written to register file
    //
    //  CRITICAL TIMING: This mux is the LAST combinational stage
    //  before the register file write port.  Its output must meet
    //  setup timing at the reg_file flip-flops.
    // =================================================================
    logic [XLEN-1:0] mem_load_data;

    // Load data sign/zero extension
    always @(*) begin
        case (mem_size)
            MEM_BYTE:   mem_load_data = {{24{data_rdata[7]}},  data_rdata[7:0]};
            MEM_HALF:   mem_load_data = {{16{data_rdata[15]}}, data_rdata[15:0]};
            MEM_WORD:   mem_load_data = data_rdata;
            MEM_BYTE_U: mem_load_data = {24'b0, data_rdata[7:0]};
            MEM_HALF_U: mem_load_data = {16'b0, data_rdata[15:0]};
            default:    mem_load_data = data_rdata;
        endcase
    end

    always @(*) begin
        case (wb_sel)
            WB_ALU  : rd_data = alu_result;
            WB_MEM  : rd_data = mem_load_data;
            WB_PC4  : rd_data = pc_plus4;
            WB_IMM  : rd_data = imm_val;
            WB_MEXT : rd_data = m_result;
            default : rd_data = alu_result;
        endcase
    end

    // =================================================================
    //  Sub-module instantiations
    // =================================================================

    // ---- Program Counter ----
    rv32_pc u_pc (
        .clk           (clk),
        .rst_n         (rst_n),
        .pc_src        (pc_src),
        .branch_target (branch_target),
        .irq_vector    (32'h0000_0100),
        .stall         (stall),
        .pc_out        (pc_out),
        .pc_plus4      (pc_plus4)
    );

    // ---- Control Unit ----
    rv32_control_unit u_ctrl (
        .instruction   (instruction),
        .reg_write     (reg_write),
        .mem_read      (mem_read),
        .mem_write     (mem_write),
        .alu_src       (alu_src_sel),
        .alu_op        (alu_op),
        .wb_sel        (wb_sel),
        .branch_en     (branch_en),
        .jump          (jump),
        .is_jalr       (is_jalr),
        .imm_type      (imm_type),
        .mem_size       (mem_size),
        .m_valid       (m_valid),
        .m_op          (m_op)
    );

    // ---- Register File ----
    rv32_register_file u_regfile (
        .clk           (clk),
        .rst_n         (rst_n),
        .rs1_addr      (rs1_addr),
        .rs1_data      (rs1_data),
        .rs2_addr      (rs2_addr),
        .rs2_data      (rs2_data),
        .wr_en         (reg_write),
        .rd_addr       (rd_addr),
        .rd_data       (rd_data)
    );

    // ---- Immediate Generator ----
    rv32_imm_gen u_immgen (
        .instruction   (instruction),
        .imm_type      (imm_type),
        .imm_out       (imm_val)
    );

    // ---- ALU (RV32I base) ----
    rv32_alu u_alu (
        .alu_op        (alu_op),
        .operand_a     (alu_operand_a),
        .operand_b     (alu_operand_b),
        .result        (alu_result),
        .zero_flag     (alu_zero)
    );

    // ---- M-Extension (modular, gated) ----
    rv32_m_extension u_mext (
        .m_valid       (m_valid),
        .m_op          (m_op),
        .operand_a     (rs1_data),
        .operand_b     (rs2_data),
        .m_result      (m_result)
    );

    // ---- Branch Unit ----
    rv32_branch_unit u_branch (
        .branch_en     (branch_en),
        .funct3        (instruction[14:12]),
        .rs1_data      (rs1_data),
        .rs2_data      (rs2_data),
        .branch_taken  (branch_taken)
    );

    // ---- AHB-Lite Bus Master ----
    rv32_ahb_lite_master u_ahb (
        .clk           (clk),
        .rst_n         (rst_n),
        .instr_addr    (pc_out),
        .data_addr     (alu_result),
        .data_wdata    (rs2_data),
        .data_read     (mem_read),
        .data_write    (mem_write),
        .data_size     (mem_size),
        .instr_rdata   (instruction),
        .data_rdata    (data_rdata),
        .bus_stall     (bus_stall),
        .HADDR         (HADDR),
        .HSIZE         (HSIZE),
        .HTRANS        (HTRANS),
        .HWRITE        (HWRITE),
        .HWDATA        (HWDATA),
        .HBURST        (HBURST),
        .HPROT         (HPROT),
        .HRDATA        (HRDATA),
        .HREADY        (HREADY),
        .HRESP         (HRESP)
    );

endmodule : rv32_core
