; reviewer item A/D: defragment copies size+1 bytes; next save hits the stray byte
.include "tlib.inc"
        setnam n_a, 2
        lda #<300
        ldx #<($4000+300)
        ldy #>($4000+300)
        jsr save40
        jsr rec                 ; 0: save A1 (300 bytes from $4000)
        setnam n_b, 2
        ldx #<($4000+300)
        ldy #>($4000+300)
        jsr save40
        jsr rec                 ; 1: save B1 (load address $4000 -> first byte $00)
        setnam n_sb, 5
        lda #$00
        jsr EFS_open
        jsr rec                 ; 2: scratch B1
        jsr EFS_close
        jsr bankin
        jsr EFS_defragment
        jsr bankout_rec         ; 3: defragment
        sei                     ; dump new (area 2, hh) directory: bank 32 ROMH -> $6000
        jsr bankin
        lda #32
        sta $de00
        ldx #$00
    cp: lda $a000, x
        sta $6000, x
        lda $a100, x
        sta $6100, x
        inx
        bne cp
        lda #$00
        sta $de00
        jsr bankout
        cli
        setnam n_c, 2           ; C1 from $0801: first byte $01
        lda #$01
        sta zsrc
        lda #$08
        sta zsrc + 1
        lda #zsrc
        ldx #<($0801+300)
        ldy #>($0801+300)
        jsr EFS_save
        jsr rec                 ; 4: save C1 (bug: $19 write error)
        relocate
        setnam n_c, 2
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        stx endlo
        sty endhi
        jsr rec                 ; 5: load C1 (bug: loads although the save failed)
        lda endlo
        jsr rec                 ; 6: end low
        lda endhi
        jsr rec                 ; 7: end high
        lda $5000
        jsr rec                 ; 8: first data byte (expect $01; bug: $00)
        finish
    save40:
        lda #$00
        sta zsrc
        lda #$40
        sta zsrc + 1
        lda #zsrc
        jmp EFS_save
    n_a:  .byte "A1"
    n_b:  .byte "B1"
    n_sb: .byte "S0:B1"
    n_c:  .byte "C1"
    endlo: .byte 0
    endhi: .byte 0
.include "tlib_code.inc"
