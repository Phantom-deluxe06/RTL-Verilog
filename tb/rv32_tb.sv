// ============================================================================
// File        : rv32_tb.sv
// Description : Self-checking testbench for the RV32IM SoC.
//               Preloads SRAM with a small hand-assembled RV32I/M program,
//               runs for a fixed number of cycles, then verifies register
//               file state and memory contents.
// Project     : 1-TOPS — Team Infinity
// ============================================================================
//
// TEST PROGRAM (hand-assembled RV32IM machine code):
// --------------------------------------------------
// Addr  Hex          Assembly              Description
// 0x00  0x00500093   ADDI  x1, x0, 5      x1 = 5
// 0x04  0x00A00113   ADDI  x2, x0, 10     x2 = 10
// 0x08  0x002081B3   ADD   x3, x1, x2     x3 = x1 + x2 = 15
// 0x0C  0x40208233   SUB   x4, x1, x2     x4 = x1 - x2 = -5 (0xFFFFFFB)
// 0x10  0x0020F2B3   AND   x5, x1, x2     x5 = x1 & x2 = 0
// 0x14  0x0020E333   OR    x6, x1, x2     x6 = x1 | x2 = 15
// 0x18  0x002093B3   SLL   x7, x1, x2     x7 = x1 << (x2[4:0]) = 5 << 10 = 5120
// 0x1C  0x0020A433   SLT   x8, x1, x2     x8 = (x1 < x2) ? 1 : 0 = 1
// 0x20  0x00302023   SW    x3, 0(x0)      mem[0x100] = reserved, use 0x100 below
//       — actually store to address 0x100: 0x10002023 won't fit, use different encoding:
// 0x20  0x003024A3   SW    x3, 0x09*4(x0) — simplified: let's use immediate store
//
// We'll use a cleaner test sequence:
// 0x00  ADDI x1, x0, 5         →  x1 = 5
// 0x04  ADDI x2, x0, 10        →  x2 = 10
// 0x08  ADD  x3, x1, x2        →  x3 = 15
// 0x0C  SUB  x4, x1, x2        →  x4 = -5
// 0x10  AND  x5, x1, x2        →  x5 = 0
// 0x14  OR   x6, x1, x2        →  x6 = 15
// 0x18  XOR  x7, x1, x2        →  x7 = 15
// 0x1C  SLT  x8, x1, x2        →  x8 = 1
// 0x20  SLTU x9, x1, x2        →  x9 = 1
// 0x24  SLLI x10, x1, 3        →  x10 = 40
// 0x28  SRLI x11, x2, 1        →  x11 = 5
// 0x2C  LUI  x12, 0x12345      →  x12 = 0x12345000
// 0x30  SW   x3, 0x400(x0)     →  mem[0x400] = 15
// 0x34  LW   x13, 0x400(x0)    →  x13 = 15 (load back)
// 0x38  BEQ  x3, x13, +8       →  branch to 0x40 (x3 == x13 == 15)
// 0x3C  ADDI x14, x0, 0xFF     →  SKIPPED if branch taken
// 0x40  ADDI x15, x0, 0x42     →  x15 = 0x42 (branch lands here)
// 0x44  JAL  x16, +8           →  x16 = 0x48, jump to 0x4C
// 0x48  ADDI x17, x0, 0xFF     →  SKIPPED (jumped over)
// 0x4C  ADDI x18, x0, 0x55     →  x18 = 0x55
// --- M-extension test ---
// 0x50  MUL  x19, x1, x2       →  x19 = 5*10 = 50
// 0x54  ADDI x20, x0, -1       →  x20 = 0xFFFFFFFF (-1)
// 0x58  DIV  x21, x2, x1       →  x21 = 10/5 = 2
// 0x5C  REM  x22, x2, x1       →  x22 = 10%5 = 0
// 0x60  NOP  (ADDI x0, x0, 0)  →  stall / end marker
// 0x64  NOP
// 0x68  NOP
// ============================================================================

`timescale 1ns / 1ps

module rv32_tb;

    // ---------------------------------------------------------------
    //  Clock and reset
    // ---------------------------------------------------------------
    logic clk, rst_n;
    logic irq;
    logic dma_req;
    logic [31:0] dma_addr, dma_wdata;
    logic dma_we;
    logic [31:0] dma_rdata;
    logic dma_grant;

    // Clock generation: 10 ns period (100 MHz)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------------
    //  DUT instantiation
    // ---------------------------------------------------------------
    rv32_soc_top u_soc (
        .clk       (clk),
        .rst_n     (rst_n),
        .irq       (irq),
        .dma_req   (dma_req),
        .dma_addr  (dma_addr),
        .dma_wdata (dma_wdata),
        .dma_we    (dma_we),
        .dma_rdata (dma_rdata),
        .dma_grant (dma_grant)
    );

    // ---------------------------------------------------------------
    //  Convenience: hierarchical access to internals for checking
    // ---------------------------------------------------------------
    // Register file values (via hierarchy)
    `define RF u_soc.u_core.u_regfile.reg_file
    `define PC u_soc.u_core.u_pc.pc_out

    // ---------------------------------------------------------------
    //  Test program — hand-assembled machine code
    // ---------------------------------------------------------------
    task load_program();
        // ADDI x1, x0, 5         (I-type: imm=5, rs1=0, funct3=000, rd=1, opcode=0010011)
        u_soc.sram[0]  = 32'h00500093;
        // ADDI x2, x0, 10
        u_soc.sram[1]  = 32'h00A00113;
        // ADD  x3, x1, x2        (R-type: funct7=0, rs2=2, rs1=1, funct3=000, rd=3, opcode=0110011)
        u_soc.sram[2]  = 32'h002081B3;
        // SUB  x4, x1, x2        (R-type: funct7=0100000)
        u_soc.sram[3]  = 32'h40208233;
        // AND  x5, x1, x2
        u_soc.sram[4]  = 32'h0020F2B3;
        // OR   x6, x1, x2
        u_soc.sram[5]  = 32'h0020E333;
        // XOR  x7, x1, x2
        u_soc.sram[6]  = 32'h0020C3B3;
        // SLT  x8, x1, x2
        u_soc.sram[7]  = 32'h0020A433;
        // SLTU x9, x1, x2
        u_soc.sram[8]  = 32'h0020B4B3;
        // SLLI x10, x1, 3        (I-type shift: imm[11:5]=0, shamt=3)
        u_soc.sram[9]  = 32'h00309513;
        // SRLI x11, x2, 1
        u_soc.sram[10] = 32'h00115593;
        // LUI  x12, 0x12345
        u_soc.sram[11] = 32'h12345637;
        // SW   x3, 0x400(x0)     (S-type: offset=0x400=1024)
        // imm[11:5]=0100000, rs2=3(x3), rs1=0(x0), funct3=010, imm[4:0]=00000
        u_soc.sram[12] = 32'h40302023;
        // LW   x13, 0x400(x0)    (I-type: imm=0x400)
        u_soc.sram[13] = 32'h40002683;
        // BEQ  x3, x13, +8       (B-type: offset=8 → imm[12|10:5]=0, imm[4:1|11]=0100)
        // Target = 0x38 + 8 = 0x40.  Encoding:  imm=8 → {0, 000000, 01101, 00011, 000, 0100, 0, 1100011}
        u_soc.sram[14] = 32'h00D68463;
        // ADDI x14, x0, 0xFF     (this should be SKIPPED by branch)
        u_soc.sram[15] = 32'h0FF00713;
        // ADDI x15, x0, 0x42     (branch target: addr 0x40)
        u_soc.sram[16] = 32'h04200793;
        // JAL  x16, +8           (J-type: offset=8, rd=x16)
        // Jump from 0x44 to 0x4C.  imm=8 → {0, 0000000100, 0, 00000000, rd=10000, 1101111}
        u_soc.sram[17] = 32'h0080086F;
        // ADDI x17, x0, 0xFF     (SKIPPED by JAL)
        u_soc.sram[18] = 32'h0FF00893;
        // ADDI x18, x0, 0x55     (JAL target: addr 0x4C)
        u_soc.sram[19] = 32'h05500913;
        // MUL  x19, x1, x2       (R-type: funct7=0000001, funct3=000, M-ext)
        u_soc.sram[20] = 32'h022089B3;
        // ADDI x20, x0, -1
        u_soc.sram[21] = 32'hFFF00A13;
        // DIV  x21, x2, x1       (funct7=0000001, funct3=100)
        u_soc.sram[22] = 32'h02114AB3;
        // REM  x22, x2, x1       (funct7=0000001, funct3=110)
        u_soc.sram[23] = 32'h02116B33;
        // NOP (ADDI x0, x0, 0)   — end markers
        u_soc.sram[24] = 32'h00000013;
        u_soc.sram[25] = 32'h00000013;
        u_soc.sram[26] = 32'h00000013;
        u_soc.sram[27] = 32'h00000013;
    endtask

    // ---------------------------------------------------------------
    //  Checker task
    // ---------------------------------------------------------------
    int pass_count, fail_count;

    task check_reg(input int reg_num, input logic [31:0] expected, input string name);
        logic [31:0] actual;
        if (reg_num == 0)
            actual = 32'b0;
        else
            actual = `RF[reg_num];

        if (actual === expected) begin
            $display("[PASS] %s : x%0d = 0x%08h", name, reg_num, actual);
            pass_count++;
        end else begin
            $error("[FAIL] %s : x%0d = 0x%08h, expected 0x%08h", name, reg_num, actual, expected);
            fail_count++;
        end
    endtask

    // ---------------------------------------------------------------
    //  Main test sequence
    // ---------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;

        // Idle DMA and IRQ
        irq      = 1'b0;
        dma_req  = 1'b0;
        dma_addr = 32'b0;
        dma_wdata= 32'b0;
        dma_we   = 1'b0;

        // Reset
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);

        // Load program into SRAM (during reset)
        load_program();

        // Release reset
        rst_n = 1'b1;

        // Run for enough cycles to execute all instructions
        // Each instruction takes 1 cycle; we have ~28 instructions
        // plus branches/jumps.  40 cycles is plenty.
        repeat (40) @(posedge clk);

        // -------------------------------------------------------
        //  Verify register state
        // -------------------------------------------------------
        $display("\n========================================");
        $display("  RV32IM SoC — Self-Check Results");
        $display("========================================\n");

        check_reg(1,  32'h0000_0005, "ADDI x1, x0, 5");
        check_reg(2,  32'h0000_000A, "ADDI x2, x0, 10");
        check_reg(3,  32'h0000_000F, "ADD  x3, x1, x2");
        check_reg(4,  32'hFFFF_FFFB, "SUB  x4, x1, x2");
        check_reg(5,  32'h0000_0000, "AND  x5, x1, x2");
        check_reg(6,  32'h0000_000F, "OR   x6, x1, x2");
        check_reg(7,  32'h0000_000F, "XOR  x7, x1, x2");
        check_reg(8,  32'h0000_0001, "SLT  x8, x1, x2");
        check_reg(9,  32'h0000_0001, "SLTU x9, x1, x2");
        check_reg(10, 32'h0000_0028, "SLLI x10, x1, 3");
        check_reg(11, 32'h0000_0005, "SRLI x11, x2, 1");
        check_reg(12, 32'h1234_5000, "LUI  x12, 0x12345");

        // SW x3, 0x400(x0) stores 15 at word address 0x400/4 = 256
        // LW x13, 0x400(x0) reads it back
        check_reg(13, 32'h0000_000F, "LW   x13, 0x400(x0)");

        // BEQ x3, x13, +8 → branch taken, x14 should NOT be written
        check_reg(14, 32'h0000_0000, "BEQ  skip: x14 unwritten");

        // ADDI x15, x0, 0x42 → branch target
        check_reg(15, 32'h0000_0042, "ADDI x15, x0, 0x42");

        // JAL x16, +8 → x16 = PC(0x44) + 4 = 0x48
        check_reg(16, 32'h0000_0048, "JAL  x16, +8 (link)");

        // x17 should be SKIPPED (jumped over)
        check_reg(17, 32'h0000_0000, "JAL  skip: x17 unwritten");

        // ADDI x18, x0, 0x55
        check_reg(18, 32'h0000_0055, "ADDI x18, x0, 0x55");

        // M-extension tests
        check_reg(19, 32'h0000_0032, "MUL  x19, x1, x2  (5*10=50)");
        check_reg(20, 32'hFFFF_FFFF, "ADDI x20, x0, -1");
        check_reg(21, 32'h0000_0002, "DIV  x21, x2, x1  (10/5=2)");
        check_reg(22, 32'h0000_0000, "REM  x22, x2, x1  (10%5=0)");

        // -------------------------------------------------------
        //  Memory check: sram[256] (addr 0x400) should be 15
        // -------------------------------------------------------
        if (u_soc.sram[256] === 32'h0000_000F) begin
            $display("[PASS] MEM[0x400] = 0x%08h", u_soc.sram[256]);
            pass_count++;
        end else begin
            $error("[FAIL] MEM[0x400] = 0x%08h, expected 0x0000000F", u_soc.sram[256]);
            fail_count++;
        end

        // -------------------------------------------------------
        //  Summary
        // -------------------------------------------------------
        $display("\n========================================");
        if (fail_count == 0)
            $display("  *** ALL %0d TESTS PASSED ***", pass_count);
        else
            $display("  *** %0d PASSED, %0d FAILED ***", pass_count, fail_count);
        $display("========================================\n");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #5000;
        $error("TIMEOUT: Simulation exceeded 5000 ns");
        $finish;
    end

endmodule : rv32_tb
