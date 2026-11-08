; uart_tx_9600.asm -- UART transmitter, 9600 baud 8N1, LSB first, 100 MHz clock,
; with a 2 s pause after every byte. For one CARP state machine. No [delay] used.
;
; Each word pulled from the TX FIFO sends its low 8 bits as one UART frame:
;   start bit (0), 8 data bits LSB first, stop bit (1). Then the line stays
;   high (idle) for the pause before the next frame starts.
;
; Timing (branch taken = 1 cycle, branch not taken = 2 cycles):
;   bit length   = D + 6 cycles         D = round(f_clk / baud) - 6
;   pause length ~ (N + 4) * 65536      N = round(f_clk * pause_seconds / 65536) - 4
;
;   100 MHz, 9600 baud: 10417 cycles/bit (9599.7 baud, -0.003%)
;                       D = 10411 = 10*1024 + 5*32 + 11
;   2 s pause:          N = 3048  =  2*1024 + 31*32 + 8
;
; Both constants are too big for SET (0..31), so they're built in the ISR
; 5 bits at a time. The ISR can only hold one at a time, so D is rebuilt
; before every frame and N after it.
;
; 32 of 32 instructions: the program memory is full.

        set   pindirs, 1        ; drive the pin
        set   pins, 1           ; line idles high

next:
        ; ---- ISR = D (bit length) = B2*1024 + B1*32 + B0
        set   x, 11             ; B0
        in    x, 5
        set   x, 5              ; B1
        in    x, 5
        set   x, 10             ; B2
        in    x, 5
        in    null, 1

        ; ---- send one frame
        pull                    ; OSR <- next byte from the TX FIFO
        set   x, 8              ; start bit + 8 data bits use the same loop
        set   pins, 0           ; ---- start bit
        mov   y, isr
        jmp   x--, dly          ; always taken here (x = 8)
bit:
        out   pins, 1           ; ---- data bit (LSB first)
        mov   y, isr
        jmp   x--, dly          ; taken for bits 0-6, falls through on bit 7
lastdly:
        jmp   y--, lastdly      ; bit 7 waits here: same total length
        set   pins, 1           ; ---- stop bit, then the line stays high

        ; ---- ISR = N (pause length) = C2*1024 + C1*32 + C0
        ; Built with y so x keeps 65535: the last "jmp x--" above ran with
        ; x = 0, and x-- always decrements, so x wrapped to 0xFFFF.
        set   y, 8              ; C0
        in    y, 5
        set   y, 31             ; C1
        in    y, 5
        set   y, 2              ; C2
        in    y, 5
        in    null, 1

        ; ---- pause: 65536 passes of an (N + 4)-cycle loop
pause:
        mov   y, isr
wait:
        jmp   y--, wait
        jmp   x--, pause
        jmp   next

dly:
        jmp   y--, dly          ; D taken + 1 not taken = D + 2 cycles
        jmp   bit
