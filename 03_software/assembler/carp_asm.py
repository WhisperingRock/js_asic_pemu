#!/usr/bin/env python3
"""
CARP state machine assembler (table-driven).

Usage:
    python3 carp_asm.py program.asm               # writes program.mem, prints a listing
    python3 carp_asm.py program.asm -o prog.mem   # choose the output file
    python3 carp_asm.py program.asm -q            # no listing
    python3 carp_asm.py program.asm --sm bi       # also check write indices for a
                                                  # bidirectional (4-pin) state machine
                                                  # (--sm regular: 2 outputs)

Load the .mem file in Verilog with:
    $readmemh("program.mem", instr_mem);

Syntax (one instruction per line):
    label:                       ; a label marks the address of the next instruction
    in    pins[9], 1             ; comments start with ';' or '//'
    jmp   pins[3], loop          ; [n] = pin index, written right after the name

PIN INDEX (instruction bits 11:8; there is no [delay] any more)
    pins[n] / pindirs[n] put n (0-15) in the index field. No [n] = 0.
    ("pin" is still accepted as another spelling of "pins", so old programs
    assemble, but "pins" is the one name to use.)
    READS use n as a bit of the shared input bank (same number on every
    state machine):
        jmp  pins[n], label      jump if bank bit n is 1     (tests ONE bit)
        wait 1, pins[n]          wait for bank bit n == 1    (tests ONE bit;
                                                              gpio[n] is the same)
        in   pins[n], count      bank bits n .. n+count-1   (must stay <= 15)
        mov  x, pins[n]          bank shifted right by n    (pins = whole bank)
    WRITES use n as THIS state machine's own output pin (regular 0-1, bidir 0-3):
        out  pins[n], count      outputs n .. n+count-1
        set  pins[n], 0|1        output n only                       (S = 0)
        set  pins[n..], value    outputs n and up, value 0..15        (S = 1)
                                 (value bit 0 -> output n)
        mov  pins[n], src        outputs n and up
        (same for pindirs[n]: the output enables)
    BEQ has no index field: its "pins" sources are the whole bank.

Instructions:
    push
    pull
    out   <dest>, <bit count>            dest: pins[n] x y null pindirs[n] pc isr osr
    in    <src>,  <bit count>            src:  pins[n] x y null isr osr
    jmp   [<cond>,] <label|addr>         cond: !x x-- !y y-- x!=y pins[n] !osre
    beq   <src1|imm>, <src2>, <label|addr>
                                         src1: pins x y pins&x pins&y pins&osr isr osr
                                               or a number 0..7
                                         src2: pins x y null pindirs pc isr osr
    mov   <dest>, [!|~|::]<src>          !/~ = invert, :: = bit-reverse
    set   <dest>, <value>                dest: pins[n] pindirs[n]   value 0..1  (one pin)
                                               pins[n..] pindirs[n..] value 0..15 (n and up)
                                               x y                    value 0..31
    wait  <polarity>, <src>[n]           src:  pins gpio irq (also: wait 1, pins, n)
    nop                                  = mov y, y

  Masked BEQ, e.g. with a mask in Y:
    beq   pins&y, y, label               all masked pins high
    beq   pins&y, null, label            all masked pins low

HOW IT'S ORGANIZED
    Section 1 (the tables) is everything that describes the ISA: opcodes,
    which bits each field occupies, and the name -> number tables for every
    operand. When the ISA changes, you edit a table, not the code.

    Section 2 turns each line's operand text into field values, e.g.
    "out pins[1], 1" -> {dest: 0, index: 1, count: 1}. Section 3 packs those
    values into a 16-bit word using the bit positions from LAYOUTS, and checks
    that each value fits its field.
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
    "wait": 0b1100,
}

# Bit positions of every field: (field name, high bit, low bit)
# A field listed here gets range-checked automatically.
LAYOUTS = {
    "push": [("op", 15, 12)],
    "pull": [("op", 15, 12)],
    "out":  [("op", 15, 12), ("index", 11, 8), ("dest", 7, 5), ("count", 4, 0)],
    "in":   [("op", 15, 12), ("index", 11, 8), ("src", 7, 5),  ("count", 4, 0)],
    "jmp":  [("op", 15, 12), ("index", 11, 8), ("cond", 7, 5), ("addr", 4, 0)],
    "beq":  [("op", 15, 12), ("src1", 11, 9),  ("src2", 8, 6), ("imm", 5, 5), ("addr", 4, 0)],
    "mov":  [("op", 15, 12), ("index", 11, 8), ("dest", 7, 5), ("optn", 4, 3), ("src", 2, 0)],
    # SET to pins/pindirs: bit 4 is S (0 = one pin, 1 = index and up), data = 3:0.
    # SET to x/y: bits 4:0 are all data. The parser folds S into "data".
    "set":  [("op", 15, 12), ("index", 11, 8), ("dest", 7, 5), ("data", 4, 0)],
    # bits 4:0 of WAIT are reserved (the old Index [1:0] is not used)
    "wait": [("op", 15, 12), ("index", 11, 8), ("pol", 7, 7),  ("src", 6, 5)],
}

# The 8 to 1 mux / destination table
# (isr as an OUT destination also sets the ISR shift counter to the bit count)
MUX8 = {"pins": 0, "x": 1, "y": 2, "null": 3, "pindirs": 4, "pc": 5, "isr": 6, "osr": 7}

OUT_DEST = MUX8
IN_SRC   = {k: MUX8[k] for k in ("pins", "x", "y", "null", "isr", "osr")}
MOV_DEST = MUX8
MOV_SRC  = MUX8
MOV_OPTN = {"": 0, "!": 1, "~": 1, "::": 2}    # none / invert / bit-reverse
SET_DEST = {"pins": 0, "x": 1, "y": 2, "pindirs": 4}   # 011 reserved (maybe null later)
JMP_COND = {"": 0, "!x": 1, "x--": 2, "!y": 3, "y--": 4, "x!=y": 5, "pins": 6, "!osre": 7,
            "pin": 6}   # "pin" = old spelling of "pins"

# BEQ: bit 5 picks what ir[11:9] means -- 0: a Source 1 select, 1: a 3-bit
# immediate (0..7). Src2 uses the 8 to 1 mux. "pins" is the whole bank.
BEQ_SRC1 = {"pins": 0, "x": 1, "y": 2, "pins&x": 3, "pins&y": 4, "pins&osr": 5,
            "isr": 6, "osr": 7}
BEQ_SRC2 = MUX8

WAIT_SRC = {"gpio": 0, "pins": 1, "irq": 2,   # 11 reserved
            "pin": 1}                           # "pin" = old spelling of "pins"

# Operand names that take a pin index [n]
INDEXED  = {"pin", "pins", "pindirs", "gpio", "irq"}
WRITE_TO = {"pins", "pindirs"}              # as a destination these are local outputs

PIN_INDEX    = (0, 15)   # 4-bit index
BANK_WIDTH   = 16        # input bank bits
SM_OUTPUTS   = {"regular": 2, "bi": 4}   # outputs per state machine kind (--sm)
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


OPTIONS = {"sm": None}      # set from the command line: None, "regular" or "bi"


def parse_int(tok, what):
    try:
        val = int(tok, 0)          # accepts 12, 0x0C, 0b1100
    except ValueError:
        raise AsmError(f"expected a number for {what}, got '{tok}'")
    if val < 0:
        raise AsmError(f"{what} can't be negative ({val})")
    return val


def split_index(tok):
    """'pins[9]' -> ('pins', 9); 'pins' -> ('pins', None)."""
    if re.search(r"\.\.\s*\]", tok):
        raise AsmError(f"'{tok}': [n..] (index and up) is only used with set pins / set pindirs")
    m = re.fullmatch(r"([^\[\]]+)\[([^\]]*)\]", tok)
    if not m:
        if "[" in tok or "]" in tok:
            raise AsmError(f"can't read '{tok}' (pin index is written name[n], e.g. pins[3])")
        return tok, None
    name, idx = m.group(1), parse_int(m.group(2), "pin index")
    if name.lower() not in INDEXED:
        raise AsmError(f"'{name}' doesn't take a pin index; only {', '.join(sorted(INDEXED - {'pin'}))} do")
    lo, hi = PIN_INDEX
    if not lo <= idx <= hi:
        raise AsmError(f"pin index must be {lo}..{hi}, got {idx}")
    return name, idx


def lookup(table, tok, what):
    key = tok.lower()
    if key not in table:
        legal = ", ".join(k for k in table if k) or "(none)"
        raise AsmError(f"unknown {what} '{tok}' (legal: {legal})")
    return table[key]


def check_write(name, idx, count):
    """Writes go to this state machine's own outputs: index (+ count) must fit."""
    kind = OPTIONS["sm"]
    if kind is None or name.lower() not in WRITE_TO:
        return
    n = SM_OUTPUTS[kind]
    if idx >= n:
        raise AsmError(f"{name}[{idx}]: a {kind} state machine only has outputs 0..{n - 1}")
    if count is not None and idx + count > n:
        raise AsmError(f"{name}[{idx}] with count {count} runs past output {n - 1} "
                       f"of a {kind} state machine")


def resolve_target(tok, labels):
    if tok in labels:
        return labels[tok]
    if re.fullmatch(r"\d+|0[xX][0-9a-fA-F]+|0[bB][01]+", tok):
        return parse_int(tok, "address")
    raise AsmError(f"unknown label '{tok}'")


def expect(tokens, n, usage):
    if len(tokens) != n:
        raise AsmError(f"expected: {usage}")


def no_index(name, idx, what):
    if idx is not None:
        raise AsmError(f"{what} '{name}' doesn't take a pin index")


def p_none(tokens, labels):
    expect(tokens, 0, "no operands")
    return {}


def p_count(tok):
    count = parse_int(tok, "bit count")
    lo, hi = OUT_IN_COUNT
    if not lo <= count <= hi:
        raise AsmError(f"bit count must be {lo}..{hi}, got {count}")
    return count


def p_out(tokens, labels):
    expect(tokens, 2, "out <dest>, <bit count>")
    name, idx = split_index(tokens[0])
    count = p_count(tokens[1])
    if name.lower() not in WRITE_TO:
        no_index(name, idx, "OUT destination")
    idx = idx or 0
    check_write(name, idx, count)
    return {"dest": lookup(OUT_DEST, name, "OUT destination"), "index": idx, "count": count}


def p_in(tokens, labels):
    expect(tokens, 2, "in <src>, <bit count>")
    name, idx = split_index(tokens[0])
    count = p_count(tokens[1])
    if name.lower() != "pins":
        no_index(name, idx, "IN source")
    idx = idx or 0
    if name.lower() == "pins" and idx + count > BANK_WIDTH:
        raise AsmError(f"in pins[{idx}], {count} reads past bank bit {BANK_WIDTH - 1} "
                       f"(those bits read as 0)")
    return {"src": lookup(IN_SRC, name, "IN source"), "index": idx, "count": count}


def p_jmp(tokens, labels):
    if not tokens:
        raise AsmError("expected: jmp [<cond>,] <label>")
    cond = "".join(tokens[:-1])            # handles 'x != y' written with spaces
    name, idx = split_index(cond) if cond else ("", None)
    if name.lower() not in ("pins", "pin"):
        no_index(name, idx, "JMP condition")
    return {"cond": lookup(JMP_COND, name, "JMP condition"),
            "index": idx or 0,
            "addr": resolve_target(tokens[-1], labels)}


def p_beq(tokens, labels):
    expect(tokens, 3, "beq <src1|imm>, <src2>, <label>")
    a, b, target = tokens
    addr = resolve_target(target, labels)
    for tok in (a, b):
        if "[" in tok:
            raise AsmError(f"BEQ has no pin index ('{tok}'); its pins sources are the "
                           f"whole bank -- use jmp pins[n] to test one pin")

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
    dname, didx = split_index(dest)
    sname, sidx = split_index(src)
    if dname.lower() not in WRITE_TO:
        no_index(dname, didx, "MOV destination")
    if sname.lower() != "pins":
        no_index(sname, sidx, "MOV source")
    if didx is not None and sidx is not None and didx != sidx:
        raise AsmError(f"mov has one pin index: {dname}[{didx}] and {sname}[{sidx}] can't both be used")
    idx = didx if didx is not None else (sidx or 0)
    if didx is not None:
        check_write(dname, didx, None)
    return {"dest": lookup(MOV_DEST, dname, "MOV destination"),
            "index": idx,
            "optn": MOV_OPTN[optn],
            "src":  lookup(MOV_SRC, sname, "MOV source")}


def p_set(tokens, labels):
    expect(tokens, 2, "set <dest>, <value>")
    dest = tokens[0]
    # pins[n..] / pindirs[n..] = "index and up" (S = 1)
    up = re.fullmatch(r"(\w+)\[\s*([^\]]*?)\s*\.\.\s*\]", dest)
    if up:
        dest = f"{up.group(1)}[{up.group(2)}]"
    name, idx = split_index(dest)
    value = parse_int(tokens[1], "SET value")
    code = lookup(SET_DEST, name, "SET destination")
    if name.lower() in WRITE_TO:
        idx = idx or 0
        if up:
            if value > 15:
                raise AsmError(f"set {name}[{idx}..] takes a value 0..15 (one bit per pin), got {value}")
            check_write(name, idx, None)
            kind = OPTIONS["sm"]
            if kind and value >> (SM_OUTPUTS[kind] - idx):
                raise AsmError(f"set {name}[{idx}..], {value}: a {kind} state machine only has "
                               f"outputs {idx}..{SM_OUTPUTS[kind] - 1}, so value bits past "
                               f"{SM_OUTPUTS[kind] - 1 - idx} would be dropped")
            data = 0b10000 | value                 # S = 1
        else:
            if value > 1:
                raise AsmError(f"set {name}[{idx}] changes one pin, so the value is 0 or 1 "
                               f"(got {value}); use {name}[{idx}..] to set pins {idx} and up")
            check_write(name, idx, 1)
            data = value                            # S = 0
    else:
        if up:
            raise AsmError(f"'{tokens[0]}': [n..] is only for set pins / set pindirs")
        no_index(name, idx, "SET destination")
        idx, data = 0, value                        # x / y: all 5 bits are data
    return {"dest": code, "index": idx, "data": data}


def p_wait(tokens, labels):
    # wait <pol>, <src>[n]     or the older form     wait <pol>, <src>, <n>
    if len(tokens) == 3:
        tokens = [tokens[0], f"{tokens[1]}[{tokens[2]}]"]
    expect(tokens, 2, "wait <polarity>, <src>[<index>]")
    pol = parse_int(tokens[0], "polarity")
    if pol > 1:
        raise AsmError(f"polarity must be 0 or 1, got {pol}")
    name, idx = split_index(tokens[1])
    return {"pol": pol,
            "src": lookup(WAIT_SRC, name, "WAIT source"),
            "index": idx or 0}


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


def tokenize(operands):
    # 'pins & y' -> 'pins&y' so the masked BEQ sources stay one token
    operands = re.sub(r"\s*&\s*", "&", operands.strip())
    return [t for t in re.split(r"[,\s]+", operands) if t]


def assemble(source_lines):
    errors = []
    labels = {}
    program = []   # (line number, mnemonic, operand text, source line)

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

        # An old-style delay: "[n]" standing on its own at the end of the line
        if re.search(r"\s\[\s*[^\]]*\]\s*$", line):
            errors.append(f"line {lineno}: [delay] was removed from the ISA "
                          f"(bits 11:8 are the pin index now)\n    {raw.strip()}")
            continue

        parts = line.split(None, 1)
        mnemonic = parts[0].lower()
        operands = parts[1] if len(parts) > 1 else ""
        if mnemonic in PSEUDO:
            if operands:
                errors.append(f"line {lineno}: '{mnemonic}' takes no operands")
            mnemonic, operands = PSEUDO[mnemonic]
        program.append((lineno, mnemonic, operands, raw.rstrip()))

    if len(program) > MAX_PROGRAM:
        errors.append(f"program is {len(program)} instructions; the limit is {MAX_PROGRAM}")

    # Pass 2: encode
    output = []    # (address, word, mnemonic, source line)
    for addr, (lineno, mnemonic, operands, raw) in enumerate(program):
        try:
            if mnemonic not in OPCODES:
                raise AsmError(f"unknown instruction '{mnemonic}'")
            fields = PARSERS[mnemonic](tokenize(operands), labels)
            fields["op"] = OPCODES[mnemonic]
            output.append((addr, pack(mnemonic, fields), mnemonic, raw))
        except AsmError as e:
            errors.append(f"line {lineno}: {e}\n    {raw.strip()}")

    return output, labels, errors


def main():
    ap = argparse.ArgumentParser(description="CARP state machine assembler")
    ap.add_argument("source", help="assembly file (.asm)")
    ap.add_argument("-o", "--output", help="output .mem file (default: <source>.mem)")
    ap.add_argument("-q", "--quiet", action="store_true", help="don't print the listing")
    ap.add_argument("--sm", choices=sorted(SM_OUTPUTS),
                    help="check write indices for this kind of state machine")
    args = ap.parse_args()
    OPTIONS["sm"] = args.sm

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