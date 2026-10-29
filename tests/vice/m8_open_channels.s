; M8 test: load/save while a channel is open must not disturb it
.include "tlib.inc"
        ; --- write file: chrout, load+save attempts in the middle ---
        setnam n_wf, 2
        lda #$01
        jsr EFS_open
        jsr rec                 ; 0: open(1) "WF"
        lda #$00                ; load address $5000
        jsr EFS_chrout
        lda #$50
        jsr EFS_chrout
        ldx #$00
        stx val
    :   lda val
        jsr EFS_chrout
        inc val
        lda val
        cmp #$04
        bne :-
        relocate                ; attempts while open (these must fail with 2)
        setnam n_data1, 5
        lda #$00
        ldx #$00
        ldy #$70
        jsr EFS_load
        jsr rec                 ; 1: load while open: expect $02, C set
        lda #$00
        sta zsrc
        lda #$40
        sta zsrc + 1
        lda #zsrc
        ldx #$10
        ldy #$40
        jsr EFS_save
        jsr rec                 ; 2: save while open: expect $02, C set
    :   lda val                 ; 4 more data bytes
        jsr EFS_chrout
        inc val
        lda val
        cmp #$08
        bne :-
        jsr EFS_close
        jsr rec                 ; 3: close: expect 0
        ldx #$00                ; load it back
        txa
    :   sta $5000, x
        inx
        bne :-
        relocate
        setnam n_wf, 2
        lda #$00
        ldx #$00
        ldy #$50
        jsr EFS_load
        stx endlo               ; save X/Y first, rec destroys X
        sty endhi
        jsr rec                 ; 4: load WF
        lda endlo
        jsr rec                 ; 5: end address low (expect $07: 8 data bytes)
        lda endhi
        jsr rec                 ; 6: end address high (expect $50)
        ldx #$07                ; data 0..7 at $5000-$5007?
        ldy #$00
    :   txa
        cmp $5000, x
        beq :+
        iny
    :   dex
        bpl :--
        tya
        jsr rec                 ; 7: mismatches (expect 0)

        ; --- read file: save attempt in the middle, then chrin ---
        setnam n_d1024, 8
        lda #$00
        jsr EFS_open
        jsr EFS_chrin
        jsr EFS_chrin
        jsr EFS_chrin
        sta val                 ; 3rd byte
        lda #zsrc
        ldx #$10
        ldy #$40
        jsr EFS_save
        jsr rec                 ; 8: save while reading: expect $02
        jsr EFS_chrin
        jsr rec                 ; 9: chrin after that: expect C clear
        jsr EFS_close

        ; --- directory: load attempt in the middle, count bytes ---
        jsr dircount
        jsr rec                 ; 10: listing bytes (low), undisturbed
        lda #$01
        sta disturb
        jsr dircount
        jsr rec                 ; 11: listing bytes (low), with a load in between
        finish

    dircount:
        setnam n_dollar, 1
        lda #$00
        jsr EFS_open
        lda #$00
        sta cnt
        sta cnt + 1
    dl: jsr EFS_chrin
        bcs dd
        inc cnt
        bne :+
        inc cnt + 1
    :   lda cnt
        cmp #$40
        bne dl
        lda disturb
        beq dl
        relocate
        setnam n_data1, 5
        lda #$00
        ldx #$00
        ldy #$70
        jsr EFS_load            ; must fail with 2 and not disturb the listing
        jmp dl
    dd: jsr EFS_close
        lda cnt
        clc
        rts

    n_wf:    .byte "WF"
    n_data1: .byte "DATA1"
    n_d1024: .byte "DATA1024"
    n_dollar: .byte "$"
    val:     .byte 0
    endlo:   .byte 0
    endhi:   .byte 0
    cnt:     .word 0
    disturb: .byte 0
.include "tlib_code.inc"
