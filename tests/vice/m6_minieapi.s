; M6 test: write operations with MiniEAPI must be refused
.include "tlib.inc"
EFS_init_eapi = $8003
        jsr save1
        jsr rec                 ; 0: save "E1" with EAPI (expect 0)
        jsr bankin
        jsr EFS_init_minieapi
        jsr bankout
        jsr save2
        jsr rec                 ; 1: save "M1" with MiniEAPI (expect $1a, C set)
        setnam n_m2, 2
        lda #$01
        jsr EFS_open
        jsr rec                 ; 2: open(1) "M2" (expect $1a, C set)
        jsr EFS_close
        setnam n_s, 9
        lda #$00
        jsr EFS_open
        jsr rec                 ; 3: open "S:DELME15" (expect $1a, C set)
        jsr EFS_close
        jsr bankin
        jsr EFS_defragment
        jsr bankout_rec         ; 4: defragment (expect $1a, C set)
        jsr bankin
        jsr EFS_format
        jsr bankout_rec         ; 5: format (expect $1a, C set)
        relocate
        setnam n_d, 7
        jsr load5
        jsr rec                 ; 6: load DELME15 with MiniEAPI (expect 0: still there)
        relocate
        setnam n_m1, 2
        jsr load5
        jsr rec                 ; 7: load M1 (expect $04)
        jsr bankin
        lda #$cd                ; back to the real EAPI
        jsr EFS_init_eapi
        jsr bankout_rec         ; 8: init eapi (C clear)
        jsr save2
        jsr rec                 ; 9: save "M1" with EAPI again (expect 0)
        finish
    save1:
        setnam n_e1, 2
        jmp savex
    save2:
        setnam n_m1, 2
    savex:
        lda #$00
        sta zsrc
        lda #$40
        sta zsrc + 1
        lda #zsrc
        ldx #$10
        ldy #$40
        jmp EFS_save
    load5:
        lda #$00
        ldx #$00
        ldy #$50
        jmp EFS_load
    n_e1: .byte "E1"
    n_m1: .byte "M1"
    n_m2: .byte "M2"
    n_s:  .byte "S:DELME15"
    n_d:  .byte "DELME15"
.include "tlib_code.inc"
