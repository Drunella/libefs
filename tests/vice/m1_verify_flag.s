; M1: the verify flag of EFS_load must not stay set
.include "tlib.inc"
        relocate
        jsr clear
        setnam n_f, 7
        lda #$01                ; verify against empty memory: mismatch
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr EFS_readst
        jsr rec                 ; 0: readst after verify (expect $10)
        setnam n_f, 7
        lda #$00                ; load (no setlfs before)
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 1: load A, C
        jsr EFS_readst
        jsr rec                 ; 2: readst after load (expect $40, bug $10)
        lda $5002
        jsr rec                 ; 3: byte of the file at $5002 (bug: 0)
        setnam n_f, 7
        lda #$01                ; verify against the loaded data: match
        ldx #$00
        ldy #$50
        jsr EFS_load
        jsr rec                 ; 4: verify A, C (expect 0, clear)
        jsr EFS_readst
        jsr rec                 ; 5: readst (expect $40)
        finish
    clear:
        ldx #$00
        txa
    :   sta $5000, x
        inx
        bne :-
        rts
    n_f: .byte "DELME15"
.include "tlib_code.inc"
