`timescale 1ns/1ps
// =============================================================================
// Compliance testbench for RISC-V 5-stage pipeline CPU
//
// The riscv-compliance test programs:
//   1. Execute the instruction-under-test and store results in the "signature"
//      data region (begin_signature … end_signature in the linked binary).
//   2. Loop forever writing to address 0x0000_1000 (tohost) to signal done.
//   3. After that write the testbench dumps the signature region to
//      "signature.output" for comparison with the golden reference.
//
// Signature region (for the pre-compiled rv32i binaries in this repo):
//   begin_signature = 0x2000  →  word index 0x800  = 2048
//   end_signature   = 0x2090  →  36 words (0x90 bytes / 4)
//
// Memory layout:
//   The flat binary (code + .data + signature area) is loaded into both
//   instruction memory and data memory so that the separated Harvard
//   architecture emulates the unified memory the test programs expect.
// =============================================================================

module tinyriscv_soc_tb;

    // -------------------------------------------------------------------------
    // Clock / reset
    // -------------------------------------------------------------------------
    reg clk;
    reg rst_n;

    initial clk = 0;
    always  #10 clk = ~clk;          // 50 MHz

    initial begin
        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;
    end

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    wire [31:0] gpio_out;
    wire [31:0] gpio_in;
    wire [31:0] seg_display;
    wire        uart_tx;
    wire [ 7:0] leds;

    assign gpio_in = 32'b0;

    riscv_soc u_soc (
        .clk         (clk),
        .rst_n       (rst_n),
        .gpio_out    (gpio_out),
        .gpio_in     (gpio_in),
        .seg_display (seg_display),
        .uart_tx     (uart_tx),
        .uart_rx     (1'b1),
        .leds        (leds)
    );

    // -------------------------------------------------------------------------
    // Memory initialisation
    // -------------------------------------------------------------------------
    initial begin
        #1;
        $readmemh("inst.data", u_soc.u_imem.mem);
        $readmemh("inst.data", u_soc.u_dmem.mem);
    end

    // -------------------------------------------------------------------------
    // Detect tohost write (address 0x0000_1000, write enable asserted)
    // -------------------------------------------------------------------------
    // Signature dump parameters – read from plusargs, defaults match most rv32i binaries
    // CPU resets to PC=0x8000_0000; compliance binaries are linked at 0x0
    // but auipc shifts tohost address by 0x8000_0000 at runtime.
    localparam TOHOST_ADDR = 32'h8000_1000;

    integer SIG_BASE_WORD;
    integer SIG_WORDS;
    initial begin
        if (!$value$plusargs("sig_base=%d", SIG_BASE_WORD)) SIG_BASE_WORD = 32'h800;
        if (!$value$plusargs("sig_words=%d", SIG_WORDS))     SIG_WORDS     = 36;
    end

    reg  tohost_seen;
    initial tohost_seen = 0;

    always @(posedge clk) begin
        if (rst_n && !tohost_seen) begin
            if (u_soc.dmem_wen && (u_soc.dmem_addr == TOHOST_ADDR))
                tohost_seen <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Dump signature and end simulation
    // -------------------------------------------------------------------------
    integer sig_fd;
    integer sig_i;
    integer timeout_cnt;

    initial timeout_cnt = 0;

    always @(posedge clk) begin
        if (rst_n) begin
            timeout_cnt = timeout_cnt + 1;
            if (timeout_cnt > 500000) begin
                $display("COMPLIANCE_TIMEOUT");
                $finish;
            end
        end
    end

    initial begin
        wait (tohost_seen == 1'b1);
        #20;   // Allow the final store to complete

        sig_fd = $fopen("signature.output", "w");
        if (sig_fd == 0) begin
            $display("ERROR: cannot open signature.output");
            $finish;
        end
        for (sig_i = 0; sig_i < SIG_WORDS; sig_i = sig_i + 1)
            $fwrite(sig_fd, "%08x\n", u_soc.u_dmem.mem[SIG_BASE_WORD + sig_i]);
        $fclose(sig_fd);
        $finish;
    end

endmodule
