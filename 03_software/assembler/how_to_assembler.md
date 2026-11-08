Usage #1 (Manual Command):
    python3 carp_asm.py program.asm               # writes program.mem, prints a listing
    python3 carp_asm.py program.asm -o prog.mem   # choose the output file
    python3 carp_asm.py program.asm -q            # no listing

Usage #1 (Makefile):
    make asm                                      #Output is by default "program.mem"