; m2: directory bounds with a directory that has no terminator (all 256
; slots used, image patched); listing and save must stop at the end
.include "tlib.inc"
        relocate
        setnam n_d, 1
        lda #$00
        ldx #$00
        ldy #$60
        jsr EFS_load
        stx endlo
        sty endhi
        jsr rec                 ; 0: load "$" (lines counted from the dump)
        lda endlo
        jsr rec                 ; 1: end low
        lda endhi
        jsr rec                 ; 2: end high
        relocate
        setnam n_x, 4           ; load the last entry's file (slot 255 = DELME384 copy)
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 3: load (expect 0)
        setnam n_n, 2           ; a save must fail: directory full (no free slot)
        lda #$00
        sta zsrc
        lda #$40
        sta zsrc + 1
        lda #zsrc
        ldx #$05
        ldy #$40
        jsr EFS_save
        jsr rec                 ; 4: save (expect an error, not a crash)
        finish
    n_d: .byte "$"
    n_x: .byte "X255"
    n_n: .byte "N1"
    endlo: .byte 0
    endhi: .byte 0
.include "tlib_code.inc"
