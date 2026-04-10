#!/usr/bin/env python3
"""Convert Xilinx .coe memory file to iverilog $readmemh format."""
import sys
import os

def convert_coe(in_path, out_path):
    with open(in_path, 'r') as f:
        content = f.read()

    # Find the vector section after '='
    idx = content.find('memory_initialization_vector=')
    if idx == -1:
        idx = content.find('memory_initialization_vector =')
    assert idx != -1, "Could not find memory_initialization_vector"
    vector_section = content[idx:].split('=', 1)[1]

    # Strip whitespace, commas, semicolons
    words = []
    for token in vector_section.replace('\n', ' ').replace('\r', ' ').split():
        token = token.strip(' ,;')
        if token:
            words.append(token)

    with open(out_path, 'w') as f:
        for w in words:
            f.write(w + '\n')

    print(f"Converted {len(words)} words: {in_path} -> {out_path}")

if __name__ == '__main__':
    base = r'C:\Users\38560\Desktop\work\riscv-cpu-competition'
    convert_coe(f'{base}/attachments/irom.coe', f'{base}/tb/irom.hex')
    convert_coe(f'{base}/attachments/dram.coe', f'{base}/tb/dram.hex')
