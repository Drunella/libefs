; S10: a save that exactly fills the free space (fresh cart: 186,664 bytes free)
.include "tlib.inc"
        setnam n_fill, 4
        lda #$01
        jsr EFS_open
        jsr rec                 ; 0: open(1) FILL
        lda #<186564            ; leaves 100 bytes
        sta cnt
        lda #>186564
        sta cnt + 1
        lda #^186564
        sta cnt + 2
    fl: lda #$00
        jsr EFS_chrout
        bcs fe
        lda cnt
        bne fl_lo
        lda cnt + 1
        bne fl_mid
        dec cnt + 2
    fl_mid:
        dec cnt + 1
    fl_lo:
        dec cnt
        lda cnt
        ora cnt + 1
        ora cnt + 2
        bne fl
    fe: jsr rec                 ; 1: last chrout (expect 0)
        jsr EFS_close
        jsr rec                 ; 2: close
        setnam n_x98, 3
        lda #98                 ; 98 + 2 = 100: exact fit
        jsr savex
        jsr rec                 ; 3: save X98 (fixed: 0; before: $48)
        setnam n_x97, 3
        lda #97
        jsr savex
        jsr rec                 ; 4: save X97 (expect $48: no room left / before: 0)
        relocate
        setnam n_x98, 3
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        stx endlo
        jsr rec                 ; 5: load X98
        lda endlo
        jsr rec                 ; 6: end low (expect $61: 98 bytes at $5000)
        finish
    savex:
        sta len
        lda #$00
        sta zsrc
        lda #$40
        sta zsrc + 1
        lda #zsrc
        ldx len
        ldy #$40
        jmp EFS_save
    n_fill: .byte "FILL"
    n_x98:  .byte "X98"
    n_x97:  .byte "X97"
    cnt:    .byte 0, 0, 0
    len:    .byte 0
    endlo:  .byte 0
.include "tlib_code.inc"
