; helper routines, include at the end of the CODE segment
    rec:    ; store A and C at results[rp], rp += 2
        php
        ldx rp
        sta results, x
        lda #$00
        plp
        rol
        sta results + 1, x
        inx
        inx
        stx rp
        rts
    rp: .byte 0

    bankin:
        pha
        lda #$37
        sta $01
        lda #$87
        sta $de02
        lda #$00
        sta $de00
        pla
        rts

    bankout:
        php
        pha
        lda #$04
        sta $de02
        lda #$36
        sta $01
        pla
        plp
        rts

    bankout_rec:
        jsr bankout
        jmp rec
