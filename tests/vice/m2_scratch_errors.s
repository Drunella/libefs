; M2: scratch errors are reported with .C set and close the channel
.include "tlib.inc"
        setnam n_s1, 7
        lda #$00
        jsr EFS_open
        jsr rec                 ; 0: open "S:DATA1" (area 0): expect $1a, C set
        jsr EFS_chrin
        jsr rec                 ; 1: chrin afterwards: C set
        jsr EFS_close
        jsr rec                 ; 2: close
        setnam n_s2, 10
        lda #$00
        jsr EFS_open
        jsr rec                 ; 3: open "S0:DELME15": expect $01, C clear
        jsr EFS_close
        jsr rec                 ; 4: close: expect 0, C clear
        setnam n_s2, 10
        lda #$00
        jsr EFS_open
        jsr rec                 ; 5: scratch it again: expect $04 not found, C set
        jsr EFS_close
        setnam n_s3, 8
        lda #$01
        jsr EFS_open
        jsr rec                 ; 6: open(1) "S:DATA1*" (area 0): expect $1a, C set
        jsr EFS_close
        finish
    n_s1: .byte "S:DATA1"
    n_s2: .byte "S0:DELME15"
    n_s3: .byte "S:DATA1*"
.include "tlib_code.inc"
