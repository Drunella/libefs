; shared definitions for the VICE test programs (included by *test.s)
; test programs run at $c000, results at $c900 (2 bytes per rec), done flag $c9f0

EFS_init_minieapi = $8006
EFS_defragment    = $8009
EFS_format        = $800c
EFS_validate      = $800f
EFS_util   = $df00
EFS_setnam = $df06
EFS_load   = $df0c
EFS_open   = $df12
EFS_close  = $df18
EFS_chrin  = $df1e
EFS_save   = $df24
EFS_chrout = $df2a
EFS_readst = $df30

zsrc = $fb

.macro setnam name, len
        lda #len
        ldx #<name
        ldy #>name
        jsr EFS_setnam
.endmacro

.macro relocate
        lda #$01
        ldy #$00
        jsr EFS_util
.endmacro

.macro finish
        lda #$42
        sta results_done
    :   jmp :-
.endmacro

.segment "LOADADDR"
        .addr $c000

.segment "RESULTS"
    results:      .res $f0
    results_done: .byte 0

.segment "CODE"
