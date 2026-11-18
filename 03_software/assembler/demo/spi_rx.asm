; spi_rx.asm -- SPI slave receiver (mode 0, LSB first) for SM1 (bidirectional).
; Bank bits: 0 = CS, 1 = SCK (SM0's input pins), 2 = MOSI (SM1 pin 0).
; Each byte received is pushed to SM1's RX FIFO as 16'h00XX.

        set   pindirs[0..], 0   ; all 4 pins are inputs
byte:
        wait  1, pins[0]        ; at startup only: make sure CS is idle (high)
        set   x, 7              ; 8 bits
        wait  0, pins[0]        ; CS low (passes right away if we're mid-transaction)
bit:
        wait  0, pins[1]        ; SCK low
        wait  1, pins[1]        ; SCK rising edge: master's data is valid
        in    pins[2], 1        ; sample MOSI into the ISR
        jmp   x--, bit
        in    null, 8           ; move the byte down to ISR[7:0]
        push                    ; RX FIFO <- byte
        jmp   byte              ; next byte (same transaction or the next one)