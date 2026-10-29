; C8 test: open with a scratch command, then chrin/chrout/close.
; Results at $c900, 2 bytes (A, C) per step:
;   0 open(1) "S:DELME384"   1 chrin   2 chrout   3 close
;   4 open(0) "DELME384"     5 close
;   6 open(0) "S0:DELME640"  7 close
; $c9f0 = $42 when done.
EFS_setnam = $df06
EFS_open   = $df12
EFS_close  = $df18
EFS_chrin  = $df1e
EFS_chrout = $df2a
.segment "LOADADDR"
        .addr $c000
.segment "CODE"
        lda #n1_len
        ldx #<n1
        ldy #>n1
        jsr EFS_setnam
        lda #$01
        jsr EFS_open
        jsr rec
        jsr EFS_chrin
        jsr rec
        lda #$55
        jsr EFS_chrout
        jsr rec
        jsr EFS_close
        jsr rec

        lda #n2_len
        ldx #<n2
        ldy #>n2
        jsr EFS_setnam
        lda #$00
        jsr EFS_open
        jsr rec
        jsr EFS_close
        jsr rec

        lda #n3_len
        ldx #<n3
        ldy #>n3
        jsr EFS_setnam
        lda #$00
        jsr EFS_open
        jsr rec
        jsr EFS_close
        jsr rec

        lda #$42
        sta results_done
    forever:
        jmp forever

    rec:
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

    n1: .byte "S:DELME384"
    n1_len = * - n1
    n2: .byte "DELME384"
    n2_len = * - n2
    n3: .byte "S0:DELME640"
    n3_len = * - n3
    rp: .byte 0
.segment "RESULTS"
    results:      .res $f0
    results_done: .byte 0
