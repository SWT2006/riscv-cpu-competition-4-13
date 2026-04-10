`timescale 1ns/1ps
// Control unit: pure combinational decode of instruction fields.
// CRITICAL: ecall fires ONLY for the exact ECALL encoding (0x00000073).
//           EBREAK / WFI / SRET / other SYSTEM funct3=000 are treated as NOP.
module control_unit (
    input  wire [6:0]  opcode,
    input  wire [2:0]  funct3,
    input  wire [6:0]  funct7,
    input  wire [11:0] funct12,  // instruction[31:20] — needed to distinguish ECALL/EBREAK/MRET
    output reg  [4:0]  alu_op,   // see ALU_* localparams below
    output reg         alu_src,  // 0=rs2, 1=imm
    output reg         mem_read,
    output reg         mem_write,
    output reg         reg_write,
    output reg  [1:0]  wb_sel,   // 00=ALU, 01=MEM, 10=PC+4
    output reg         branch,
    output reg         jal,
    output reg         jalr,
    output reg         lui,
    output reg         auipc,
    output reg         ecall,    // true ECALL only (funct12 == 12'h000)
    output reg         mret,     // MRET (funct12 == 12'h302)
    output reg         csr_op    // any CSR instruction (funct3 != 000)
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

    always @(*) begin
        alu_op    = ALU_ADD;
        alu_src   = 1'b0;
        mem_read  = 1'b0;
        mem_write = 1'b0;
        reg_write = 1'b0;
        wb_sel    = 2'b00;
        branch    = 1'b0;
        jal       = 1'b0;
        jalr      = 1'b0;
        lui       = 1'b0;
        auipc     = 1'b0;
        ecall     = 1'b0;
        mret      = 1'b0;
        csr_op    = 1'b0;

        case (opcode)
            7'b0110011: begin  // R-type
                reg_write = 1'b1;
                if (funct7 == 7'b0000001) begin
                    case (funct3)
                        3'b000: alu_op = ALU_MUL;
                        3'b001: alu_op = ALU_MULH;
                        3'b010: alu_op = ALU_MULHSU;
                        3'b011: alu_op = ALU_MULHU;
                        3'b100: alu_op = ALU_DIV;
                        3'b101: alu_op = ALU_DIVU;
                        3'b110: alu_op = ALU_REM;
                        3'b111: alu_op = ALU_REMU;
                        default: alu_op = ALU_ADD;
                    endcase
                end else begin
                    case (funct3)
                        3'b000: alu_op = funct7[5] ? ALU_SUB : ALU_ADD;
                        3'b001: alu_op = ALU_SLL;
                        3'b010: alu_op = ALU_SLT;
                        3'b011: alu_op = ALU_SLTU;
                        3'b100: alu_op = ALU_XOR;
                        3'b101: alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                        3'b110: alu_op = ALU_OR;
                        3'b111: alu_op = ALU_AND;
                        default: alu_op = ALU_ADD;
                    endcase
                end
            end

            7'b0010011: begin  // I-type ALU
                reg_write = 1'b1;
                alu_src   = 1'b1;
                case (funct3)
                    3'b000: alu_op = ALU_ADD;
                    3'b001: alu_op = ALU_SLL;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    3'b100: alu_op = ALU_XOR;
                    3'b101: alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b110: alu_op = ALU_OR;
                    3'b111: alu_op = ALU_AND;
                    default: alu_op = ALU_ADD;
                endcase
            end

            7'b0000011: begin  // LOAD
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = ALU_ADD;
                mem_read  = 1'b1;
                wb_sel    = 2'b01;
            end

            7'b0100011: begin  // STORE
                alu_src   = 1'b1;
                alu_op    = ALU_ADD;
                mem_write = 1'b1;
            end

            7'b1100011: begin  // BRANCH
                branch = 1'b1;
                alu_op = ALU_SUB;
            end

            7'b0110111: begin  // LUI
                reg_write = 1'b1;
                lui       = 1'b1;
                alu_src   = 1'b1;
                alu_op    = ALU_PASS_B;
            end

            7'b0010111: begin  // AUIPC
                reg_write = 1'b1;
                auipc     = 1'b1;
                alu_src   = 1'b1;
                alu_op    = ALU_ADD;
            end

            7'b1101111: begin  // JAL
                reg_write = 1'b1;
                jal       = 1'b1;
                wb_sel    = 2'b10;
            end

            7'b1100111: begin  // JALR
                reg_write = 1'b1;
                jalr      = 1'b1;
                alu_src   = 1'b1;
                alu_op    = ALU_ADD;
                wb_sel    = 2'b10;
            end

            7'b0001111: begin  // FENCE / FENCE.I — pipeline flush by re-fetching PC+4
                jal = 1'b1;    // imm_gen returns 4 for FENCE.I, so branch_target = PC+4
            end

            7'b1110011: begin  // SYSTEM
                if (funct3 == 3'b000) begin
                    // Decode by funct12; ecall also covers EBREAK (stage_ex uses csr_addr to set mcause)
                    case (funct12)
                        12'h000: ecall = 1'b1;  // ECALL — mcause=11 in stage_ex
                        12'h001: ecall = 1'b1;  // EBREAK — mcause=3 in stage_ex (csr_addr==12'h001)
                        12'h302: mret  = 1'b1;  // MRET
                        // 12'h105 = WFI, 12'h102 = SRET: treat as NOP
                        default: ;
                    endcase
                end else begin
                    // CSRRW / CSRRS / CSRRC / CSRRWI / CSRRSI / CSRRCI
                    csr_op    = 1'b1;
                    reg_write = 1'b1;
                    // wb_sel=00: alu_result is set to csr_rdata in stage_ex
                end
            end

            default: ; // NOP / unknown
        endcase
    end

endmodule
