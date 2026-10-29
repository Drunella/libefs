; M3 test: command prefix with the name crossing a page boundary.
; "S0:DELME640" is put at $33fe (name part starts at $3401), and $3301
; holds "DELME641" as bait: the buggy code scratches DELME641 instead.
.include "tlib.inc"
        ldx #$00
    :   lda n_bait, x
        sta $3301, x
        inx
        cpx #8
        bne :-
        ldx #$00
    :   lda n_cmd, x
        sta $33fe, x
        inx
        cpx #11
        bne :-
        lda #11
        ldx #$fe
        ldy #$33
        jsr EFS_setnam
        lda #$00
        jsr EFS_open
        jsr rec                 ; 0: open "S0:DELME640" at $33fe: expect $01
        jsr EFS_close
        relocate                ; which file is gone?
        setnam n_640, 8
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 1: load DELME640: expect $04 (scratched)
        setnam n_bait, 8
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 2: load DELME641: expect $00 (still there)
        ; directory command across a page: "$0:DELME6*" at $34fd
        ldx #$00
    :   lda n_dir, x
        sta $34fd, x
        inx
        cpx #10
        bne :-
        relocate
        lda #10
        ldx #$fd
        ldy #$34
        jsr EFS_setnam
        lda #$00
        ldx #$00
        ldy #$60
        jsr EFS_load
        jsr rec                 ; 3: load "$0:DELME6*" at $34fd: expect $00
        finish
    n_cmd:  .byte "S0:DELME640"
    n_640:  .byte "DELME640"
    n_bait: .byte "DELME641"
    n_dir:  .byte "$0:DELME6*"
.include "tlib_code.inc"
