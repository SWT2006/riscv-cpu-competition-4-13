`timescale 1ns/1ps
// EX stage: ALU, branch comparison, jump/trap target, CSR write data.
// Misalignment exception detection is intentionally omitted to shorten the
// critical path; the competition software does not require it.
module stage_ex (
    input  wire [31:0] idex_pc,
    input  wire [31:0] idex_pc_plus4,
    input  wire [31:0] idex_rs1_data,
    input  wire [31:0] idex_rs2_data,
    input  wire [31:0] idex_imm,
    input  wire [4:0]  idex_rs1_addr,
    input  wire [4:0]  idex_rs2_addr,
    input  wire [4:0]  idex_alu_op,
    input  wire        idex_alu_src,
    input  wire        idex_branch,
    input  wire        idex_jal,
    input  wire        idex_jalr,
    input  wire        idex_auipc,
    input  wire [2:0]  idex_funct3,
    input  wire        idex_ecall,
    input  wire        idex_mret,
    input  wire        idex_csr_op,
    input  wire [31:0] idex_csr_rdata,
    input  wire [11:0] idex_csr_addr,
    // CSR outputs for ECALL/MRET branch targets (registered in csr_unit)
    input  wire [31:0] csr_mtvec,
    input  wire [31:0] csr_mepc,
    // Forwarding inputs
    input  wire [1:0]  forward_a,
    input  wire [1:0]  forward_b,
    input  wire [31:0] exmem_alu_result,
    input  wire [1:0]  exmem_wb_sel,
    input  wire [31:0] exmem_pc_plus4,
    input  wire [31:0] wb_write_data,
    // Outputs
    output wire [31:0] alu_result,
    output wire [31:0] rs2_data_fwd,   // forwarded rs2 (for store data)
    output wire        branch_taken,
    output wire [31:0] branch_target,
    // Trap outputs → csr_unit
    output wire        trap_valid,
    output wire [31:0] trap_epc,
    output wire [31:0] trap_mcause,
    // CSR instruction write → csr_unit
    output wire        csr_wen,
    output wire [11:0] csr_waddr,
    output wire [31:0] csr_wdata
);

    localparam ALU_ADD    = 5'd0;
    localparam ALU_SUB    = 5'd1;
    localparam ALU_SLL    = 5'd2;
    localparam ALU_SLT    = 5'd3;
    localparam ALU_SLTU   = 5'd4;
    localparam ALU_XOR    = 5'd5;
    localparam ALU_SRL    = 5'd6;
    localparam ALU_SRA    = 5'd7;
    localparam ALU_OR     = 5'd8;
    localparam ALU_AND    = 5'd9;
    localparam ALU_PASS_B = 5'd10;
    localparam ALU_MUL    = 5'd11;
    localparam ALU_MULH   = 5'd12;
    localparam ALU_MULHSU = 5'd13;
    localparam ALU_MULHU  = 5'd14;
    localparam ALU_DIV    = 5'd15;
    localparam ALU_DIVU   = 5'd16;
    localparam ALU_REM    = 5'd17;
    localparam ALU_REMU   = 5'd18;

    // ---------------------------------------------------------------
    // Forwarding muxes
    // EX/MEM forwards pc_plus4 (not alu_result) when prev instr is JAL/JALR.
    // ---------------------------------------------------------------
    wire [31:0] exmem_fwd = (exmem_wb_sel == 2'b10) ? exmem_pc_plus4 : exmem_alu_result;

    reg [31:0] fwd_a, fwd_b;
    always @(*) begin
        case (forward_a)
            2'b10:   fwd_a = exmem_fwd;
            2'b01:   fwd_a = wb_write_data;
            default: fwd_a = idex_rs1_data;
        endcase
    end
    always @(*) begin
        case (forward_b)
            2'b10:   fwd_b = exmem_fwd;
            2'b01:   fwd_b = wb_write_data;
            default: fwd_b = idex_rs2_data;
        endcase
    end

    assign rs2_data_fwd = fwd_b;

    // ---------------------------------------------------------------
    // ALU operand selection
    // ---------------------------------------------------------------
    wire [31:0] alu_a = idex_auipc ? idex_pc  : fwd_a;
    wire [31:0] alu_b = idex_alu_src ? idex_imm : fwd_b;

    // ---------------------------------------------------------------
    // ALU (RV32IM)
    // ---------------------------------------------------------------
    wire signed [31:0] sa = $signed(alu_a);
    wire signed [31:0] sb = $signed(alu_b);
    wire        [63:0] mul_uu = alu_a * alu_b;
    wire signed [63:0] mul_ss = sa * sb;
    wire signed [63:0] mul_su = sa * $signed({1'b0, alu_b});

    reg [31:0] alu_out;
    always @(*) begin
        case (idex_alu_op)
            ALU_ADD:    alu_out = alu_a + alu_b;
            ALU_SUB:    alu_out = alu_a - alu_b;
            ALU_SLL:    alu_out = alu_a << alu_b[4:0];
            ALU_SLT:    alu_out = (sa < sb) ? 32'd1 : 32'd0;
            ALU_SLTU:   alu_out = (alu_a < alu_b) ? 32'd1 : 32'd0;
            ALU_XOR:    alu_out = alu_a ^ alu_b;
            ALU_SRL:    alu_out = alu_a >> alu_b[4:0];
            ALU_SRA:    alu_out = $signed(alu_a) >>> alu_b[4:0];
            ALU_OR:     alu_out = alu_a | alu_b;
            ALU_AND:    alu_out = alu_a & alu_b;
            ALU_PASS_B: alu_out = alu_b;
            ALU_MUL:    alu_out = mul_ss[31:0];
            ALU_MULH:   alu_out = mul_ss[63:32];
            ALU_MULHSU: alu_out = mul_su[63:32];
            ALU_MULHU:  alu_out = mul_uu[63:32];
            ALU_DIV:    alu_out = (alu_b == 0) ? 32'hFFFF_FFFF :
                                  (alu_a == 32'h8000_0000 && alu_b == 32'hFFFF_FFFF) ? 32'h8000_0000 :
                                  $signed(sa / sb);
            ALU_DIVU:   alu_out = (alu_b == 0) ? 32'hFFFF_FFFF : (alu_a / alu_b);
            ALU_REM:    alu_out = (alu_b == 0) ? alu_a :
                                  (alu_a == 32'h8000_0000 && alu_b == 32'hFFFF_FFFF) ? 32'h0 :
                                  $signed(sa % sb);
            ALU_REMU:   alu_out = (alu_b == 0) ? alu_a : (alu_a % alu_b);
            default:    alu_out = 32'b0;
        endcase
    end

    // CSR instructions: rd gets old CSR value (alu_result = csr_rdata)
    assign alu_result = idex_csr_op ? idex_csr_rdata : alu_out;

    // ---------------------------------------------------------------
    // Branch comparison
    // ---------------------------------------------------------------
    reg branch_cond;
    always @(*) begin
        case (idex_funct3)
            3'b000:  branch_cond = (fwd_a == fwd_b);                   // BEQ
            3'b001:  branch_cond = (fwd_a != fwd_b);                   // BNE
            3'b100:  branch_cond = ($signed(fwd_a) < $signed(fwd_b));  // BLT
            3'b101:  branch_cond = ($signed(fwd_a) >= $signed(fwd_b)); // BGE
            3'b110:  branch_cond = (fwd_a < fwd_b);                    // BLTU
            3'b111:  branch_cond = (fwd_a >= fwd_b);                   // BGEU
            default: branch_cond = 1'b0;
        endcase
    end

    // ---------------------------------------------------------------
    // Branch / jump targets
    // ---------------------------------------------------------------
    wire [31:0] pc_branch = idex_pc + idex_imm;
    wire [31:0] jalr_tgt  = (fwd_a + idex_imm) & 32'hFFFF_FFFE;

    assign branch_taken  = idex_jal | idex_jalr | (idex_branch & branch_cond)
                         | idex_ecall | idex_mret;

    assign branch_target = idex_mret  ? csr_mepc  :
                           idex_ecall ? csr_mtvec :
                           idex_jalr  ? jalr_tgt  :
                                        pc_branch;

    // ---------------------------------------------------------------
    // Trap output (ECALL and EBREAK; distinguished by idex_csr_addr)
    // ---------------------------------------------------------------
    assign trap_valid  = idex_ecall;
    assign trap_epc    = idex_pc;
    // ECALL from M-mode: mcause=11; EBREAK: mcause=3
    assign trap_mcause = (idex_csr_addr == 12'h001) ? 32'd3 : 32'd11;

    // ---------------------------------------------------------------
    // CSR write data (for CSR instructions)
    // ---------------------------------------------------------------
    wire [31:0] zimm = {27'b0, idex_rs1_addr};  // zero-extended immediate for CSRRxI

    reg [31:0] csr_wd;
    always @(*) begin
        case (idex_funct3)
            3'b001: csr_wd = fwd_a;                          // CSRRW
            3'b010: csr_wd = idex_csr_rdata | fwd_a;        // CSRRS
            3'b011: csr_wd = idex_csr_rdata & ~fwd_a;       // CSRRC
            3'b101: csr_wd = zimm;                            // CSRRWI
            3'b110: csr_wd = idex_csr_rdata | zimm;          // CSRRSI
            3'b111: csr_wd = idex_csr_rdata & ~zimm;         // CSRRCI
            default: csr_wd = fwd_a;
        endcase
    end

    assign csr_wen   = idex_csr_op;
    assign csr_waddr = idex_csr_addr;
    assign csr_wdata = csr_wd;

endmodule
