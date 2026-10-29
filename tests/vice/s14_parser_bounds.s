; S14: command parser must not read past the file name
.include "tlib.inc"
        ; "S0" (length 2) followed by ":DELME15" in memory
        ldx #$00
    :   lda n_s0, x
        sta $3400, x
        inx
        cpx #10
        bne :-
        lda #2
        ldx #$00
        ldy #$34
        jsr EFS_setnam
        lda #$00
        jsr EFS_open
        jsr rec                 ; 0: open "S0" (fixed: $04 not found; before: scratch with length $ff)
        jsr EFS_close
        relocate
        setnam n_d15, 7
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 1: load DELME15 (expect 0: still there)
        ; empty name followed by "0:" in memory
        lda #$30
        sta $3500
        lda #$3a
        sta $3501
        lda #0
        ldx #$00
        ldy #$35
        jsr EFS_setnam
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 2: load with empty name (fixed: $08; before: $1e)
        ; "$" alone still lists
        relocate
        setnam n_dollar, 1
        lda #$00
        ldx #$00
        ldy #$60
        jsr EFS_load
        jsr rec                 ; 3: load "$" (expect 0)
        ; "S:" with nothing after it
        setnam n_sc, 2
        lda #$00
        jsr EFS_open
        jsr rec                 ; 4: open "S:" (expect $08)
        jsr EFS_close
        finish
    n_s0:  .byte "S0:DELME15"
    n_d15: .byte "DELME15"
    n_dollar: .byte "$"
    n_sc:  .byte "S:"
.include "tlib_code.inc"
