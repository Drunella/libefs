; C7 test: EFS_save with invalid and valid address ranges.
; For each case: save, then load the file relocated to $5000 and compare.
; Results at $c900, 6 bytes per case:
;   save A, save C, load A, load C, mismatches (16 bit)
; $c9f0 = $42 when done.
; Started from the VICE monitor with "g c000" while the test menu runs.

EFS_util   = $df00
EFS_setnam = $df06
EFS_load   = $df0c
EFS_save   = $df24

src  = $4000
dst  = $5000
zsrc = $fb
p1   = $fd
p2   = $02

.segment "LOADADDR"
        .addr $c000

.segment "CODE"
        ldx #$00
        lda #$03
    fill:
        sta src, x
        sta src + $100, x
        clc
        adc #$07
        inx
        bne fill

        lda #$00
        sta case
    nextcase:
        lda case
        asl
        asl
        tax
        lda ranges, x
        sta start
        lda ranges + 1, x
        sta start + 1
        lda ranges + 2, x
        sta end
        lda ranges + 3, x
        sta end + 1

        lda case
        clc
        adc #$30
        sta name + 1

        ldx #$00
        txa
    clr:
        sta dst, x
        sta dst + $100, x
        inx
        bne clr

        ; save start .. end (exclusive)
        lda #$02
        ldx #<name
        ldy #>name
        jsr EFS_setnam
        lda start
        sta zsrc
        lda start + 1
        sta zsrc + 1
        ldx end
        ldy end + 1
        lda #zsrc
        jsr EFS_save
        jsr rec_ac

        ; load relocated to dst
        lda #$01
        ldy #$00
        jsr EFS_util
        lda #$02
        ldx #<name
        ldy #>name
        jsr EFS_setnam
        lda #$00
        ldx #<dst
        ldy #>dst
        jsr EFS_load
        jsr rec_ac

        ; compare (end - start) bytes if the range is valid
        lda #$00
        sta bad
        sta bad + 1
        sec
        lda end
        sbc start
        sta cntd
        lda end + 1
        sbc start + 1
        sta cntd + 1
        bcc cmpdone             ; negative range: nothing to compare
        lda start
        sta p1
        lda start + 1
        sta p1 + 1
        lda #<dst
        sta p2
        lda #>dst
        sta p2 + 1
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
        ldx rp
        lda bad
        sta results, x
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

    ranges:  ; start, end (exclusive)
        .word $4080, $4010   ; 0: end < start, same page
        .word $4100, $4000   ; 1: end < start, page below
        .word $4012, $4012   ; 2: empty
        .word $4000, $4001   ; 3: 1 byte
        .word $40f0, $4110   ; 4: 32 bytes across a page
    ncases = (* - ranges) / 4

    name:   .byte "V0"
    case:   .byte 0
    start:  .word 0
    end:    .word 0
    cntd:   .word 0
    bad:    .word 0
    rp:     .byte 0

.segment "RESULTS"
    results:      .res $f0
    results_done: .byte 0
