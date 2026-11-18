; spi_tx.asm -- SPI slave sender for SM0. Mode 0, LSB first, one byte per CS low.
; Reads:  pins[0] = CS, pins[1] = SCK      Writes: pins[0] = MISO (always driven)

frame:
        pull                    ; get the byte to send from the TX FIFO
        out   pins[0], 1        ; put bit 0 on MISO
        set   x, 6              ; 7 more bits to go
        wait  0, pins[0]        ; wait for CS low
bit:
        wait  1, pins[1]        ; SCK rising: the Arduino reads MISO
        wait  0, pins[1]        ; SCK falling: our turn
        out   pins[0], 1        ; put the next bit on MISO
        jmp   x--, bit          ; repeat for bits 1..7
        wait  1, pins[0]        ; wait for CS high: transaction over
        jmp   frame