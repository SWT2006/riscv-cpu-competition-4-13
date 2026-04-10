`timescale 1ns/1ps
// CSR register file.
// Supports mstatus(0x300), mtvec(0x305), mepc(0x341), mcause(0x342), mtval(0x343).
//
// IMPORTANT: mtvec resets to 0, NOT to 0x4.
// Software is responsible for initialising mtvec before enabling traps.
module csr_unit (
    input  wire        clk,
    input  wire        cpu_rst,       // active-high synchronous reset
    // ID-stage combinatorial read (based on current IF/ID instruction CSR addr)
    input  wire [11:0] csr_raddr,
    output reg  [31:0] csr_rdata,
    // EX-stage CSR instruction write
    input  wire        csr_wen,
    input  wire [11:0] csr_waddr,
    input  wire [31:0] csr_wdata,
    // EX-stage trap (ECALL or other exception)
    input  wire        trap_valid,    // asserted for one cycle when trap fires
    input  wire [31:0] trap_epc,      // PC of trapping instruction
    input  wire [31:0] trap_mcause,   // exception cause code
    // Direct outputs consumed by EX stage for branch targets
    output reg  [31:0] mtvec,
    output reg  [31:0] mepc
);
    reg [31:0] mcause;
    reg [31:0] mstatus;
    reg [31:0] mtval;
    reg [31:0] mscratch;

    always @(posedge clk) begin
        if (cpu_rst) begin
            mtvec    <= 32'h0000_0000;  // software must set this before trapping
            mepc     <= 32'h0;
            mcause   <= 32'h0;
            mstatus  <= 32'h0;
            mtval    <= 32'h0;
            mscratch <= 32'h0;
        end else begin
            // Trap update has priority over CSR instruction writes for mepc/mcause/mtval
            if (trap_valid) begin
                mepc   <= trap_epc;
                mcause <= trap_mcause;
            end
            if (csr_wen) begin
                case (csr_waddr)
                    12'h300: mstatus  <= csr_wdata;
                    12'h305: mtvec    <= csr_wdata;
                    12'h340: mscratch <= csr_wdata;
                    12'h341: if (!trap_valid) mepc   <= csr_wdata;
                    12'h342: if (!trap_valid) mcause <= csr_wdata;
                    12'h343: if (!trap_valid) mtval  <= csr_wdata;
                    default: ;
                endcase
            end
        end
    end

    // Combinatorial read
    always @(*) begin
        case (csr_raddr)
            12'h300: csr_rdata = mstatus;
            12'h305: csr_rdata = mtvec;
            12'h340: csr_rdata = mscratch;
            12'h341: csr_rdata = mepc;
            12'h342: csr_rdata = mcause;
            12'h343: csr_rdata = mtval;
            default: csr_rdata = 32'h0;
        endcase
    end

endmodule
