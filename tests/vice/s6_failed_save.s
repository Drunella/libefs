; S6/S7: write errors during save and at close must not leave live entries
.include "tlib.inc"
        lda #$ff
        sta $4001               ; first data byte: $ff, written over a pre-programmed byte
        setnam n_a, 2
        lda #$01                ; start $4001: first flash byte $01 over a pre-programmed $00
        sta zsrc
        lda #$40
        sta zsrc + 1
        lda #zsrc
        ldx #<($4001+300)
        ldy #>($4001+300)
        jsr EFS_save
        jsr rec                 ; 0: save A1 (expect $19, C set)
        relocate
        setnam n_a, 2
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 1: load A1 (fixed: $04 not found; before: 0, live entry)
        setnam n_w, 1
        lda #$01
        jsr EFS_open
        jsr rec                 ; 2: open(1) W (entry 7, size low pre-programmed $00)
        lda #$00
        jsr EFS_chrout
        lda #$50
        jsr EFS_chrout
        lda #$01
        jsr EFS_chrout
        lda #$02
        jsr EFS_chrout
        lda #$03
        jsr EFS_chrout
        jsr EFS_close
        jsr rec                 ; 3: close (expect $19, C set: size 5 cannot be written)
        relocate
        setnam n_d, 1
        lda #$00
        ldx #$00
        ldy #$60
        jsr EFS_load            ; listing to $6000
        jsr rec                 ; 4: load "$"
        finish
    n_a: .byte "A1"
    n_w: .byte "W"
    n_d: .byte "$"
.include "tlib_code.inc"
