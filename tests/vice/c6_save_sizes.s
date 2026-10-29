; C6 test: save files with different data lengths with EFS_save, load
; them back (relocated to $5000) and compare.
; Started from the VICE monitor with "g c000" while the test menu runs.
; Results at $c900: 8 bytes per case (see "record"), $c9f0 = $42 when done.

EFS_util   = $df00
EFS_setnam = $df06
EFS_load   = $df0c
EFS_save   = $df24

src  = $4000
dst  = $5000
zsrc = $fb            ; zp pointer with the save start address
p1   = $fd            ; compare pointers
p2   = $02            ; ($02/$03 unused by KERNAL)

.segment "LOADADDR"
        .addr $c000

.segment "CODE"
        ; fill source with a pattern
        ldx #$00
        lda #$03
    fill:
        sta src, x
        sta src + $100, x
        sta src + $200, x
        sta src + $300, x
        clc
        adc #$07
        inx
        bne fill

        lda #$00
        sta case
    nextcase:
        lda case
        asl
        tax
        lda sizes, x
        sta len
        lda sizes + 1, x
        sta len + 1

        ; name "Cn"
        lda case
        clc
        adc #$30
        sta name + 1

        ; clear destination (4 pages)
        ldx #$00
        txa
    clr:
        sta dst, x
        sta dst + $100, x
        sta dst + $200, x
        sta dst + $300, x
        inx
        bne clr

        ; save src .. src+len (end address is exclusive)
        lda #$02
        ldx #<name
        ldy #>name
        jsr EFS_setnam
        lda #<src
        sta zsrc
        lda #>src
        sta zsrc + 1
        clc
        lda #<src
        adc len
        tax
        lda #>src
        adc len + 1
        tay
        lda #zsrc
        jsr EFS_save
        jsr rec_ac              ; bytes 0,1: save A, C

        ; load relocated to dst
        lda #$01                ; util: setlfs
        ldy #$00                ; secondary 0 = relocate
        jsr EFS_util
        lda #$02
        ldx #<name
        ldy #>name
        jsr EFS_setnam
        lda #$00
        ldx #<dst
        ldy #>dst
        jsr EFS_load
        stx endlo
        sty endhi
        jsr rec_ac              ; bytes 2,3: load A, C
        ldx rp
        lda endlo
        sta results, x          ; bytes 4,5: end address (last byte)
        lda endhi
        sta results + 1, x
        inx
        inx

        ; compare len bytes (count mismatches, 16 bit)
        lda #$00
        sta bad
        sta bad + 1
        lda #<src
        sta p1
        lda #>src
        sta p1 + 1
        lda #<dst
        sta p2
        lda #>dst
        sta p2 + 1
        lda len
        sta cntd
        lda len + 1
        sta cntd + 1
    cmploop:
        lda cntd
        ora cntd + 1
        beq cmpdone
        ldy #$00
        lda (p1), y
        cmp (p2), y
        beq :+
        inc bad
        bne :+
        inc bad + 1
      : inc p1
        bne :+
        inc p1 + 1
      : inc p2
        bne :+
        inc p2 + 1
      : lda cntd
        bne :+
        dec cntd + 1
      : dec cntd
        jmp cmploop
    cmpdone:
        ; also check that the byte after the file was not touched
        ldy #$00
        lda (p2), y
        beq :+
        inc bad
      : lda bad
        sta results, x          ; bytes 6,7: mismatches
        lda bad + 1
        sta results + 1, x
        inx
        inx
        stx rp

        inc case
        lda case
        cmp #ncases
        beq done
        jmp nextcase
    done:
        lda #$42
        sta results_done
    forever:
        jmp forever

    rec_ac:
        ; store A and C at results[rp], rp += 2
        php
        ldx rp
        sta results, x
        lda #$00
        plp
        rol
        sta results + 1, x
        inx
        inx
        stx rp
        rts

    sizes:  ; data length (without load address)
        .word 255, 254, 511, 256, 1, 767
    ncases = (* - sizes) / 2

    name:   .byte "C0"
    case:   .byte 0
    len:    .word 0
    cntd:   .word 0
    bad:    .word 0
    endlo:  .byte 0
    endhi:  .byte 0
    rp:     .byte 0

.segment "RESULTS"
    results:      .res $f0
    results_done: .byte 0
