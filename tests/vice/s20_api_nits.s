; S20: "?" must not match the name padding; "@0:" is ignored on read/load;
; blocks free without the extra block
.include "tlib.inc"
        relocate
        setnam n_q, 6           ; "DATA1?" (6 chars) vs file "DATA1" (5 chars)
        jsr load5
        jsr rec                 ; 0: fixed: $04; before: 0 (? matched the padding)
        relocate
        setnam n_q5, 5          ; "DATA?" matches DATA1
        jsr load5
        jsr rec                 ; 1: expect 0
        relocate
        setnam n_at, 8          ; "@0:DATA1" on load
        jsr load5
        jsr rec                 ; 2: fixed: 0; before: $1e
        setnam n_at, 8          ; "@0:DATA1" on open for reading
        lda #$00
        jsr EFS_open
        jsr rec                 ; 3: fixed: 0; before: $1e
        jsr EFS_close
        relocate
        setnam n_d, 1
        lda #$00
        ldx #$00
        ldy #$60
        jsr EFS_load            ; listing: blocks free (fixed: 729; before: 728)
        jsr rec                 ; 4
        finish
    load5:
        lda #$00
        ldx #$00
        ldy #$50
        jmp EFS_load
    n_q:  .byte "DATA1?"
    n_q5: .byte "DATA?"
    n_at: .byte "@0:DATA1"
    n_d:  .byte "$"
.include "tlib_code.inc"
