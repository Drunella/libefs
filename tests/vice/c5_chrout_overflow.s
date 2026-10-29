; C5 test: like the C4 test, but after the first error chrout is
; called 3 more times (results at $c910); then close, read it back with chrin, and copy cartridge bank 0 to RAM.
; Started from the VICE monitor with "g c000" while the test menu runs
; (libefs and EAPI are initialized by the test cartridge).
; Results at $c900 (see labels), bank 0 ROML copied to $6000-$7fff.

EFS_util   = $df00
EFS_setnam = $df06
EFS_load   = $df0c
EFS_open   = $df12
EFS_close  = $df18
EFS_chrin  = $df1e
EFS_chrout = $df2a
EFS_readst = $df30

ptr = $fb

.segment "LOADADDR"
        .addr $c000

.segment "CODE"
        ; --- write until error -------------------------------------
        lda #name_len
        ldx #<name
        ldy #>name
        jsr EFS_setnam
        lda #1
        jsr EFS_open
        sta r_open_a
        lda #0
        rol
        sta r_open_c

    wloop:
        lda cnt                 ; data = low byte of the byte counter
        jsr EFS_chrout
        bcs werr
        inc cnt
        bne wloop
        inc cnt + 1
        bne wloop
        inc cnt + 2
        jmp wloop
    werr:
        sta r_err_a
        jsr EFS_readst
        sta r_err_st
        lda cnt
        sta r_cnt
        lda cnt + 1
        sta r_cnt + 1
        lda cnt + 2
        sta r_cnt + 2

        lda #$00                ; three more chrout calls after the error
        sta idx                 ; (EFS_chrout destroys X, so count in memory)
    more:
        lda #$00
        jsr EFS_chrout
        ldx idx
        sta r_more, x
        lda #$00
        rol
        sta r_more + 3, x
        inc idx
        lda idx
        cmp #$03
        bne more

        jsr EFS_close
        sta r_close_a
        lda #0
        rol
        sta r_close_c

        ; --- read back and compare ---------------------------------
        lda #name_len
        ldx #<name
        ldy #>name
        jsr EFS_setnam
        lda #0
        jsr EFS_open
        sta r_ropen_a
        lda #0
        sta cnt
        sta cnt + 1
        sta cnt + 2
    rloop:
        jsr EFS_chrin
        bcs rdone
        cmp cnt
        beq :+
        inc r_bad               ; count mismatches (16 bit)
        bne :+
        inc r_bad + 1
      : jsr EFS_readst
        and #$40
        bne reof
        inc cnt
        bne rloop
        inc cnt + 1
        bne rloop
        inc cnt + 2
        jmp rloop
    reof:
        inc cnt                 ; last byte was delivered with EOF
        bne rdone
        inc cnt + 1
        bne rdone
        inc cnt + 2
    rdone:
        lda cnt
        sta r_rcnt
        lda cnt + 1
        sta r_rcnt + 1
        lda cnt + 2
        sta r_rcnt + 2
        jsr EFS_close

        ; --- copy cartridge bank 0 ROML to $6000 -------------------
        sei
        lda $01
        pha
        lda #$37
        sta $01
        lda #$87
        sta $de02
        lda #$00
        sta $de00
        ldx #$00
    cpage:
        lda $8000, x
        sta $6000, x
        inx
        bne cpage
        inc cpage + 2
        inc cpage + 5
        lda cpage + 2
        cmp #$a0
        bne cpage
        lda #$04
        sta $de02
        pla
        sta $01
        cli

        lda #$42
        sta r_done
        sta results_done        ; done flag for tests/vice/run.py
    forever:
        jmp forever

    name:
        .byte "BIG"
    name_len = * - name

    cnt:
        .byte 0, 0, 0
    idx:
        .byte 0

.segment "RESULTS"
    r_open_a:   .byte 0   ; $c900
    r_open_c:   .byte 0   ; $c901
    r_cnt:      .byte 0, 0, 0  ; $c902 bytes written before the error
    r_err_a:    .byte 0   ; $c905 error code from chrout
    r_err_st:   .byte 0   ; $c906 readst after the error
    r_close_a:  .byte 0   ; $c907
    r_close_c:  .byte 0   ; $c908
    r_ropen_a:  .byte 0   ; $c909
    r_rcnt:     .byte 0, 0, 0  ; $c90a bytes read back
    r_bad:      .byte 0, 0     ; $c90d mismatches
    r_done:     .byte 0   ; $c90f $42 when finished
    r_more:     .byte 0, 0, 0, 0, 0, 0  ; $c910 A of 3 extra chrouts, then their C
    .res $f0 - 22
    results_done: .byte 0     ; $c9f0
