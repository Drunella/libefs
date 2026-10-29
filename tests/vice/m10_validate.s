; M10: EFS_validate on prepared images (see m10 image variants), then a
; defragment + verify to show the cartridge is usable afterwards
.include "tlib.inc"
        jsr bankin
        jsr EFS_validate
        jsr bankout_rec         ; 0: validate A, C
        jsr bankin
        jsr EFS_validate
        jsr bankout_rec         ; 1: validate again (expect 0)
        relocate
        setnam n_17, 8
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 3: load DELME17K
        jsr bankin
        jsr EFS_defragment
        jsr bankout_rec         ; 4: defragment
        relocate
        setnam n_17, 8
        lda #$01
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 5: verify DELME17K after the defragment
        jsr EFS_readst
        jsr rec                 ; 6: readst (expect $40)
        jsr bankin
        jsr EFS_validate
        jsr bankout_rec         ; 7: validate after the defragment (expect 0)
        relocate
        setnam n_d, 1
        lda #$00
        ldx #$00
        ldy #$60
        jsr EFS_load            ; listing to $6000
        jsr rec                 ; 2: load "$"
        finish
    n_d:  .byte "$"
    n_17: .byte "DELME17K"
.include "tlib_code.inc"
