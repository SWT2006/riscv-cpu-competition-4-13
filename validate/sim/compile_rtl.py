#!/usr/bin/env python3
"""
compile_rtl.py  –  Compile the RISC-V 5-stage pipeline CPU RTL with iverilog.

Usage (called internally by the simulation driver scripts):
    python compile_rtl.py <project_root>

  <project_root>  Path to the riscv-cpu-competition root, relative to the
                  directory where iverilog will be invoked (i.e. the CWD of
                  the caller script).

  From validate/sim/                → project_root = '../..'
  From validate/sim/compliance_test → project_root = '../../..'
"""

import sys
import subprocess
import os


def main():
    if len(sys.argv) < 2:
        print("Usage: compile_rtl.py <project_root>")
        sys.exit(1)

    rtl_dir = sys.argv[1]

    # Choose testbench based on which directory the caller lives in
    cwd = os.getcwd().replace('\\', '/')
    if 'compliance_test' in cwd:
        tb_file = '/tb/compliance_test/tinyriscv_soc_tb.v'
    else:
        tb_file = '/tb/tinyriscv_soc_tb.v'

    iverilog_cmd = ['iverilog']
    iverilog_cmd += ['-o', 'out.vvp']
    iverilog_cmd += ['-g2012']          # SystemVerilog 2012
    iverilog_cmd += ['-Wall']

    # Testbench (plain Verilog)
    iverilog_cmd.append(rtl_dir + tb_file)

    # SoC wrapper (plain Verilog – must come before .sv RTL so module
    # definitions are visible when iverilog parses the testbench)
    iverilog_cmd.append(rtl_dir + '/rtl/riscv_soc.v')

    # RTL source files (SystemVerilog .sv)
    # Note: display_seg, counter, dram_driver, perip_bridge, student_top are NOT
    # included here because the sim wrapper (riscv_soc.v) uses sim_imem/sim_dmem
    # directly instead of the board-specific peripherals.
    rtl_sv_files = [
        '/rtl/control_unit.sv',
        '/rtl/cpu_core.sv',
        '/rtl/csr_unit.sv',
        '/rtl/forwarding_unit.sv',
        '/rtl/hazard_unit.sv',
        '/rtl/imm_gen.sv',
        '/rtl/pipe_exmem.sv',
        '/rtl/pipe_idex.sv',
        '/rtl/pipe_ifid.sv',
        '/rtl/pipe_memwb.sv',
        '/rtl/stage_ex.sv',
        '/rtl/stage_id.sv',
        '/rtl/stage_if.sv',
        '/rtl/stage_mem.sv',
        '/rtl/stage_wb.sv',
    ]
    for f in rtl_sv_files:
        iverilog_cmd.append(rtl_dir + f)

    print('Compiling: ' + ' '.join(iverilog_cmd))
    process = subprocess.Popen(iverilog_cmd)
    process.wait(timeout=60)
    if process.returncode != 0:
        print('!!! iverilog compilation FAILED (return code %d) !!!' % process.returncode)
        sys.exit(process.returncode)


if __name__ == '__main__':
    sys.exit(main())
