`timescale 1ns/1ps
// Simulation testbench for the 5-stage pipeline CPU + perip_bridge.
// Provides behavioural models for IROM and DRAM so the design can be
// simulated without Vivado IP.  Load a program into irom_model[] and
// dram_model[] before running.
module soc_tb;

    // ---------------------------------------------------------------
    // Clock / reset
    // ---------------------------------------------------------------
    reg clk = 0;
    reg rst = 1;

    always #10 clk = ~clk;   // 50 MHz

    initial begin
        rst = 1;
        repeat (5) @(posedge clk);
        rst = 0;
    end

    // ---------------------------------------------------------------
    // Virtual I/O stimulus
    // ---------------------------------------------------------------
    reg  [63:0] virtual_sw  = 64'hDEAD_BEEF_1234_5678;
    reg  [7:0]  virtual_key = 8'b0;
    wire [31:0] virtual_led;
    wire [39:0] virtual_seg;

    // ---------------------------------------------------------------
    // CPU + bridge under test
    // ---------------------------------------------------------------
    wire [13:0] irom_word_addr;
    wire [31:0] irom_data;
    wire [31:0] perip_addr, perip_wdata, perip_rdata;
    wire        perip_wen;
    wire [1:0]  perip_mask;

    cpu_core u_cpu (
        .cpu_clk    (clk),
        .cpu_rst    (rst),
        .irom_addr  (irom_word_addr),
        .irom_data  (irom_data),
        .perip_addr (perip_addr),
        .perip_wen  (perip_wen),
        .perip_mask (perip_mask),
        .perip_wdata(perip_wdata),
        .perip_rdata(perip_rdata)
    );

    // ---------------------------------------------------------------
    // Behavioural IROM model (16 K words = 64 KB)
    // ---------------------------------------------------------------
    reg [31:0] irom_model [0:16383];

    assign irom_data = irom_model[irom_word_addr];

    // ---------------------------------------------------------------
    // Behavioural DRAM model (16 K words = 64 KB)
    // Mirrors dram_driver read-modify-write behaviour.
    // ---------------------------------------------------------------
    reg [31:0] dram_model [0:16383];

    // Internal bridge wires (replicate decode logic for sim)
    localparam DRAM_BASE = 32'h8010_0000;
    localparam DRAM_END  = 32'h8014_0000;

    wire sel_dram = (perip_addr >= DRAM_BASE) && (perip_addr < DRAM_END);
    wire [13:0] dram_word_idx = perip_addr[15:2];
    wire [1:0]  dram_offset   = perip_addr[1:0];

    // DRAM read (combinatorial)
    wire [31:0] dram_raw = dram_model[dram_word_idx];

    reg [31:0] dram_rout;
    always @(*) begin
        dram_rout = 32'b0;
        if (sel_dram) begin
            case (perip_mask)
                2'b00: case (dram_offset)
                           2'b00: dram_rout = {24'b0, dram_raw[7:0]};
                           2'b01: dram_rout = {24'b0, dram_raw[15:8]};
                           2'b10: dram_rout = {24'b0, dram_raw[23:16]};
                           2'b11: dram_rout = {24'b0, dram_raw[31:24]};
                       endcase
                2'b01: dram_rout = dram_offset[1] ? {16'b0, dram_raw[31:16]}
                                                   : {16'b0, dram_raw[15:0]};
                default: dram_rout = dram_raw;
            endcase
        end
    end

    // DRAM write (synchronous)
    always @(posedge clk) begin
        if (perip_wen && sel_dram) begin
            case (perip_mask)
                2'b00: case (dram_offset)
                           2'b00: dram_model[dram_word_idx][7:0]   <= perip_wdata[7:0];
                           2'b01: dram_model[dram_word_idx][15:8]  <= perip_wdata[7:0];
                           2'b10: dram_model[dram_word_idx][23:16] <= perip_wdata[7:0];
                           2'b11: dram_model[dram_word_idx][31:24] <= perip_wdata[7:0];
                       endcase
                2'b01: if (dram_offset[1])
                           dram_model[dram_word_idx][31:16] <= perip_wdata[15:0];
                       else
                           dram_model[dram_word_idx][15:0]  <= perip_wdata[15:0];
                default: dram_model[dram_word_idx] <= perip_wdata;
            endcase
        end
    end

    // ---------------------------------------------------------------
    // MMIO registers (minimal set for simulation)
    // ---------------------------------------------------------------
    reg [31:0] seg_reg = 32'b0;
    reg [31:0] led_reg = 32'b0;
    reg [31:0] cnt_ms  = 32'b0;
    reg        cnt_run = 1'b0;
    reg [15:0] cnt_sub = 16'b0;

    always @(posedge clk) begin
        if (rst) begin
            seg_reg <= 0; led_reg <= 0; cnt_run <= 0; cnt_sub <= 0; cnt_ms <= 0;
        end else if (perip_wen) begin
            case (perip_addr)
                32'h8020_0020: seg_reg <= perip_wdata;
                32'h8020_0040: led_reg <= perip_wdata;
                32'h8020_0050: begin
                    if (perip_wdata == 32'h8000_0000) begin
                        cnt_run <= 1; cnt_sub <= 0; cnt_ms <= 0;
                    end else if (perip_wdata == 32'hFFFF_FFFF) begin
                        cnt_run <= 0;
                    end
                end
            endcase
        end
        if (cnt_run) begin
            if (cnt_sub == 16'd49999) begin cnt_sub <= 0; cnt_ms <= cnt_ms + 1; end
            else cnt_sub <= cnt_sub + 1;
        end
    end

    reg [31:0] mmio_rdata;
    always @(*) begin
        case (perip_addr)
            32'h8020_0000: mmio_rdata = virtual_sw[31:0];
            32'h8020_0004: mmio_rdata = virtual_sw[63:32];
            32'h8020_0010: mmio_rdata = {24'b0, virtual_key};
            32'h8020_0020: mmio_rdata = seg_reg;
            32'h8020_0050: mmio_rdata = cnt_ms;
            default:       mmio_rdata = 32'hDEAD_BEEF;
        endcase
    end

    assign perip_rdata = sel_dram ? dram_rout : mmio_rdata;

    assign virtual_led = led_reg;
    assign virtual_seg = 40'b0;  // display driver omitted in sim

    // ---------------------------------------------------------------
    // Program loader: load irom.hex at simulation start
    // ---------------------------------------------------------------
    integer j;
    initial begin
        for (j = 0; j < 16384; j = j + 1) irom_model[j] = 32'b0;
        for (j = 0; j < 16384; j = j + 1) dram_model[j] = 32'b0;
        // Load program images:
        $readmemh("irom.hex", irom_model);
        $readmemh("dram.hex", dram_model);
    end

    // ---------------------------------------------------------------
    // Simulation timeout and monitor
    // ---------------------------------------------------------------
    initial begin
        $dumpfile("soc_tb.vcd");
        $dumpvars(0, soc_tb);
        #20_000_000;   // 20 ms sim time
        $display("[TB] Simulation complete. LED=0x%08h SEG=0x%08h CNT=%0d ms",
                 virtual_led, seg_reg, cnt_ms);
        $finish;
    end

    // Print MMIO writes for debug
    always @(posedge clk) begin
        if (!rst && perip_wen) begin
            $display("[%0t ns] STORE addr=0x%08h data=0x%08h mask=%b",
                     $time, perip_addr, perip_wdata, perip_mask);
        end
    end

endmodule
