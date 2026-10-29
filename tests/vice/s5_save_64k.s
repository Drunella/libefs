; reviewer item C: EFS_save of 65534 bytes passes the space check (carry lost)
.include "tlib.inc"
        setnam n_fill, 4
        lda #$01
        jsr EFS_open
        jsr rec                 ; 0: open(1) FILL
        lda #<156662            ; leaves 30000 bytes free
        sta cnt
        lda #>156662
        sta cnt + 1
        lda #^156662
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
    fe: jsr rec                 ; 1: last chrout
        jsr EFS_close
        jsr rec                 ; 2: close
        setnam n_big, 4
        lda #$01
        sta zsrc
        lda #$00
        sta zsrc + 1
        lda #zsrc
        ldx #$ff
        ldy #$ff
        jsr EFS_save            ; $0001-$fffe: 65534 bytes into 30000 free
        jsr rec                 ; 3: save (expect $48; bug: passes and writes past the area)
        finish
    n_fill: .byte "FILL"
    n_big:  .byte "BIGS"
    cnt:    .byte 0, 0, 0
.include "tlib_code.inc"
