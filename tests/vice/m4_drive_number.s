; M4 test: drive number in command prefixes
.include "tlib.inc"
        relocate
        setnam n1, 4
        jsr load6
        jsr rec                 ; 0: load "$1:*": expect $00 (directory)
        relocate
        setnam n2, 7
        jsr load6
        jsr rec                 ; 1: load "/:DATA1": expect $04 (file name, not found)
        relocate
        setnam n3, 7
        jsr load6
        jsr rec                 ; 2: load "0:DATA1" -> command "0": expect $1e
        setnam n4, 11
        lda #$00
        jsr EFS_open
        jsr rec                 ; 3: open "S1:DELME642": expect $01
        jsr EFS_close
        relocate
        setnam n5, 10
        jsr load6
        jsr rec                 ; 4: load "$9:DELME64*" to $6000: expect $00
        finish
    load6:
        lda #$00
        ldx #$00
        ldy #$60
        jmp EFS_load
    n1: .byte "$1:*"
    n2: .byte "/:DATA1"
    n3: .byte "0:DATA1"
    n4: .byte "S1:DELME642"
    n5: .byte "$9:DELME64*"
.include "tlib_code.inc"
