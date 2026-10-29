; S9: entry 3 (DELME641) has flags $7f (type $1f, not blank)
.include "tlib.inc"
        relocate
        setnam n_d, 1
        jsr load6
        jsr rec                 ; 0: load "$" to $6000
        relocate
        setnam n_642, 8
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 1: load DELME642 (behind the corrupt entry)
        setnam n_n, 2
        lda #<300
        ldx #<($4000+300)
        ldy #>($4000+300)
        jsr save40
        jsr rec                 ; 2: save N1
        jsr bankin
        jsr EFS_defragment
        jsr bankout_rec         ; 3: defragment (fixed: A=1 dropped)
        relocate
        setnam n_d, 1
        lda #$00
        ldx #$00
        ldy #$70
        jsr EFS_load
        jsr rec                 ; 4: load "$" to $7000 after defragment
        relocate
        setnam n_642, 8
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 5: load DELME642 after defragment
        finish
    load6:
        lda #$00
        ldx #$00
        ldy #$60
        jmp EFS_load
    save40:
        lda #$00
        sta zsrc
        lda #$40
        sta zsrc + 1
        lda #zsrc
        jmp EFS_save
    n_d:   .byte "$"
    n_642: .byte "DELME642"
    n_n:   .byte "N1"
.include "tlib_code.inc"
