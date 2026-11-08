; uart_rx_9600.asm -- UART receiver, 9600 baud 8N1, LSB first, 100 MHz clock.
; For one CARP state machine. No [delay] used.
;
; Watches in_pin. Each byte received is PUSHed to the RX FIFO as
; 16'h00XX (the byte in bits [7:0]).
;
; How it samples:
;   1. Wait for the line to fall (start bit).
;   2. Wait half a bit and check the line is still low (filters glitches).
;   3. Wait one full bit at a time and sample in the middle of each data bit.
;   4. Push the byte, wait for the line to go back high (stop bit), repeat.
;
; Timing: one bit = 10417 cycles at 100 MHz / 9600 baud.
;   D = 10411 = 10*1024 + 5*32 + 11   (same constant as uart_tx_9600.asm)
;   Each bit wait below is D + 5 cycles, close enough: the sample point
;   drifts 1 cycle per bit, 8 cycles over the whole byte.
;
; Registers:
;   OSR  holds D the whole time (this program never PULLs or OUTs)
;   ISR  holds D/2 while idle, then collects the 8 data bits
;   X    counts data bits, Y counts delay cycles

        set   pindirs, 0        ; pin is an input

        ; ---- OSR = D (one bit) = B2*1024 + B1*32 + B0
        set   x, 11             ; B0
        in    x, 5
        set   x, 5              ; B1
        in    x, 5
        set   x, 10             ; B2
        in    x, 5
        in    null, 1           ; ISR = D
        mov   osr, isr          ; OSR = D, kept for good

idle:
        mov   isr, osr
        in    null, 1           ; ISR = D/2 (half a bit)
wait_start:
        jmp   pin, wait_start   ; line idles high: loop until it goes low

        ; ---- start bit: wait half a bit, make sure it's still low
        mov   y, isr
half:
        jmp   y--, half
        jmp   pin, idle         ; high again -> it was a glitch, not a start bit

        ; ---- 8 data bits, sampled in the middle of each bit
        set   x, 7
bitloop:
        mov   y, osr
bitdly:
        jmp   y--, bitdly       ; one bit time
        in    pins, 1           ; sample: the bit enters at ISR[15]
        jmp   x--, bitloop

        ; ISR[15:8] = byte (first bit received at [8]). Shift it down.
        in    null, 8           ; ISR = 16'h00XX. The D/2 that was in the ISR
                                ; has been shifted out by now (16 shifts total)
        push                    ; RX FIFO <- byte, ISR cleared

        ; ---- wait for the stop bit (line high) before looking for the next start.
        ; We're in the middle of bit 7; if it was a 0 the line is still low.
stop:
        jmp   pin, idle
        jmp   stop