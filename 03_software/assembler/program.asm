#!/usr/bin/env python3
"""
CARP state machine assembler (table-driven).

Usage:
    python3 carp_asm.py program.asm               # writes program.mem, prints a listing
    python3 carp_asm.py program.asm -o prog.mem   # choose the output file
    python3 carp_asm.py program.asm -q            # no listing

Load the .mem file in Verilog with:
    $readmemh("program.mem", instr_mem);

Syntax (one instruction per line):
    label:                       ; a label marks the address of the next instruction
    out   pins, 1                ; comments start with ';' or '//'
    jmp   x--, bitloop [6]       ; optional [delay] at the end of the line

Instructions:
    push
    pull
    out   <dest>, <bit count>            dest: pins x y null pindirs pc isr osr
    in    <src>,  <bit count>            src:  pins x y null isr osr
    jmp   [<cond>,] <label|addr>         cond: !x x-- !y y-- x!=y pin !osre
    beq   <src1|imm>, <src2>, <label|addr>
    mov   <dest>, [!|~|::]<src>          !/~ = invert, :: = bit-reverse
    set   <dest>, <value>                dest: pins x y pindirs
    wait  <polarity>, <src>, <index>     src:  gpio pin irq   (provisional)
    nop                                  = mov y, y

HOW IT'S ORGANIZED
    Section 1 (the tables) is everything that describes the ISA: opcodes,
    which bits each field occupies, and the name -> number tables for every
    operand. When the ISA changes, you edit a table, not the code.

    Section 2 turns each line's operand text into field values, e.g.
    "out pins, 1" -> {dest: 0, count: 1}. Section 3 packs those values into a
    16-bit word using the bit positions from LAYOUTS, and checks that each
    value fits its field.
"""

import argparse
import re
import sys

# =====================================================================
# 1. ENCODING TABLES  -- edit these when the ISA changes
# =====================================================================

# ir[15:12]
OPCODES = {
    "push": 0b0000,
    "pull": 0b1000,
    "out":  0b0001,
    "in":   0b1001,
    "beq":  0b0010,
    "jmp":  0b1010,
    "mov":  0b0011,
    "set":  0b1011,
    "wait": 0b0100,  # FIX_ME: bit 15 of WAIT is still '?' in the ISA
}

# Bit positions of every field: (field name, high bit, low bit)
# A field listed here gets range-checked automatically.
# 'delay' present = the instruction accepts a [delay] suffix.
LAYOUTS = {
    "push": [("op", 15, 12)],
    "pull": [("op", 15, 12)],
    "out":  [("op", 15, 12), ("delay", 11, 8), ("dest", 7, 5), ("count", 4, 0)],
    "in":   [("op", 15, 12), ("delay", 11, 8), ("src", 7, 5),  ("count", 4, 0)],
    "jmp":  [("op", 15, 12), ("delay", 11, 8), ("cond", 7, 5), ("addr", 4, 0)],
    "beq":  [("op", 15, 12), ("src1", 11, 9),  ("src2", 8, 6), ("imm", 5, 5), ("addr", 4, 0)],
    "mov":  [("op", 15, 12), ("delay", 11, 8), ("dest", 7, 5), ("optn", 4, 3), ("src", 2, 0)],
    "set":  [("op", 15, 12), ("delay", 11, 8), ("dest", 7, 5), ("data", 4, 0)],
    "wait": [("op", 15, 12), ("delay", 11, 8), ("pol", 7, 7),  ("src", 6, 5), ("index", 4, 0)],
}

# The 8 to 1 mux / destination table
MUX8 = {"pins": 0, "x": 1, "y": 2, "null": 3, "pindirs": 4, "pc": 5, "isr": 6, "osr": 7}

OUT_DEST = MUX8
IN_SRC   = {k: MUX8[k] for k in ("pins", "x", "y", "null", "isr", "osr")}
MOV_DEST = MUX8
MOV_SRC  = MUX8
MOV_OPTN = {"": 0, "!": 1, "~": 1, "::": 2}    # none / invert / bit-reverse
SET_DEST = {"pins": 0, "x": 1, "y": 2, "pindirs": 4}
JMP_COND = {"": 0, "!x": 1, "x--": 2, "!y": 3, "y--": 4, "x!=y": 5, "pin": 6, "!osre": 7}

# BEQ: Src1 uses the Source 1 mux, Src2 uses the 8 to 1 mux
BEQ_SRC1 = {"pins": 0, "x": 1, "y": 2, "isr": 6, "osr": 7}
BEQ_SRC2 = MUX8

WAIT_SRC = {"gpio": 0, "pin": 1, "irq": 2}

OUT_IN_COUNT = (1, 16)   # legal bit counts for OUT / IN (16-bit registers)
MAX_PROGRAM  = 32        # 5-bit addresses

# Pseudo-instructions: rewritten into a real instruction before encoding
PSEUDO = {
    "nop": ("mov", "y, y"),
}

# =====================================================================
# 2. OPERAND PARSERS  -- operand text -> field values
# =====================================================================


class AsmError(Exception):
    pass


def parse_int(tok, what):
    try:
        val = int(tok, 0)          # accepts 12, 0x0C, 0b1100
    except ValueError:
        raise AsmError(f"expected a number for {what}, got '{tok}'")
    if val < 0:
        raise AsmError(f"{what} can't be negative ({val})")
    return val


def lookup(table, tok, what):
    key = tok.lower()
    if key not in table:
        legal = ", ".join(k for k in table if k) or "(none)"
        raise AsmError(f"unknown {what} '{tok}' (legal: {legal})")
    return table[key]


def resolve_target(tok, labels):
    if tok in labels:
        return labels[tok]
    if re.fullmatch(r"\d+|0[xX][0-9a-fA-F]+|0[bB][01]+", tok):
        return parse_int(tok, "address")
    raise AsmError(f"unknown label '{tok}'")


def expect(tokens, n, usage):
    if len(tokens) != n:
        raise AsmError(f"expected: {usage}")


def p_none(tokens, labels):
    expect(tokens, 0, "no operands")
    return {}


def p_out(tokens, labels):
    expect(tokens, 2, "out <dest>, <bit count>")
    count = parse_int(tokens[1], "bit count")
    lo, hi = OUT_IN_COUNT
    if not lo <= count <= hi:
        raise AsmError(f"bit count must be {lo}..{hi}, got {count}")
    return {"dest": lookup(OUT_DEST, tokens[0], "OUT destination"), "count": count}


def p_in(tokens, labels):
    expect(tokens, 2, "in <src>, <bit count>")
    count = parse_int(tokens[1], "bit count")
    lo, hi = OUT_IN_COUNT
    if not lo <= count <= hi:
        raise AsmError(f"bit count must be {lo}..{hi}, got {count}")
    return {"src": lookup(IN_SRC, tokens[0], "IN source"), "count": count}


def p_jmp(tokens, labels):
    if not tokens:
        raise AsmError("expected: jmp [<cond>,] <label>")
    cond = "".join(tokens[:-1])            # handles 'x != y' written with spaces
    return {"cond": lookup(JMP_COND, cond, "JMP condition"),
            "addr": resolve_target(tokens[-1], labels)}


def p_beq(tokens, labels):
    expect(tokens, 3, "beq <src1|imm>, <src2>, <label>")
    a, b, target = tokens
    addr = resolve_target(target, labels)

    def try_order(first, second):
        if re.fullmatch(r"\d+|0[xX][0-9a-fA-F]+|0[bB][01]+", first):
            fields = {"imm": 1, "src1": parse_int(first, "BEQ immediate")}
        else:
            fields = {"imm": 0, "src1": lookup(BEQ_SRC1, first, "BEQ source 1")}
        fields["src2"] = lookup(BEQ_SRC2, second, "BEQ source 2")
        return fields

    # Equality is symmetric: if the operands only fit the other way round, swap them.
    try:
        fields = try_order(a, b)
    except AsmError as first_error:
        try:
            fields = try_order(b, a)
        except AsmError:
            raise first_error
    fields["addr"] = addr
    return fields


def p_mov(tokens, labels):
    if len(tokens) < 2:
        raise AsmError("expected: mov <dest>, [!|~|::]<src>")
    dest = tokens[0]
    src = "".join(tokens[1:])              # allows '! y' as well as '!y'
    optn = ""
    for prefix in ("::", "!", "~"):
        if src.startswith(prefix):
            optn, src = prefix, src[len(prefix):]
            break
    return {"dest": lookup(MOV_DEST, dest, "MOV destination"),
            "optn": MOV_OPTN[optn],
            "src":  lookup(MOV_SRC, src, "MOV source")}


def p_set(tokens, labels):
    expect(tokens, 2, "set <dest>, <value>")
    return {"dest": lookup(SET_DEST, tokens[0], "SET destination"),
            "data": parse_int(tokens[1], "SET value")}


def p_wait(tokens, labels):
    expect(tokens, 3, "wait <polarity>, <src>, <index>")
    pol = parse_int(tokens[0], "polarity")
    if pol > 1:
        raise AsmError(f"polarity must be 0 or 1, got {pol}")
    return {"pol": pol,
            "src": lookup(WAIT_SRC, tokens[1], "WAIT source"),
            "index": parse_int(tokens[2], "index")}


PARSERS = {
    "push": p_none,
    "pull": p_none,
    "out":  p_out,
    "in":   p_in,
    "jmp":  p_jmp,
    "beq":  p_beq,
    "mov":  p_mov,
    "set":  p_set,
    "wait": p_wait,
}

# =====================================================================
# 3. ENCODER + TWO-PASS ASSEMBLY  -- you shouldn't need to touch this
# =====================================================================


def pack(mnemonic, fields):
    word = 0
    for name, hi, lo in LAYOUTS[mnemonic]:
        width = hi - lo + 1
        val = fields.get(name, 0)
        if val >= (1 << width):
            raise AsmError(f"{name} = {val} doesn't fit in {width} bits "
                           f"(max {(1 << width) - 1})")
        word |= val << lo
    return word


def field_string(mnemonic, word):
    """Binary grouped by field, e.g. '1010 0110 010 00011'."""
    return " ".join(format((word >> lo) & ((1 << (hi - lo + 1)) - 1), f"0{hi - lo + 1}b")
                    for _, hi, lo in LAYOUTS[mnemonic])


def strip_comment(line):
    return re.split(r";|//", line, maxsplit=1)[0].strip()


def assemble(source_lines):
    errors = []
    labels = {}
    program = []   # (line number, mnemonic, operand text, delay text, source line)

    # Pass 1: find labels and instructions
    for lineno, raw in enumerate(source_lines, 1):
        line = strip_comment(raw)
        while True:
            m = re.match(r"^([A-Za-z_]\w*)\s*:(.*)$", line)
            if not m:
                break
            name, line = m.group(1), m.group(2).strip()
            if name in labels:
                errors.append(f"line {lineno}: label '{name}' defined twice")
            labels[name] = len(program)
        if not line:
            continue

        delay = None
        m = re.search(r"\[\s*([^\]]*)\]\s*$", line)
        if m:
            delay, line = m.group(1).strip(), line[:m.start()].strip()

        parts = line.split(None, 1)
        mnemonic = parts[0].lower()
        operands = parts[1] if len(parts) > 1 else ""
        if mnemonic in PSEUDO:
            if operands:
                errors.append(f"line {lineno}: '{mnemonic}' takes no operands")
            mnemonic, operands = PSEUDO[mnemonic]
        program.append((lineno, mnemonic, operands, delay, raw.rstrip()))

    if len(program) > MAX_PROGRAM:
        errors.append(f"program is {len(program)} instructions; the limit is {MAX_PROGRAM}")

    # Pass 2: encode
    output = []    # (address, word, mnemonic, source line)
    for addr, (lineno, mnemonic, operands, delay, raw) in enumerate(program):
        try:
            if mnemonic not in OPCODES:
                raise AsmError(f"unknown instruction '{mnemonic}'")
            tokens = [t for t in re.split(r"[,\s]+", operands.strip()) if t]
            fields = PARSERS[mnemonic](tokens, labels)
            fields["op"] = OPCODES[mnemonic]
            if delay is not None:
                if not any(name == "delay" for name, _, _ in LAYOUTS[mnemonic]):
                    raise AsmError(f"'{mnemonic}' has no delay field")
                fields["delay"] = parse_int(delay, "delay")
            output.append((addr, pack(mnemonic, fields), mnemonic, raw))
        except AsmError as e:
            errors.append(f"line {lineno}: {e}\n    {raw.strip()}")

    return output, labels, errors


def main():
    ap = argparse.ArgumentParser(description="CARP state machine assembler")
    ap.add_argument("source", help="assembly file (.asm)")
    ap.add_argument("-o", "--output", help="output .mem file (default: <source>.mem)")
    ap.add_argument("-q", "--quiet", action="store_true", help="don't print the listing")
    args = ap.parse_args()

    with open(args.source) as f:
        output, labels, errors = assemble(f.readlines())

    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        print(f"{len(errors)} error(s), nothing written", file=sys.stderr)
        sys.exit(1)

    out_path = args.output or re.sub(r"\.[^./\\]*$", "", args.source) + ".mem"
    with open(out_path, "w") as f:
        for addr, word, _, raw in output:
            f.write(f"{word:04X}  // {addr:2d}: {raw.strip()}\n")

    if not args.quiet:
        print(f"{'addr':>4}  {'hex':4}  {'fields':22}  source")
        for addr, word, mnemonic, raw in output:
            print(f"{addr:4d}  {word:04X}  {field_string(mnemonic, word):22}  {raw.strip()}")
        if labels:
            print("\nlabels: " + ", ".join(f"{k}={v}" for k, v in labels.items()))
    print(f"\n{len(output)} instruction(s) -> {out_path}")


if __name__ == "__main__":
    main()