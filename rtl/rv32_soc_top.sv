// ============================================================================
// File        : rv32_soc_top.sv
// Description : SoC top-level integrating the RV32IM core with:
//                 • 64 KB unified on-chip SRAM (AHB-Lite slave)
//                 • DMA port for shared-memory access (AI Accelerator)
//                 • IRQ input from the AI Accelerator
//               The memory model is a simple synchronous SRAM behind an
//               AHB-Lite slave wrapper with zero-wait-state reads.
// Project     : 1-TOPS — Team Infinity
// Target      : 65nm SCL CMOS ASIC
// ============================================================================

import pkg_rv32_types::*;

module rv32_soc_top (
    input  logic             clk,
    input  logic             rst_n,

    // --- External interrupt (from AI Accelerator) ---
    input  logic             irq,

    // --- DMA port (shared-memory access for AI Accelerator) ---
    input  logic             dma_req,        // DMA request: hold CPU, take bus
    input  logic [XLEN-1:0]  dma_addr,       // DMA byte address
    input  logic [XLEN-1:0]  dma_wdata,      // DMA write data
    input  logic             dma_we,         // DMA write enable
    output logic [XLEN-1:0]  dma_rdata,      // DMA read data
    output logic             dma_grant       // DMA access granted
);

    // =================================================================
    //  AHB-Lite signals between core and memory
    // =================================================================
    logic [XLEN-1:0] HADDR;
    logic [2:0]      HSIZE;
    logic [1:0]      HTRANS;
    logic            HWRITE;
    logic [XLEN-1:0] HWDATA;
    logic [2:0]      HBURST;
    logic [3:0]      HPROT;
    logic [XLEN-1:0] HRDATA;
    logic            HREADY;
    logic            HRESP;

    // =================================================================
    //  DMA arbiter — simple priority: DMA request stalls CPU
    //
    //  When dma_req is asserted:
    //    1. CPU is stalled (dma_stall = 1)
    //    2. SRAM port is steered to the DMA address/data
    //    3. dma_grant acknowledges the access
    // =================================================================
    logic dma_stall;
    assign dma_stall = dma_req;
    assign dma_grant = dma_req;   // Grant is immediate (single-cycle SRAM)

    // =================================================================
    //  CPU Core
    // =================================================================
    logic [XLEN-1:0] instr_addr;
    logic [XLEN-1:0] instr_rdata;

    rv32_core u_core (
        .clk         (clk),
        .rst_n       (rst_n),
        .irq         (irq),
        .dma_stall   (dma_stall),
        .instr_addr  (instr_addr),
        .instr_rdata (instr_rdata),
        .HADDR       (HADDR),
        .HSIZE     (HSIZE),
        .HTRANS    (HTRANS),
        .HWRITE    (HWRITE),
        .HWDATA    (HWDATA),
        .HBURST    (HBURST),
        .HPROT     (HPROT),
        .HRDATA    (HRDATA),
        .HREADY    (HREADY),
        .HRESP     (HRESP)
    );

    // =================================================================
    //  Unified 64 KB SRAM — AHB-Lite slave with DMA mux
    //
    //  Memory map: 0x0000_0000 to 0x0000_FFFF  (64 KB)
    //  Word-addressed internally: addr[15:2] selects one of 16384 words.
    //
    //  For the single-cycle design the SRAM is modeled as a simple
    //  combinational-read / synchronous-write array.  The 65nm SCL
    //  foundry SRAM compiler will produce a macro with similar timing.
    // =================================================================

    // SRAM storage
    logic [XLEN-1:0] sram [0:MEM_DEPTH-1];

    // Address / data steering: DMA or CPU
    logic [XLEN-1:0]  mem_addr;
    logic [XLEN-1:0]  mem_wdata;
    logic              mem_we;

    always @(*) begin
        if (dma_req) begin
            mem_addr  = dma_addr;
            mem_wdata = dma_wdata;
            mem_we    = dma_we;
        end else begin
            mem_addr  = HADDR;
            mem_wdata = HWDATA;
            mem_we    = HWRITE & (HTRANS != AHB_IDLE);
        end
    end

    // Word-aligned address index
    logic [13:0] word_addr;
    assign word_addr = mem_addr[15:2];

    // -----------------------------------------------------------------
    //  SRAM write — synchronous (posedge clk)
    //  Supports byte / half-word / word writes via byte-lane masking
    // -----------------------------------------------------------------
    logic [2:0] active_size;
    assign active_size = dma_req ? AHB_SIZE_WORD : HSIZE;

    always_ff @(posedge clk) begin
        if (mem_we) begin
            case (active_size)
                AHB_SIZE_BYTE: begin
                    case (mem_addr[1:0])
                        2'b00: sram[word_addr][7:0]   <= mem_wdata[7:0];
                        2'b01: sram[word_addr][15:8]  <= mem_wdata[7:0];
                        2'b10: sram[word_addr][23:16] <= mem_wdata[7:0];
                        2'b11: sram[word_addr][31:24] <= mem_wdata[7:0];
                    endcase
                end
                AHB_SIZE_HALF: begin
                    if (mem_addr[1])
                        sram[word_addr][31:16] <= mem_wdata[15:0];
                    else
                        sram[word_addr][15:0]  <= mem_wdata[15:0];
                end
                default: // AHB_SIZE_WORD
                    sram[word_addr] <= mem_wdata;
            endcase
        end
    end

    // -----------------------------------------------------------------
    //  SRAM read — combinational (for single-cycle access)
    //  DUAL PORT: One for Data/DMA, one for Instruction Fetch
    // -----------------------------------------------------------------
    logic [XLEN-1:0] mem_rdata;
    assign mem_rdata = sram[word_addr];

    logic [13:0] instr_word_addr;
    assign instr_word_addr = instr_addr[15:2];
    assign instr_rdata = sram[instr_word_addr];

    // Route data read to CPU and DMA
    assign HRDATA   = mem_rdata;
    assign dma_rdata = mem_rdata;

    // -----------------------------------------------------------------
    //  AHB-Lite slave response — always OKAY, always ready
    //  (single-cycle SRAM, no wait states)
    // -----------------------------------------------------------------
    assign HREADY = 1'b1;
    assign HRESP  = AHB_OKAY;

endmodule : rv32_soc_top
