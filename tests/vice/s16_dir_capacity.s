; S16: how many files fit into the directory (7 are there; 255 slots + terminator)
.include "tlib.inc"
        lda #$00
        sta idx
        sta ok
    nx: lda idx                 ; name "Fxx" (hex)
        lsr
        lsr
        lsr
        lsr
        jsr hex
        sta name + 1
        lda idx
        and #$0f
        jsr hex
        sta name + 2
        setnam name, 3
        lda #$00
        sta zsrc
        lda #$40
        sta zsrc + 1
        lda #zsrc
        ldx #$03
        ldy #$40
        jsr EFS_save
        bcs done
        inc ok
        inc idx
        bne nx
    done:
        jsr rec                 ; 0: first failing save: A, C (fixed/before: $48)
        lda ok
        jsr rec                 ; 1: files saved (fixed: 248 = 255-7; before: 247)
        finish
    hex:
        cmp #$0a
        bcc :+
        adc #$06
    :   adc #$30
        rts
    name: .byte "F00"
    idx: .byte 0
    ok: .byte 0
.include "tlib_code.inc"
