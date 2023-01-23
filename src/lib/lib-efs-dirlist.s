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
.localchar '@'

.include "lib-efs.i"


.import error_byte
.import status_byte
.import filename_address
.import io_start_address
.import io_end_address
.import efs_flags
.import efs_generic_command
.import internal_state

.import restore_zeropage
.import backup_zeropage

.import efs_init_readef
.import efs_init_readef_rely
.import efs_readef
.import efs_readef_low
.import efs_readef_high
.import efs_readef_bank
.import efs_readef_read_and_inc
.import efs_readef_pointer_inc
.import efs_readef_pointer_dec
.import efs_readef_pointer_advance
.import efs_readef_pointer_reverse
.import efs_readef_pointer_setall
.import efs_readef_pointer_set

;.import efs_init_readef
;.import efs_readef_pointer_reverse
;.import efs_readef_pointer_dec
;.import efs_readef_read_and_inc
;.import efs_readef_pointer_advance
;.import efs_readef
;.import efs_readef_high
;.import efs_readef_low

.import efs_setstartbank_ext

.import rom_config_get_value
.import rom_config_prepare_config

.export rom_dirload_isrequested
.export rom_dirload_verify
.export rom_dirload_transfer
.export rom_dirload_address
.export rom_dirload_begin
.export rom_dirload_chrin


.segment "EFS_ROM"

; --------------------------------------------------------------------
; directory list functions
; usage:
;   35/36: configuration
;   37: temporary state machine state
;   38/39: temporary file size
;   3a: temporary variable
;   3b: 
;   3c/3d: address to state maching processing function
;   3e/3f: pointer to destination / pointer to filename
;   io_end_address: state machine variable
;   io_end_address + 1: state machine variable

    dirload_area_var := io_end_address
    dirload_state_var := io_end_address + 1
    dirload_temp_var_zp := zp_var_xa
    dirload_temp_state_zp := zp_var_x7

    rom_dirload_isrequested:
        lda filename_address
        sta zp_var_xe
        lda filename_address + 1
        sta zp_var_xf

        ldy #$00
        lda #$24        ; '$'
        cmp (zp_var_xe), y     ; no fit
        bne :+

        sec
        rts
      : clc
        rts


    rom_dirload_begin:
        lda #$00
        sta dirload_area_var
        jsr efs_dirload_nextarea

        lda internal_state
        and #$c0
        ora #$01
        sta internal_state
        lda #$01
        sta dirload_temp_state_zp
        lda #$00
        sta dirload_state_var
        rts


    efs_dirload_nextarea:
        ; prepares the data for the next area
        ; dirload_area_var contains current area
        ; returns .C set if there us no next
        ; dirload_area_var contains the next area
        jsr rom_config_prepare_config

        ; area 0: read only efs
        lda dirload_area_var
        bne @area1  ; current area 0 -> list 1
        lda #libefs_config::area_0
        jsr rom_dirload_prepare
        jmp @cont

        ; ### only look into active area
      @area1:
        lda #libefs_config::areas
        jsr rom_config_get_value
        cmp #$03
        bne @done
        lda dirload_area_var
        cmp #$01
        bne @area2  ; current area 1; != list 2
        lda #libefs_config::area_1
        jsr rom_dirload_prepare
        jmp @cont

      @area2:
        lda dirload_area_var
        cmp #$02
        bne @done  ; current area 2; != list 3
        lda #libefs_config::area_2
        jsr rom_dirload_prepare

      @cont:
        inc dirload_area_var
        clc
        rts

      @done:
        sec
        rts


    rom_dirload_prepare:
        ; set pointer and length of directory
        ; a offset in configuration
        sta dirload_temp_var_zp

        ; set read ef code
        jsr efs_init_readef

;        jsr efs_init_setstartbank
        ldy dirload_temp_var_zp
        lda (zp_var_x5), y  ; at libefs_config::libefs_area::bank
;        jsr efs_generic_command
        jsr efs_setstartbank_ext
        sta efs_readef_bank

;        ; set read ef code
;        jsr efs_init_readef_bank

        inc dirload_temp_var_zp
        ldy dirload_temp_var_zp
        lda (zp_var_x5), y  ; at libefs_config::libefs_area::addr low
        sta efs_readef_low

        inc dirload_temp_var_zp
        ldy dirload_temp_var_zp
        lda (zp_var_x5), y  ; at libefs_config::libefs_area::addr high
        sta efs_readef_high

        ; banking mode and size is irrelevant in dirload
;        inc dirload_temp_var_zp
;        inc dirload_temp_var_zp
;        ldy dirload_temp_var_zp
;        lda ($35), y  ; at libefs_config::libefs_area::size
;        tay
;        dey
        ;sty ### 
        rts


    rom_dirload_address:
        lda #$01
        sta zp_var_xe
        lda #$04
        sta zp_var_xf
        lda #LIBEFS_FLAGS_RELOCATE
        bit efs_flags
        bne :+              ; set: load to X/Y, clear: no relocate
        jmp :++
      : lda io_start_address  ; load to relocation address (X/Y)
        sta zp_var_xe
        lda io_start_address + 1
        sta zp_var_xf

      : lda zp_var_xe
        sta io_start_address
        lda zp_var_xf
        sta io_start_address + 1

        rts


    rom_dirload_chrin:
        jsr backup_zeropage
        lda internal_state
        and #$3f  ; remove the upper bits
        sta dirload_temp_state_zp
      @again:
        jsr rom_dirload_next_byte
        tay
        lda internal_state
        and #$c0    ; only take the upper bits
        ora dirload_temp_state_zp  ; or the state
        sta internal_state
        lda dirload_temp_state_zp  ; check if state is zero
        beq @eof    ; state 0 means end
        bcs @again  ; C set, skip writing and repeat
        jsr restore_zeropage
        tya
        clc
        rts
      @eof:
        jsr restore_zeropage
        tya
        sec
        rts


    rom_dirload_transfer:
        jsr rom_dirload_next_byte  ; skip load address
        jsr rom_dirload_next_byte

        ldy #$00
      @loop:
        jsr rom_dirload_next_byte
        ldx dirload_temp_state_zp
        beq @eof   ; state 0 means end
        bcs @loop  ; C set, skip writing and repeat
        ldy #$00
        sta (zp_var_xe), y
        inc zp_var_xe
        bne @loop
        inc zp_var_xf
        jmp @loop

      @eof:
        clc
        tya
        adc zp_var_xe
        sta zp_var_xe
        bcc :+
        inc zp_var_xf
      : lda zp_var_xe
        bne :+
        dec zp_var_xf
      : dec zp_var_xe

        lda #$40
        sta status_byte
        lda #$00
        sta internal_state  ; must be reset here

        lda zp_var_xe
        sta io_end_address
        lda zp_var_xf
        sta io_end_address + 1

        clc
        rts


    rom_dirload_verify:
        ; dirload verify not supported -> device not present error
        lda #ERROR_DEVICE_NOT_PRESENT
        sta error_byte
        lda #$00
        sta io_end_address
        sta io_end_address + 1
        sec
        rts


    rom_dirload_next_byte:
        lda dirload_temp_state_zp
        asl
        tax
        lda rom_dirload_statemachine, x
        sta zp_var_xc
        lda rom_dirload_statemachine + 1, x
        sta zp_var_xd
        clc
        jmp ($0000 + zp_var_xc)

    rom_dirload_statemachine:
        .addr rom_dirload_sm_finish        ; 0
        .addr rom_dirload_sm_addresslow    ; 1
        .addr rom_dirload_sm_addresshigh   ; 2
        .addr rom_dirload_sm_addrdummy     ; 3
        .addr rom_dirload_sm_addrdummy     ; 4
        .addr rom_dirload_sm_zero          ; 5
        .addr rom_dirload_sm_zero          ; 6
        .addr rom_dirload_sm_reverseon     ; 7
        .addr rom_dirload_sm_quotationmark ; 8
        .addr rom_dirload_sm_diskname      ; 9
        .addr rom_dirload_sm_quotationmark ; 10
        .addr rom_dirload_sm_space         ; 11
        .addr rom_dirload_sm_space         ; 12
        .addr rom_dirload_sm_space         ; 13
        .addr rom_dirload_sm_space         ; 14
        .addr rom_dirload_sm_space         ; 15
        .addr rom_dirload_sm_space         ; 16
        .addr rom_dirload_sm_space         ; 17
        .addr rom_dirload_sm_linenend      ; 18

        sm_finish = 19
        .addr rom_dirload_sm_addrdummy     ; 19
        .addr rom_dirload_sm_addrdummy     ; 20
        .addr rom_dirload_sm_freelow       ; 21
        .addr rom_dirload_sm_freehigh      ; 22
        .addr rom_dirload_sm_blocksfree    ; 23
        .addr rom_dirload_sm_zero          ; 24
        .addr rom_dirload_sm_zero          ; 25
        .addr rom_dirload_sm_zero          ; 26
        .addr rom_dirload_sm_finish        ; 27

        sm_nextfile = 28
        .addr rom_dirload_sm_addrdummy     ; 28
        .addr rom_dirload_sm_addrdummy     ; 29
        .addr rom_dirload_sm_sizelow       ; 30
        .addr rom_dirload_sm_sizehigh      ; 31
        .addr rom_dirload_sm_sizeskip      ; 32
        .addr rom_dirload_sm_quotationmark ; 33
        .addr rom_dirload_sm_filename      ; 34
        .addr rom_dirload_sm_quotationmark ; 35
        .addr rom_dirload_sm_filenamefill  ; 36
        .addr rom_dirload_sm_type_begin    ; 37
        .addr rom_dirload_sm_type_next     ; 38
        .addr rom_dirload_sm_type_next     ; 39
        .addr rom_dirload_sm_type_next     ; 40
        .addr rom_dirload_sm_writeprot     ; 41
        .addr rom_dirload_sm_space         ; 42
        .addr rom_dirload_sm_space         ; 43
        .addr rom_dirload_sm_linenend      ; 44


    rom_dirload_diskname_text:
        .byte "easyflash fs    "  ; length 16
        rom_dirload_diskname_textlen = * - rom_dirload_diskname_text - 1

    rom_dirload_blocksfree_text:
        .byte "blocks free.             "
        rom_dirload_blocksfree_textlen = * - rom_dirload_blocksfree_text - 1

    rom_dirload_types_text:
        ; set type: prg, crt, oce, xba; < for low; > for high, +/* for ultimax
        .byte " prg"
        .byte "-prg"
        .byte "+prg"
        .byte "-crt"
        .byte " crt"
        .byte "+crt"
        .byte "*crt"
        .byte "+ocn"
        .byte "-ocn"
        .byte " xba"
        .byte " xba"
        .byte " xba"


    rom_dirload_sm_writeprot:
        ; if in device 0 area, always write protected
        lda dirload_area_var
        cmp #$01
        beq :+    ; read only
        lda #$20
        bne :++
      : lda #$3c  ; '<'
      : inc dirload_temp_state_zp
        clc
        rts

    rom_dirload_sm_finish:
        ; finish does not produce a byte
        lda #$00
        sta dirload_temp_state_zp
        clc
        rts

    rom_dirload_sm_skip:
        lda #$00
        sta dirload_state_var
        inc dirload_temp_state_zp
        sec
        rts

    rom_dirload_sm_space:
        lda #$20
        inc dirload_temp_state_zp
        rts

    rom_dirload_checkboundary:
        ; check if directory cursor is out of bounds
        ; .C set if out of bounds
        ; ### correct boundary configuration
        lda efs_readef_high
        cmp #$b8
        rts

    rom_dirload_sm_linenend:
        ; produces $00 and decides if new filename
        ; if filename -> 20
        ; if finish -> 15
        lda #16  ; pointer starts at begin of dir entry
        jsr efs_readef_pointer_advance
        jsr rom_dirload_checkboundary
        bcs @areadone   ; directory terminates
        jsr efs_readef  ; read flag
        sta dirload_temp_var_zp
        and #%00011111  ; mask out hidden and reserved flag fields
        bne @notinvalid  ; is file invalid -> no
      @invalid:
        lda #8  ; -> yes, invalid
        jsr efs_readef_pointer_advance
        jmp rom_dirload_sm_linenend

      @notinvalid:
        cmp #$1f
        beq @areadone  ; terminator -> area done
        bit dirload_temp_var_zp
        bmi @invalid   ; hidden -> invalid
        jmp @nextfile  ; nextfile
      @areadone:  ; directory area is done, check next
        jsr efs_dirload_nextarea
        bcc rom_dirload_sm_linenend  ; more areas -> repeat
        lda #sm_finish  ; no further areas finish directory
        sta dirload_temp_state_zp
        lda #$00
        clc
        rts

      @nextfile:
        lda #sm_nextfile  ; go to file line
        sta dirload_temp_state_zp
        lda #$00
        clc
        rts

/*    rom_dirload_sm_devlow:
        lda efs_device
        and #$0f
        clc
        adc #$30 
        cmp #$3a
        bmi :+    ; if > 9 
        clc
        adc #$07  ; add 7 for a-f
      : inc dirload_temp_state_zp
        rts

    rom_dirload_sm_devhigh:
        lda efs_device
        lsr
        lsr
        lsr
        lsr
        clc
        adc #$30
        cmp #$3a
        bmi :+    ; if > 9
        clc
        adc #$07  ; add 7 for a-f
      : inc dirload_temp_state_zp
        rts*/


    rom_dirload_sm_addresslow:
        lda io_start_address
        inc dirload_temp_state_zp
        rts

    rom_dirload_sm_addresshigh:
        lda io_start_address + 1
        inc dirload_temp_state_zp
        rts

    rom_dirload_sm_addrdummy:
        lda #$00
        sta dirload_state_var
        lda #$01
        inc dirload_temp_state_zp
        rts

    rom_dirload_sm_zero:
        lda #$00
        inc dirload_temp_state_zp
        rts

    rom_dirload_sm_reverseon:
        lda #$12
        inc dirload_temp_state_zp
        rts

    rom_dirload_sm_quotationmark:
        ;lda #$00
        ;sta dirload_state_var
        lda #$22
        inc dirload_temp_state_zp
        rts

    rom_dirload_sm_diskname:
        ldx dirload_state_var
        lda rom_dirload_diskname_text, x
        inc dirload_state_var
        cpx #rom_dirload_diskname_textlen
        bne :+
        inc dirload_temp_state_zp
        ldx #$00
        stx dirload_state_var
      : clc
        rts

    rom_dirload_sm_blocksfree:
        ldx dirload_state_var
        lda rom_dirload_blocksfree_text, x
        inc dirload_state_var
        cpx #rom_dirload_blocksfree_textlen
        bne :+
        inc dirload_temp_state_zp
        ldx #$00
        stx dirload_state_var
      : clc
        rts

    rom_dirload_sm_filename:
        ; pointer is at the name
        ldx dirload_state_var
        jsr efs_readef
        beq @nullchar
        jsr efs_readef_pointer_inc
        inc dirload_state_var
        cpx #15
        clc
        beq @finish
        rts
      @nullchar:
        sec
      @finish:
        inc dirload_temp_state_zp ; name finished
        rts

;        lda #$20  ; space if 0 char
;      : inc dirload_state_var
;        cpx #15
;        bne :+
;        inc dirload_temp_state_zp
;        ldx #$00
;        stx dirload_state_var
        
      : clc
        rts

    rom_dirload_sm_filenamefill:
        ldx dirload_state_var
        cpx #16
        beq @finish
        jsr efs_readef_read_and_inc
        inc dirload_state_var
        lda #$20  ; (space)
        clc
        rts
      @finish:
        inc dirload_temp_state_zp
        lda #$20  ; (space)
        sec
        rts


    rom_dirload_sm_sizelow:
        ; pointer is at flags
        lda #5  ; advance to size low
        jsr efs_readef_pointer_advance
        jsr efs_readef_read_and_inc  ; size low
        beq :+
        lda #$01
      : sta zp_var_x8  ; a is 0 after branch
        jsr efs_readef  ; read mid
        clc
        adc zp_var_x8
        inc dirload_temp_state_zp
        rts


    rom_compare16:
        ; A: high value
        ; X: low value
        ; val1(X/A) >= Val2(f8/f9) => C set
        ; https://codebase64.org/doku.php?id=base:16-bit_comparison
        ; a            ; Val1 high
        cmp zp_var_x9        ; Val2 high
        bcc @LsThan    ; hiVal1 < hiVal2 --> Val1 < Val2
        bne @GrtEqu    ; hiVal1 != hiVal2 --> Val1 > Val2
        txa            ; Val1 low
        cmp zp_var_x8        ; Val2 low
        ;beq Equal     ; Val1 = Val2
        bcs @GrtEqu    ; loVal1 >= loVal2 --> Val1 >= Val2
      @LsThan:
        sec
        rts
      @GrtEqu:
        clc
        rts

    rom_dirload_sm_sizehigh:
        ; pointer is at size mid
        jsr efs_readef_pointer_dec
        jsr efs_readef_read_and_inc  ;low
        beq :+
        lda #$01
      : sta zp_var_x8  ; a is zero iafter branch
        jsr efs_readef_read_and_inc  ;mid
        clc
        adc zp_var_x8
        sta zp_var_x8
        lda #$00
        sta zp_var_x9
        jsr efs_readef ; high
        adc zp_var_x9
        sta zp_var_x9

        inc dirload_temp_state_zp
        lda #23  ; reverse pointer to name
        jsr efs_readef_pointer_reverse

        lda #$00
        ldx #$09
        jsr rom_compare16
        bcs :+     ; 10 >= f8/f9 ($0009)
        lda #$03   ; print 3 spaces
        sta dirload_state_var
        jmp @done

      : lda #$00
        ldx #$63
        jsr rom_compare16
        bcs :+     ; 100 >= f8/f9 ($0063)
        lda #$02   ; print 2 spaces
        sta dirload_state_var
        jmp @done

      : lda #$03
        ldx #$e7
        jsr rom_compare16
        bcs :+     ; 1000 >= f8/f9 ($03e7)
        lda #$01   ; print 1 spaces
        sta dirload_state_var
        jmp @done

      : lda #$00   ; print 0 spaces
        sta dirload_state_var

        ; size in blocks is in f8/f9
        ; calculate how many spaces to skip (0, 1, 2 ,3)
        ; 9    -> $0009
        ; 99   -> $0063
        ; 999  -> $03e7
        ; 9999 -> $270f
        ; https://codebase64.org/doku.php?id=base:16-bit_absolute_comparison

      @done:
        lda zp_var_x9
        clc
        rts


    rom_dirload_sm_sizeskip:
        lda dirload_state_var
        bne :+
        inc dirload_temp_state_zp
        sec
        rts
      : lda #$20
        dec dirload_state_var
        clc
        rts


    rom_dirload_sm_type_begin:
        ; pointer is at flags
        jsr efs_readef
        and #$1f
        cmp #$09
        bcc :+
        sbc #$09 - $03  ; reduce by reserved values ($04 - $0f)
      : sec
        sbc #$01
        asl a
        asl a
        sta dirload_state_var

        lda #8  ; advance pointer to begin of next name
        jsr efs_readef_pointer_advance
        ; no return here

    rom_dirload_sm_type_next:
        lda dirload_state_var
        inc dirload_state_var
        tax
        lda rom_dirload_types_text, x
        inc dirload_temp_state_zp
        clc
        rts


    rom_dirload_sm_freelow:
        ; calculate the free blocks
        ; ### other area  
        ; in area 0 nothing free
        ; ### calculate free blocks in current area
        lda #$00
        sta dirload_state_var
        inc dirload_temp_state_zp
        clc
        rts

    rom_dirload_sm_freehigh:
        lda dirload_state_var
        inc dirload_temp_state_zp
        clc
        rts

