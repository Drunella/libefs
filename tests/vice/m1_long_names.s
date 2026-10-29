; m1: names longer than 16 characters are truncated to 16 (kernal/1541 behaviour)
.include "tlib.inc"
        relocate
        setnam n_17, 17         ; "DATA567890123456X": first 16 match a file
        jsr load5
        jsr rec                 ; 0: fixed: 0; before: $04 (scan desynchronised)
        relocate
        setnam n_17b, 18        ; "DATA56789012345XY": 15 match, file is 15 chars
        jsr load5
        jsr rec                 ; 1: expect $04 (16th char X <> padding)
        relocate
        setnam n_dir, 19        ; "$:DATA567890123456X" lists the 16-char file
        lda #$00
        ldx #$00
        ldy #$60
        jsr EFS_load
        jsr rec                 ; 2: listing (count lines below)
        finish
    load5:
        lda #$00
        ldx #$00
        ldy #$50
        jmp EFS_load
    n_17:  .byte "DATA567890123456X"
    n_17b: .byte "DATA56789012345XY"
    n_dir: .byte "$:DATA567890123456X"
.include "tlib_code.inc"
