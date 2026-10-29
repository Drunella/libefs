; S15: "@" in save must report a failed scratch
.include "tlib.inc"
        setnam n_at0, 8         ; "@0:DATA1": DATA1 is in area 0 (write protected)
        lda #5
        jsr savex
        jsr rec                 ; 0: save @0:DATA1 (fixed: $1a; before: $3f)
        setnam n_at1, 10        ; "@0:DELME15": overwrite works
        lda #5
        jsr savex
        jsr rec                 ; 1: save @0:DELME15 (expect 0)
        relocate
        setnam n_d15, 7
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        stx endlo
        jsr rec                 ; 2: load DELME15 (expect 0)
        lda endlo
        jsr rec                 ; 3: end low (expect $04: the new 5-byte file)
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
    n_at0: .byte "@0:DATA1"
    n_at1: .byte "@0:DELME15"
    n_d15: .byte "DELME15"
    len: .byte 0
    endlo: .byte 0
.include "tlib_code.inc"
