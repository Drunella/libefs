; S13: EFS_save must not consume the file name
.include "tlib.inc"
        setnam n_dup, 3
        lda #5
        jsr savex
        jsr rec                 ; 0: first save DUP (expect 0)
        lda #5                  ; same name, no setnam
        jsr savex
        jsr rec                 ; 1: second save (fixed: $3f exists; before: $08 missing name)
        setnam n_long, 20       ; 20 characters: stored as 16
        lda #5
        jsr savex
        jsr rec                 ; 2: save long name (expect 0)
        relocate
        setnam n_long16, 16
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 3: load by the 16-character name (expect 0)
        relocate
        setnam n_dollar, 1
        lda #$00
        ldx #$00
        ldy #$60
        jsr EFS_load            ; listing to $6000
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
    n_dup:    .byte "DUP"
    n_dollar: .byte "$"
    n_long:   .byte "ABCDEFGHIJKLMNOPQRST"
    n_long16: .byte "ABCDEFGHIJKLMNOP"
    len: .byte 0
.include "tlib_code.inc"
