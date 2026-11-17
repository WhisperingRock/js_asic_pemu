; spi_tx.asm -- SPI slave sender (mode 0, LSB first) for SM0 (regular).
; Reads (bank bits): 0 = CS, 1 = SCK (SM0's input pins).
; Writes (my outputs): pins[0] = MISO, pindirs[0] = MISO enable.
; Each byte sent comes from SM0's TX FIFO. MISO is driven only while CS is low.

byte:
        pull                    ; OSR <- next byte to send
        out   pins[0], 1        ; its bit 0 onto MISO, ready before the first rising edge
        set   x, 6              ; 7 more bits (bits 1..7)
hold:
        jmp   pins[0], idle     ; CS high: no transaction, let go of MISO
        jmp   pins[1], fall     ; SCK high: master already sampled bit 0, keep going
        jmp   hold              ; CS still low, no clock yet: keep checking
idle:
        set   pindirs[0], 0     ; let go of MISO (Z)
        wait  0, pins[0]        ; CS low: we're selected
        set   pindirs[0], 1     ; drive MISO (bit 0 is already on it)
bit:
        wait  1, pins[1]        ; SCK rising: master samples the current bit
fall:
        wait  0, pins[1]        ; SCK falling: our turn to change MISO
        out   pins[0], 1        ; next bit
        jmp   x--, bit
        wait  1, pins[1]        ; 8th rising edge: master samples bit 7
        wait  0, pins[1]        ; 8th falling edge: byte done
        jmp   byte