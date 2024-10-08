; ----------------------------------------------------------------------------
; Copyright 2023 Drunella
;
; Licensed under the Apache License, Version 2.0 (the "License");
; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
;
;     http://www.apache.org/licenses/LICENSE-2.0
;
; Unless required by applicable law or agreed to in writing, software
; distributed under the License is distributed on an "AS IS" BASIS,
; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; See the License for the specific language governing permissions and
; limitations under the License.
; ----------------------------------------------------------------------------

.feature c_comments

.include "easyflash.i"

.import popa 
.import popax
.importzp sreg

.import _cputc

.export _EFS_defragment_wrapper
.export _EFS_format_wrapper
.export _EFS_get_endadress
.export _EFS_readst_wrapper
.export _EFS_setnam_wrapper
.export _EFS_setlfs_wrapper
.export _EFS_load_wrapper
.export _EFS_open_wrapper
.export _EFS_close_wrapper
.export _EFS_chrin_wrapper
.export _EFS_chrout_wrapper
.export _EFS_save_wrapper

.export _SYS_get_system
.export _SYS_get_sid
.export _TIMER_get_system
.export _TIMER_measure
.export _TIMER_reset
.export _SYS_readdir


.segment "DATA"

    end_address:
        .word $0000


.segment "CODE"

    ; uint8_t __fastcall__ EFS_defragment_wrapper(void);
    _EFS_defragment_wrapper:
        ; bank easyflash in
        lda #$37
        sta $01
        lda #$87   ; led, 16k mode
        sta $de02
        lda #$00   ; EFSLIB_ROM_BANK
        sta $de00

;        sei
        jsr EFS_defragment
;        cli
        pha

        lda #$36
        sta $01
        lda #$04   ; easyflash off
        sta $de02
        pla
        ldx #$00
        rts
        

    ; uint8_t __fastcall__ EFS_format_wrapper(void);
    _EFS_format_wrapper:
        ; bank easyflash in
        lda #$37
        sta $01
        lda #$87   ; led, 16k mode
        sta $de02
        lda #$00   ; EFSLIB_ROM_BANK
        sta $de00

;        sei
        jsr EFS_format
;        cli
        pha

        lda #$36
        sta $01
        lda #$04   ; easyflash off
        sta $de02        
        pla
        ldx #$00
        rts
        

    ; char* __fastcall__ EFS_get_endadress(void);
    _EFS_get_endadress:
        lda end_address
        ldx end_address + 1
        rts


    ; uint8_t __fastcall__ EFS_readst_wrapper();
    _EFS_readst_wrapper:
        jsr EFS_readst
        ldx #$00
        rts


    ; uint8_t __fastcall__ EFS_setnam_wrapper(char* name, uint8_t length);
    _EFS_setnam_wrapper:
        pha        ; length in A
        jsr popax  ; name in A/X
        pha
        txa
        tay
        pla
        tax
        pla

        ; parameter:
        ;    A: name length
        ;    X: name address low
        ;    Y: name address high
        ; return: none
        jsr EFS_setnam
        bcc :+
        lda #$ff
        ldx #$00
        rts
      : lda #$00
        ldx #$00
        rts


    ; uint8_t __fastcall__ EFS_setlfs_wrapper(uint8_t secondary);
    _EFS_setlfs_wrapper:
        ;pha
        ;jsr popa
        tay
        ;pla
        ;tay
        ;txa

        ; parameter:
        ;    Y: secondary address(0=load, ~0=verify)
        ; return: none
        jsr EFS_setlfs
        bcc :+
        lda #$ff
        ldx #$00
        rts
      : lda #$00
        ldx #$00
        rts


    ; uint8_t __fastcall__ EFS_open_wrapper(uint8_t mode);
    _EFS_open_wrapper:
;        sei
        jsr EFS_open
;        cli

        bcc :+
        cmp #$00
        bne :+
        lda #$ff
    :   ldx #$00
        rts


    ; uint8_t __fastcall__ EFS_close_wrapper();
    _EFS_close_wrapper:
;        sei
        jsr EFS_close
;        cli

        bcc :+
        cmp #$00
        bne :+
        lda #$ff
    :   ldx #$00
        rts


    ; uint8_t __fastcall__ EFS_chrin_wrapper(uint8_t* data);
    _EFS_chrin_wrapper:
        sta sreg
        stx sreg+1

;        sei
        jsr EFS_chrin
;        cli

        bcs :+
        ldy #$00
        sta (sreg), y
        tya
        tax
        rts
    :   cmp #$00
        bne :+
        lda #$ff
    :   ldx #$00
        rts

    ; uint8_t __fastcall__ EFS_chrout_wrapper(uint8_t data);
    _EFS_chrout_wrapper:
;        sei
        jsr EFS_chrout
;        cli
        bcc :+
        cmp #$00
        bne :+
        lda #$ff  ; no error value?
    :   ldx #$00
        rts


    ; uint8_t __fastcall__ EFS_load_wrapper(char* address, uint8_t mode);
    _EFS_load_wrapper:
        pha        ; mode in A
        jsr popax  ; addr in A/X
        pha
        txa
        tay
        pla
        tax
        pla

        ; parameter:
        ;    A: 0=load, 1-255=verify
        ;    X: load address low
        ;    Y: load address high
        ; return:
        ;    A: error code ($04: file not found, $05: device not present; $08: missing filename;
        ;    X: end address low
        ;    Y: end address high
        ;    .C: 1 if error
;        sei
        jsr EFS_load
;        cli

        stx end_address
        sty end_address + 1

        bcc :+
        cmp #$00
        bne :+
        lda #$ff
    :   ldx #$00
        rts


    ; uint8_t __fastcall__ EFS_save_wrapper(char* startaddress, char* endaddress);
    _EFS_save_wrapper:
        pha        ; endaddress in A/X; high
        txa
        pha        ; low

        jsr popax  ; startaddress in A/X -> $40/41
        sta $40    
        stx $41

        pla
        tay
        pla
        tax

        lda #$40
;        sei
        jsr EFS_save
;        cli

        bcc :+
        cmp #$00
        bne :+
        lda #$ff
    :   ldx #$00
        rts


    ; uint16_t __fastcall__ TIMER_get_system()
    _TIMER_get_system:
        sei             ; accounting for NMIs is not needed when
        lda #$00        ; used as part of application initialisation
        sta $dd08       ; TO2TEN start TOD - in case it wasn't running
    :   cmp $dd08       ; TO2TEN wait until tenths
        beq :-          ; register changes its value

        lda #$ff        ; count from $ffff (65535) down
        sta $dd04       ; TI2ALO both timer A register
        sta $dd05       ; TI2AHI set to $ff

        lda #%00010001  ; bit seven = 0 - 60Hz TOD mode
        sta $dd0e       ; CI2CRA start the timer

        lda $dd08       ; TO2TEN
    :   cmp $dd08       ; poll TO2TEN for change
        beq :-

        lda $dd05       ; TI2AHI expect (approximate) $7f4a $70a6 $3251 $20c0
        ldx $dd04
        cli
        rts


    ; uint8_t __fastcall__ _SYS_get_system()
    _SYS_get_system:
        sei
        ldy #$04
    ld_DEY:
        ldx #$88     ; DEY = $88
    waitline:
        cpy $d012
        bne waitline
        dex
        bmi ld_DEY + 1
    cycle_wait_loop:
        lda $d012 - $7f,x
        dey
        bne cycle_wait_loop
        and #$03
        ldx #$00
        cli
        rts


    ; uint8_t __fastcall__ _SYS_get_sid()
    ; from http://unusedino.de/ec64/technical/c=hacking/ch20.html
    _SYS_get_sid:
        sei
        lda #11
        sta $d011

        ;sid setup here
        lda #$20
        sta $d40e
        sta $d40f

        lda #%00110001
        sta $d412

        ldx #0
        stx sid_measure

    @loop:
        lda $d41b
        cmp sid_measure
        bcc @ahead
        sta sid_measure
    @ahead:
        dex
        bne @loop

        lda #%00110000
        sta $d412

        cli
        lda #27
        sta $d011

        lda sid_measure
        bmi @sid8580
        bpl @sid6581

        lda #$ff  ; detection error
        rts

    @sid8580:
        lda #$02
        rts

    @sid6581:
        lda #$01
        rts

    sid_measure:
        .byte 0


    ; void __fastcall__ TIMER_reset()
    _TIMER_reset:
        lda #$7f        ; disable all interrupts on CIA#2
        sta $dd0d
        lda #$0
        sta $dd0e       ; stop timer A
        sta $dd0f       ; stop timer B
        lda #$ff
        sta $dd04
        sta $dd05
        sta $dd06
        sta $dd07

        ;     76543210
;        lda #$11        ; start timer A counting cycles
;        sta $dd0e
;        lda #$51        ; start timer B counting underflows
;        sta $dd0f       ; of timer A
        lda #%01000001
        sta $dd0f
        lda #%00000001
        sta $dd0e
        rts


    ; uint32_t __fastcall__ TIMER_measure()
    _TIMER_measure:
        lda #$0
        sta $dd0e       ; stop timer A
        sta $dd0f       ; stop timer B

        lda $dd07
        sta sreg+1
        lda $dd06
        sta sreg
        ldx $dd05
        lda $dd04

        rts
        
    


    ; uint8_t __fastcall__ SYS_readdir(uint8_t device);
    _SYS_readdir:
        pha
        LDA #$01
        LDX #<@dirname
        LDY #>@dirname
        JSR $FFBD      ; call SETNAM

        LDA #$02       ; filenumber 2
        pla 
        tax
        LDA #$02       ; filenumber 2
        LDY #$00       ; secondary address 0 (required for dir reading!)
        JSR $FFBA      ; call SETLFS

        lda #$c0
        sta @setbyte + 2
        lda #$00
        sta @setbyte + 1 

        JSR $FFC0      ; call OPEN (open the directory)
        BCS @error     ; quit if OPEN failed

        LDX #$02       ; filenumber 2
        JSR $FFC6      ; call CHKIN

;        LDY #$04       ; skip 4 bytes on the first dir line
;        BNE @skip2
;      @next:
;        LDY #$02       ; skip 2 bytes on all other lines
;      @skip2:
;        JSR @getbyte    ; get a byte from dir and ignore it
;        DEY
;        BNE @skip2

;        JSR @getbyte    ; get low byte of basic line number
;        TAY
;        JSR @getbyte    ; get high byte of basic line number
      @char:
        ;jsr _cputc
        JSR @getbyte
        bcs @exit
        jsr @setbyte
        jmp @char

;        BNE @char      ; continue until end of line

;        LDA #$0D
;        jsr _cputc
;        lda #$0a
;        jsr _cputc
;        BNE @next      ; no RUN/STOP -> continue
      @error:
        ; Akkumulator contains BASIC error code

        ; most likely error:
        ; A = $05 (DEVICE NOT PRESENT)
      @exit:
        LDA #$02       ; filenumber 2
        JSR $FFC3      ; call CLOSE

        JSR $FFCC     ; call CLRCHN
        lda #$00
        ldy #$00
        RTS

      @getbyte:
        JSR $FFB7      ; call READST (read status byte)
        BNE @end       ; read error or end of file
        JMP $FFCF      ; call CHRIN (read byte from directory)
      @end:
        JMP @exit

      @dirname:
        .byte "$"      ; filename used to access directory

      @setbyte:
        sta $c000
        inc @setbyte + 1
        bne :+
        inc @setbyte + 2
      : rts
