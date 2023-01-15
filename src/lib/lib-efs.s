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


; ### implement conditional switches for non rom version


.feature c_comments
.localchar '@'

.include "lib-efs.i"
.include "../../version.txt"


.import __EFS_RAM_LOAD__
.import __EFS_RAM_RUN__
.import __EFS_RAM_SIZE__

.import __EFS_MINIEAPI_LOAD__
.import __EFS_MINIEAPI_RUN__
.import __EFS_MINIEAPI_SIZE__

.import backup_zeropage_data
.import backup_memory_config
.import status_byte
.import error_byte
.import efs_flags
.import internal_state
.import filename_address
.import filename_length
.import io_start_address
.import io_end_address

.import efs_io_byte
.import efs_generic_command
.import efs_bankin
.import efs_bankout
.import efs_enter_pha
.import efs_enter

.import rom_dirload_isrequested
.import rom_dirload_verify
.import rom_dirload_transfer
.import rom_dirload_address
.import rom_dirload_begin
.import rom_dirload_chrin

.export rom_chrout_body
.export rom_save_body
.export rom_chrin_body
.export rom_close_body
.export rom_open_body
.export rom_load_body
.export rom_setnam_body
.export rom_setlfs_body

.export restore_zeropage
.export backup_zeropage

.export efs_init_setstartbank
.export rom_config_get_value
.export rom_config_prepare_config


.segment "EFS_CALL"

; --------------------------------------------------------------------
; efs rom jump table
; 3 bytes jmp
; 10 byte magic & version
; 3 byte filler

    EFS_init: ; @ $8000
        ; parameter:
        ;    A: configuration
        ;    X/Y: relocation address
        ; return:
        ;    .C: 1 if error
        jmp efs_init_body

    EFS_init_eapi: ; @ $8003
        ; parameter: none
        ; return: .C set if eapi not present
        jmp efs_init_minieapi_body

    EFS_init_mini_eapi: ; @ $8006
        jmp efs_init_eapi_body

    EFS_init_XXX: ; @ $8009
        rts
        nop
        nop

    EFS_init_YYY: ; @ $800c
        rts
        nop
        nop

        .byte $00

    efs_magic: ; @ $8010
    efs_default_config:
        .byte "libefs"
        .byte major_version, minor_version, patch_version

        .byte $01
        .byte $00, $00, $a0, $d0, $ff  ; area 0: bank 0, $a000, mode lhlh, unlimited
        .byte $00, $00, $00, $00, $00  ; area 1: none
        .byte $00, $00, $00, $00, $00  ; area 2: none
        .byte $00, $00, $00            ; defragment: no
        .byte $00, $00, $00, $00  ; dummy

    efs_config_size = * - efs_default_config
    .if efs_config_size <> 32
    .error "efs config size mismatch"
    .endif

    efs_call_size = * - EFS_init
    .if efs_call_size <> 48
    .error "EFS_CALL size mismatch"
    .endif



.segment "EFS_ROM"

; --------------------------------------------------------------------
; efs: init and utility function bodies
; no zp usage

    backup_zeropage:
        ldx #ZEROPAGE_SIZE - 1  ; backup zp
    :   lda ZEROPAGE_BACKUP_END - ZEROPAGE_SIZE + 1, x
        sta backup_zeropage_data, x
        dex
        bpl :-
        rts

    restore_zeropage:
        ldx #ZEROPAGE_SIZE - 1  ; restore zp
    :   lda backup_zeropage_data, x
        sta ZEROPAGE_BACKUP_END - ZEROPAGE_SIZE + 1, x
        dex
        bpl :-
        rts


    efs_init_body:
        ; copy code to df00
        ldx #<__EFS_RAM_SIZE__ - 1
    :   lda __EFS_RAM_LOAD__,x
        sta __EFS_RAM_RUN__,x
        dex
        bpl :-
        clc

        clc
        rts


    efs_init_minieapi_body:
        ; copy code to df80
        ldx #<__EFS_MINIEAPI_SIZE__ - 1
    :   lda __EFS_MINIEAPI_LOAD__,x
        sta __EFS_MINIEAPI_RUN__,x
        dex
        bpl :-
        clc
        rts


    efs_init_eapi_body:
        tax

        lda #$65
        cmp $b800
        bne @error
        lda #$61
        cmp $b801
        bne @error
        lda #$70
        cmp $b802
        bne @error
        lda #$69
        cmp $b803
        bne @error

        lda $01
        sta backup_memory_config

        ldy #<(@codeend - @code - 1)
      : lda @code, y
        sta efs_generic_command, y
        dey
        bpl :-

        stx efs_generic_command + @dest  ; store high value

        ; copy blocks
        ldx #$00
      : lda EAPI_SOURCE + $0000, x
        jsr efs_generic_command
        inx
        bne :-

        inc efs_generic_command + @dest
        ldx #$00
      : lda EAPI_SOURCE + $0100, x
        jsr efs_generic_command
        inx
        bne :-

        inc efs_generic_command + @dest
        ldx #$00
      : lda EAPI_SOURCE + $0200, x
        jsr efs_generic_command
        inx
        bne :-
        dec efs_generic_command + @dest
        dec efs_generic_command + @dest

        ; init eapi
        lda #$20  ; jsr
        sta efs_generic_command + @dest - 2
        lda #$14  ; low
        sta efs_generic_command + @dest - 1
        jmp efs_generic_command  ; init eapi
        clc
        rts

      @error:
        sec
        rts

      @code:
        jsr efs_bankout
      @dest = * - @code + 2
        sta $c000, x
        jmp efs_enter_pha
      @codeend:
      .if (@codeend - @code) > GENERIC_COMMAND_SIZE
      .error "dynamic code initeapi to large"
      .endif


    efs_init_setstartbank:
        ldy #<(@codeend - @code - 1)
      : lda @code, y
        sta efs_generic_command, y
        dey
        bpl :-
        clc
        rts

       @code:
        jsr EAPISetBank
        jmp efs_enter_pha
       @codeend:
      .if (@codeend - @code) > GENERIC_COMMAND_SIZE
      .error "dynamic code setstartbank to large"
      .endif


    efs_init_readmem:
        ldy #<(@codeend - @code - 1)
      : lda @code, y
        sta efs_generic_command, y
        dey
        bpl :-
        clc
        rts

      @code:
        jsr efs_bankout
        lda ($3e), y  ; read from memory
        ldx #$37
        stx $01
        jmp efs_enter_pha
        ; bne #$04
      @codeend:
      .if (@codeend - @code) > GENERIC_COMMAND_SIZE
      .error "dynamic code readmem to large"
      .endif


    efs_init_readmem_ext:
        ldy #<(@codeend - @code - 1)
      : lda @code, y
        sta efs_generic_command, y
        dey
        bpl :-
        clc
        rts

      @code: ;
        jsr efs_bankout
        lda $ffff  ; read from memory
        ldx #$37
        stx $01
        bne * + 3
      @codeend:
      .if (@codeend - @code) > GENERIC_COMMAND_SIZE
      .error "dynamic code readmem_ext to large"
      .endif

    efs_readmem_ext = efs_generic_command
    efs_readmem_ext_low = efs_generic_command + 4
    efs_readmem_ext_high = efs_generic_command + 5


    efs_init_eapireadinc:
        lda #$20  ; jsr
        sta efs_io_byte
        lda #<EAPIReadFlashInc
        sta efs_io_byte + 1
        lda #>EAPIReadFlashInc
        sta efs_io_byte + 2
        rts


    efs_init_eapiwriteinc:
        lda #$20  ; jsr
        sta efs_io_byte
        lda #<EAPIWriteFlashInc
        sta efs_io_byte + 1
        lda #>EAPIWriteFlashInc
        sta efs_io_byte + 2
        rts


    efs_init_eapiwrite:
        lda #$20  ; jsr
        sta efs_io_byte
        lda #<EAPIWriteFlash
        sta efs_io_byte + 1
        lda #>EAPIWriteFlash
        sta efs_io_byte + 2
        rts


; --------------------------------------------------------------------
; efs body functions
; need to leave with 'jmp efs_bankout'
; zerpage usage only after zeropage backup

    rom_setlfs_body:
        pha  ; store logical number

        lda #$00  ; secondary address for relocation
        cpy #$00
        bne :+    ; zero => relocate
        lda #LIBEFS_FLAGS_RELOCATE
      : sta efs_flags

        pla  ; logical number
        cmp #$0f  ; command channel
        bne :+
        lda #LIBEFS_FLAGS_COMMAND
        ora efs_flags
        sta efs_flags

      : jmp efs_bankout  ; ends with rts


    rom_setnam_body:
        ; A: length; X/Y: name address (x low)
        sta filename_length
        stx filename_address
        sty filename_address + 1;
        clc  ; no error
        jmp efs_bankout  ; ends with rts


    rom_chrout_body:
        ; character in a
        ; ### no zeropage usage
        ; check if character may be written (file not open: $03, not output file: $07)
        ; write character
        ;jsr efs_write_byte
        sec
        lda #ERROR_DEVICE_NOT_PRESENT
        sta error_byte
        ; ### check if writing succeeded or failed
        ; .C set if error
        ; status set to $40 if device full
        jmp efs_bankout  ; ends with rts


    rom_chrin_body:
        ; no zeropage usage
        lda internal_state
        bne @next
        sec
        lda #ERROR_FILE_NOT_OPEN
        sta error_byte
        bne @done

      @next:
        lda status_byte    ; previous eof
        beq @fileop
        lda #$00
        sta error_byte
        sec
        beq @done

      @fileop:
        bit internal_state  ; we check for bit 7/6 == 1/0
        bpl @dirop  ; branch if bit 7 is clear
        bvs @dirop  ; branch if bit 6 is set
        jsr efs_io_byte  ; read file
        bcc @done
        lda #STATUS_EOF
        sta status_byte
        lda #$00
        beq @done

      @dirop:
        bit internal_state  ; we check for bit 7/6 == 1/0
        bmi @error  ; branch if bit 7 is set
        bvc @error  ; branch if bit 6 is clear

        jsr rom_dirload_chrin  ; read dir
        bcc @done
        lda #STATUS_EOF
        sta status_byte
        lda #$00
        beq @done

      @error:
        sec
        lda #ERROR_NO_INPUT_FILE
        sta error_byte
        lda #$00

      @done:
        jmp efs_bankout  ; ends with rts


    rom_open_body:
        ; no parameters, returns A, .C
        jsr backup_zeropage

        lda #$00         ; reset state and error
        sta status_byte
        sta error_byte

        lda internal_state  ; check if file open
        beq @commandcheck
        lda #ERROR_FILE_OPEN
        sta error_byte
        sec
        bne @leave

      @commandcheck:
        lda efs_flags
        and #LIBEFS_FLAGS_COMMAND  ; command channel
        beq @dircheck
        lda #%00100000  ; no processing
        sta internal_state
        jsr rom_command_begin
        bcs @leave
        jsr rom_command_process
        jmp @leave

      @dircheck:
        jsr rom_dirload_isrequested
        bcc @dirfind
        lda #%01000000  ; directory processing
        sta internal_state
        jsr rom_dirload_begin
        clc
        jmp @leave

      @dirfind:
        jsr efs_directory_search
        bcs @leave  ; not found
        lda #%10000000  ; file load processing
        sta internal_state
        jsr rom_fileload_begin
        clc

      @leave:
        php  ; save carry
        jsr restore_zeropage
        lda error_byte
        plp
        jmp efs_bankout  ; ends with rts


    rom_close_body:
        ; no zeropage
        clc
        lda #$00
        sta status_byte
        sta error_byte

        lda internal_state
        bne :+
        sec 
        lda #ERROR_FILE_NOT_OPEN
        sta error_byte

      : lda #$00
        sta internal_state

        lda error_byte
        jmp efs_bankout  ; ends with rts


    rom_load_body:
        ; return: X/Y: end address
        ; no internal state will be set
        ;sta efs_verify
        stx io_start_address
        sty io_start_address + 1
        cmp #$00
        beq :+    ; zero => no verify
        lda #LIBEFS_FLAGS_VERIFY
        ora efs_flags
        sta efs_flags

      : jsr backup_zeropage

        lda #$00
        sta status_byte
        sta error_byte

        lda internal_state
        beq @dircheck
        lda #ERROR_FILE_OPEN
        sta error_byte
        sec
        bne @leave

      @dircheck:
        jsr rom_dirload_isrequested
        bcc @fileload

      @dirload:
        lda efs_flags
        and #LIBEFS_FLAGS_VERIFY  ; set: verify, clear: load
        bne @dirloadverify

        jsr rom_dirload_begin
        jsr rom_dirload_address
        jsr rom_dirload_transfer
        jmp @leave

      @dirloadverify:
        jsr rom_dirload_verify
        jmp @leave

      @fileload:
        jsr efs_directory_search
        bcs @leave ; not found

        jsr rom_fileload_begin
        jsr rom_fileload_address

        lda efs_flags
        and #LIBEFS_FLAGS_VERIFY  ; set: verify, clear: load
        bne @fileloadverify
        
        jsr rom_fileload_transfer
        jmp @leave

      @fileloadverify:
;        lda libefs_configuration
;        and #LIBEFS_CONFIG_VERIFY  ;  verify possible
;        bne @verifyok
;        lda #ERROR_DEVICE_NOT_PRESENT
;        sta error_byte
;        sec
;        jmp @leave
;      @verifyok:
        jsr rom_fileload_verify

      @leave:
        php  ; save carry
        jsr restore_zeropage
        plp

        ldx io_end_address
        ldy io_end_address + 1
        lda error_byte

        jmp efs_bankout  ; ends with rts


    rom_save_body: ; ###
        ; A: address of zero page with startaddress; X/Y: end address + 1
        stx io_end_address
        sty io_end_address + 1
        tax
        lda $00, x
        sta io_start_address
        lda $01, x
        sta io_start_address + 1
        jsr backup_zeropage

        bit internal_state  ; we check for bit 7/6 == 1/1
        bpl @fileopen  ; branch if bit 7 is clear
        bvs @fileopen  ; branch if bit 6 is clear

        sec  ; ###
        lda #ERROR_DEVICE_NOT_PRESENT
        sta error_byte
        jmp @done

;        jsr rom_save_execute ###
;        jmp @done

      @fileopen:
        lda #ERROR_FILE_OPEN
        sta error_byte

      @done:
        php  ; save carry

        jsr restore_zeropage
        lda error_byte

        plp
        jmp efs_bankout  ; ends with rts



; --------------------------------------------------------------------
; ef read functions with manipulatable pointer

;.scope efs_readef

.export efs_init_readef
.export efs_readef
.export efs_readef_low
.export efs_readef_high
.export efs_readef_read_and_inc
.export efs_readef_pointer_inc
.export efs_readef_pointer_dec
.export efs_readef_pointer_advance
.export efs_readef_pointer_reverse

    efs_init_readef:
        ldy #<(@codeend - @code - 1)
      : lda @code, y
        sta efs_generic_command, y
        dey
        bpl :-
        clc
        rts

      @code: ; 12 bytes
        jsr EAPIGetBank
        sta EASYFLASH_BANK
        lda $8000  ; read from banked memory; byte 7, 8
        jmp efs_enter_pha
      @codeend:
      .if (@codeend - @code) > GENERIC_COMMAND_SIZE
      .error "dynamic code readef to large"
      .endif

    efs_readef = efs_generic_command
    efs_readef_low = efs_generic_command + 7
    efs_readef_high = efs_generic_command + 8

    efs_readef_read_and_inc:
        jsr efs_readef
        pha
        jsr efs_readef_pointer_inc
        pla  ; to have the correct cpu states
        rts

    efs_readef_pointer_inc:
        inc efs_readef_low
        bne :+
        inc efs_readef_high
      : ;lda efs_readef_high
        rts

    efs_readef_pointer_dec:
        lda efs_readef_low
        bne :+
        dec efs_readef_high
      : dec efs_readef_low
        rts

    efs_readef_pointer_advance:
        clc
        adc efs_readef_low
        sta efs_readef_low
        bcc :+
        inc efs_readef_high
      : ;lda efs_readef_high
        rts

    efs_readef_pointer_reverse:
        tax
        lda efs_readef_low
        stx efs_readef_low
        sec
        sbc efs_readef_low
        sta efs_readef_low
        bcs :+
        dec efs_readef_high
      : ;lda efs_readef_high
        rts

;.endscope



; --------------------------------------------------------------------
; efs config functions
; 35/36 temporary variable

    zp_pointer_configuration = $35 ; $36

    rom_config_get_value:
        ; config is stored in 35/36
        ; config address parameter in a
        pha  ; save a
        txa
        pha  ; save x
        tya
        pha  ; save y
 
        tsx
        lda $0103, x  ; a register
        tay
        lda (zp_pointer_configuration), y
        sta $0103, x  ; a register

        pla
        tay
        pla
        tax
        pla  ; it will pop the result
        rts


    rom_config_get_areastart:
        ; the value to get to area x
        ; only values 1, 2, 3 are allowed
        tay 
        dey
        lda #libefs_config::area_0
      : cli
        adc #.sizeof(libefs_area)
        dey
        bne :-
        rts


    rom_config_prepare_config:
        lda LIBEFS_CONFIG_START + 0
        cmp #$4c
        bne @default
        lda LIBEFS_CONFIG_START + 1
        cmp #$49
        bne @default
        lda LIBEFS_CONFIG_START + 2
        cmp #$42
        bne @default
        lda LIBEFS_CONFIG_START + 3
        cmp #$45
        bne @default
        lda LIBEFS_CONFIG_START + 4
        cmp #$46
        bne @default
        lda LIBEFS_CONFIG_START + 5
        cmp #$53
        bne @default

        lda #<LIBEFS_CONFIG_START
        sta zp_pointer_configuration
        lda #>LIBEFS_CONFIG_START
        sta zp_pointer_configuration + 1
        rts

      @default:
        lda #<efs_default_config
        sta zp_pointer_configuration
        lda #>efs_default_config
        sta zp_pointer_configuration + 1
        rts



; --------------------------------------------------------------------
; efs load and verify functions
; parameter:
;   38: bank
;   39/3a: offset in bank (with $8000 added)
;   3b/3c/fd: size
; using
;   37: temporary
;   3e/3f: pointer to data
; 
    rom_fileload_begin:
        jsr efs_init_eapireadinc  ; repair dynamic code

        ; directory entry
        ldx $39  ; efs_directory_entry + efs_directory::offset_low
        lda $3a  ; efs_directory_entry + efs_directory::offset_high
        clc
        adc #$80
        tay
        lda #$d0  ; eapi bank mode
        jsr EAPISetPtr

        ldx $3b  ; efs_directory_entry + efs_directory::size_low
        ldy $3c  ; efs_directory_entry + efs_directory::size_high
        lda $3d  ; efs_directory_entry + efs_directory::size_upper
        jsr EAPISetLen

        jsr efs_init_setstartbank
        lda $38  ; efs_directory_entry + efs_directory::bank
        jsr efs_generic_command

        rts


    rom_fileload_address:
        jsr efs_io_byte ; load address
        sta $3e
        jsr efs_io_byte
        sta $3f
        ;lda efs_secondary  ; 0=load to X/Y, 1=load to prg address
        lda #LIBEFS_FLAGS_RELOCATE
        bit efs_flags
        bne :+              ; set: load to X/Y, clear: no relocate
        jmp :++
      : lda io_start_address  ; load to relocation address (X/Y)
        sta $3e
        lda io_start_address + 1
        sta $3f

      : lda $3e
        sta io_start_address
        lda $3f
        sta io_start_address + 1

        rts


    rom_fileload_transfer:
;        ldy #$00
      @loop:
        jsr efs_io_byte
        bcs @eof
        ldy #$00
        sta ($3e), y
;        iny
;        bne @loop
;        inc $3f
;        jmp @loop
        inc $3e
        bne @loop
        inc $3f
        jmp @loop

      @eof:
        clc
        tya
        adc $3e
        sta $3e
        bcc :+
        inc $3f
      : lda $3e
        bne :+
        dec $3f
      : dec $3e
     
        lda #$40
        sta status_byte

        lda $3e
        sta io_end_address
        lda $3f
        sta io_end_address + 1

        clc
        rts


    rom_fileload_verify:
        jsr efs_init_readmem  ; prepare verify command
        ;ldy #$00
      @loop:
        jsr efs_io_byte
        bcs @eof  ; eof
        sta $37
        ldy #$00
        jsr efs_generic_command
        cmp $37
        bne @mismatch
;        iny
;        bne @loop
;        inc $3f
;        jmp @loop
        ;ldy #$00
        ;sta ($3e), y
        inc $3e
        bne @loop
        inc $3f
        jmp @loop

      @eof:
        lda #$40
        sta status_byte
        lda $3e  ; verify successful, reduce address by one
        bne :+
        dec $3f
      : dec $3e
        jmp @leave

      @mismatch:
        lda #$10
        sta status_byte
        
      @leave:
        clc
        tya
        adc $3e
        sta $3e
        bcc :+
        inc $3f

      : lda $3e
        sta io_end_address
        lda $3f
        sta io_end_address + 1

        lda status_byte
        and #$10
        bne :+
        clc
        rts
      : sec
        rts


; --------------------------------------------------------------------
; commands processing functions
; usage:
;  35/36: configuration pointer
;     37: used area
;     38: command
;  3e/3f: pointer to name
; return:

    rom_command_begin:
        lda filename_address
        sta zp_var_xe
        lda filename_address + 1
        sta zp_var_xf

        ldy #$00
        lda (zp_var_xe), y
        sta zp_var_x8

        ; check for ':'
        iny
        lda #$3a    ; ':'
        cmp (zp_var_xe), y
        beq @match

        ; check for a number: 0 < n <= x <= m < $ff
        lda (zp_var_xe), y    ; no fit
        clc
        adc #$ff - $30        ; lower bound $30
        adc #$39 - $30 + $01  ; upper bound $39
        bcc @nomatch          ; .C clear -> not in range

        ; check for ':'
        iny
        lda #$3a    ; ':'
        cmp (zp_var_xe), y
        beq @match

      @nomatch:
        lda #ERROR_SYNTAX_ERROR_30
        sta error_byte
        sec
        rts

      @match:
        ; advance filename pointer by y + 1
        sec  ; +1
        tya
        adc zp_var_xe
        sta zp_var_xe
        bne :+
        inc zp_var_xf
      : lda zp_var_xe
        sta filename_address
        lda zp_var_xf
        sta filename_address + 1

        iny ; decrease length by y + 1
      : dec filename_length
        dey
        bne :-

        clc
        rts


    rom_command_process:
        lda zp_var_x8

        cmp #$53    ; 'S'
        bne @nomatch
        ; scratch
        jsr efs_directory_search
        bcs @leave     ; not found
        jsr rom_scratch_process
        rts  ; error and .C set in rom_scratch_process

      @leave:
        rts
        
      @nomatch:
        lda #ERROR_SYNTAX_ERROR_31
        sta error_byte
        sec
        rts


    rom_scratch_process:
        ; configuration is at the correct area
        jsr efs_init_eapiwriteinc  ; prepare dynamic code

        ; filedata are set
        ; if in area 1 -> write protected
        lda zp_var_x7
        cmp #$01
        bne @scratch
        lda #ERROR_WRITE_PROTECTED
        sta error_byte
        bne @error

      @scratch:
        lda #16  ; advance pointer to flags
        jsr efs_readef_pointer_advance

        ; prepare bank
        jsr efs_init_setstartbank
        lda zp_var_x7
        jsr rom_config_get_areastart
        tay
        lda (zp_var_x5), y  ; at libefs_config::areax::bank
        jsr efs_generic_command

        iny                 ; banking mode
        iny
        iny
        lda (zp_var_x5), y  ; at libefs_config::areax::mode
        ldx efs_readef_low
        ldy efs_readef_high
        jsr EAPISetPtr

        ldx #$01
        lda #$00
        tay
        jsr EAPISetLen

        lda #$60
        sec  ; set to check for minieapi failures
        jsr efs_io_byte
        lda #ERROR_WRITE_ERROR
        bcs @error
        lda #ERROR_FILE_SCRATCHED

      @error:
        ; c flag set according to writeflash result
        sta error_byte
        rts


/*      @scratchcheck:
        jsr rom_scratch_isrequested
        bcc @dircheck
        lda #%0010000  ; no processing
        sta internal_state
        jsr efs_directory_search
        bcs @leave     ; not found
        jsr rom_scratch_begin  ; this finishes the operation
        jmp @leave

      ; ### check for disk drive commands
      ; "R0:..."  rename file ###
*/

/*    rom_scratch_isrequested:
        ; returns .C set if scratch requested 
        lda filename_address
        sta zp_var_xe
        lda filename_address + 1
        sta zp_var_xf

        ; check for letter S
        ldy #$00
        lda #$53    ; 'S'
        cmp (zp_var_xe), y
        bne @nomatch

        ; check for ':'
        iny
        lda #$3a    ; ':'
        cmp (zp_var_xe), y
        beq @match

        ; check for a number: 0 < n <= x <= m < $ff
        lda (zp_var_xe), y    ; no fit
        clc
        adc #$ff - $30        ; lower bound $30
        adc #$39 - $30 + $01  ; upper bound $39
        bcc @nomatch          ; .C clear -> not in range

        ; check for ':'
        iny
        lda #$3a    ; ':'
        cmp (zp_var_xe), y
        bne @nomatch

      @match:
        ; advance filename pointer by y + 1
        sec  ; +1
        tya
        adc zp_var_xe
        sta zp_var_xe
        bne :+
        inc zp_var_xf
      : lda zp_var_xe
        sta filename_address
        lda zp_var_xf
        sta filename_address + 1

        iny ; decrease length by y + 1
      : dec filename_length
        dey
        bne :-

        sec
        rts

      @nomatch:
        clc
        rts*/


/*    rom_dirsearch_address:
        ; set pointer and length of directory
        ; a offset in configuration
        sta dirsearch_temp_var_zp

        jsr rom_config_prepare_config

        jsr efs_init_setstartbank
        ;lda #$00  ; ### 0, could be different bank
        ldy dirsearch_temp_var_zp
        lda ($35), y  ; at libefs_config::libefs_area::bank
        jsr efs_generic_command

        ; set read ef code
        jsr efs_init_readef

        inc dirsearch_temp_var_zp
        ldy dirsearch_temp_var_zp
        lda ($35), y  ; at libefs_config::libefs_area::addr low
        sta efs_readef_low

        inc dirsearch_temp_var_zp
        ldy dirsearch_temp_var_zp
        lda ($35), y  ; at libefs_config::libefs_area::addr high
        sta efs_readef_high

        ; banking mode and area size is irrelevant in dirsearch
        rts*/


/*    rom_scratch_process:
        ; configuration is at the correct area
        jsr efs_init_eapiwriteinc  ; prepare dynamic code

        ; filedata are set
        ; if in area 1 -> write protected
        lda zp_var_x7
        cmp #$01
        bne @scratch
        lda #ERROR_WRITE_PROTECTED
        sta error_byte
        bne @error

      @scratch:
        lda #16  ; advance pointer to flags
        jsr efs_readef_pointer_advance

        ; prepare bank
        jsr efs_init_setstartbank
        lda zp_var_x7
        jsr rom_config_get_areastart
        tay
        lda (zp_var_x5), y  ; at libefs_config::areax::bank
        jsr efs_generic_command

        iny                 ; banking mode
        iny
        iny
        lda (zp_var_x5), y  ; at libefs_config::areax::mode
;        tax                 ; save mode in x

;        lda efs_readef_high  ; and address
;        cmp #$b0
;        bcc :+
;        clc
;        adc #$40
;      : tay
;        txa
        ldx efs_readef_low
        ldy efs_readef_high
        jsr EAPISetPtr

        ldx #$01
        lda #$00
        tay
        jsr EAPISetLen

        lda #$60
        sec  ; set to check for minieapi failures
        jsr efs_io_byte
        lda #ERROR_WRITE_ERROR
        bcs @error
        lda #ERROR_FILE_SCRATCHED

      @error:
        ; c flag set according to writeflash result
        sta error_byte
        rts*/
        


; --------------------------------------------------------------------
; directory search functions
; usage:
;   35/36: pointer to configuration
;   37: name check result
;   3e/3f: pointer to name
; return:
;   37: area
;   38: bank
;   39/3a: offset in bank (with $8000 added)
;   3b/3c/3d: size
;   read_ef: pointer is at begin of directory entry

;    dir_read_byte_low = efs_io_byte + 1
;    dir_read_byte_high = efs_io_byte + 2

    dirsearch_area_var_zp := $37
    dirsearch_temp_var_zp := $38
    dirsearch_name_pointer_zp := $3e
    dirsearch_entry_zp := $3b

    efs_directory_search:
        lda filename_address
        sta dirsearch_name_pointer_zp
        lda filename_address + 1
        sta dirsearch_name_pointer_zp + 1

        jsr rom_config_prepare_config
        lda #libefs_config::areas
        jsr rom_config_get_value
        cmp #$03
        beq :+

        ; read only efs
        lda #$01
        sta dirsearch_area_var_zp
        lda #libefs_config::area_0
        jsr rom_dirsearch_begin
        jsr rom_dirsearch_find
        bcc @found
        sec
        rts
        
        ; rw efs
      : lda #$01
        sta dirsearch_area_var_zp
        lda #libefs_config::area_0
        jsr rom_dirsearch_begin
        jsr rom_dirsearch_find
        bcc @found
        lda #$02
        sta dirsearch_area_var_zp
        lda #libefs_config::area_1
        jsr rom_dirsearch_begin
        jsr rom_dirsearch_find
        bcc @found
        lda #$03
        sta dirsearch_area_var_zp
        lda #libefs_config::area_2
        jsr rom_dirsearch_begin
        jsr rom_dirsearch_find
        sec
        rts

       @found:
        jsr rom_dirsearch_filedata
        rts


    efs_directory_empty:
        ; find next empty directory entry
        ; ###
        rts


    rom_dirsearch_filedata:
        ; position is at flags, bank is the next data to load
        ; all zp variables are free and can be used
        jsr efs_readef_read_and_inc  ; efs_io_byte  ; bank
        sta $38
        jsr efs_readef_read_and_inc  ; efs_io_byte  ; bank high

        ; offset
        jsr efs_readef_read_and_inc  ; efs_io_byte
        sta $39
        jsr efs_readef_read_and_inc  ; efs_io_byte
        ; memory offset will be added later
        sta $3a

        ; size
        jsr efs_readef_read_and_inc  ; efs_io_byte
        sta $3b
        jsr efs_readef_read_and_inc  ; efs_io_byte
        sta $3c
        jsr efs_readef_read_and_inc  ; efs_io_byte
        sta $3d

        ; reverse to flag
        lda #24  ; reverse pointer to name
        jsr efs_readef_pointer_reverse
        clc

        rts


    rom_dirsearch_begin:
        ; set pointer and length of directory
        ; a offset in configuration
        sta dirsearch_temp_var_zp

        jsr rom_config_prepare_config

        jsr efs_init_setstartbank
        ;lda #$00  ; ### 0, could be different bank
        ldy dirsearch_temp_var_zp
        lda ($35), y  ; at libefs_config::libefs_area::bank
        jsr efs_generic_command

        ; set read ef code
        jsr efs_init_readef

        inc dirsearch_temp_var_zp
        ldy dirsearch_temp_var_zp
        lda ($35), y  ; at libefs_config::libefs_area::addr low
        sta efs_readef_low

        inc dirsearch_temp_var_zp
        ldy dirsearch_temp_var_zp
        lda ($35), y  ; at libefs_config::libefs_area::addr high
        sta efs_readef_high

        ; banking mode and area size is irrelevant in dirsearch
        rts


    rom_dirsearch_checkname:
        ; compare filename
        ; name is in (fe/ff)
        ldy #$00
        ldx #$00
      @loop:
        jsr efs_readef_read_and_inc  ; load next char
        sta dirsearch_entry_zp
        inx
        
        lda #$2a             ; '*'
        cmp (dirsearch_name_pointer_zp), y  ; character in name is '*', we have a match
        beq @match
        lda #$3f             ; '?'
        cmp (dirsearch_name_pointer_zp), y  ; character in name is '?', the char fits
        beq @fit
        lda (dirsearch_name_pointer_zp), y  ; compare character with character in entry
        cmp dirsearch_entry_zp  ; if not equal nextname
        bne @next
      @fit:
        iny
        cpy filename_length  ; name length check
        bne @loop            ; more characters
        cpy #$10             ; full name length reached
        beq @match           ;   -> match
        jsr efs_readef_read_and_inc  ; load next char
        sta dirsearch_entry_zp
        inx
        lda dirsearch_entry_zp  ; if == \0
        beq @match           ;   -> match
                             ; length check failed
      @next:
        cpx #$10
        beq :+
        jsr efs_readef_read_and_inc  ; load next char
        inx
        bne @next
      : lda #$00
        sta dirsearch_temp_var_zp
        rts

      @match:
        cpx #$10
        beq :+
        jsr efs_readef_read_and_inc  ; load next char
        inx
        bne @match
      : lda #$01
        sta dirsearch_temp_var_zp
        rts


    rom_dirsearch_checkboundary:
        ; check if directory cursor is out of bounds
        ; .C set if out of bounds
        lda efs_readef_high
        cmp #$b8        
        rts

    rom_dirsearch_is_terminator:
        ; A: value
        ; returns C set if current entry is empty (terminator)
        ; returns C clear if there are more entries
        ; uses A, status
        ; must not use X
        and #$1f
        cmp #$1f
        beq :+
        clc  ; in use or deleted
        rts
    :   sec  ; empty
        rts


    rom_dirsearch_find:
;        lda filename_address
;        sta dirsearch_name_pointer_zp
;        lda filename_address + 1
;        sta dirsearch_name_pointer_zp + 1
;        jsr rom_dirsearch_begin_search

        lda filename_length
        bne @repeat
        lda #ERROR_MISSING_FILENAME  ; no filename: status=0, error=8, C
        bne @error      ; jmp to error

      @repeat:
        ; checkname
        jsr rom_dirsearch_checkname

        ; test if more entries
        jsr efs_readef_read_and_inc  ; efs_io_byte    ; load next char
        jsr rom_dirsearch_is_terminator
        bcs @error4    ; terminator, file not found
        cmp #$00       ; compare for invalid
        beq @nomatch   ; file not valid
        jsr rom_dirsearch_checkboundary
        bcs @error4    ; over bounds, file not found
        jmp @next
      @error4:
        lda #ERROR_FILE_NOT_FOUND  ; file not found: status=0, C
      @error:
        sta error_byte
        sec
        rts

      @next:
        ; no test if hidden
;        and #%00011111  ; mask out hidden and reserved flag fields
;        beq :+          ; file invalid
        lda dirsearch_temp_var_zp
        bne @match
      @nomatch:
        lda #$07
        jsr efs_readef_pointer_advance
        jmp @repeat

      @match:
        ; found, read file info
        ;jsr rom_dirsearch_filedata
        lda #$00
        sta error_byte
        clc
        rts



; ------------------------------------------------------------------------
; attic

/*
        pla  ; low
        sta $fe
        tax
        clc
        adc #<rel_verify_byte_offset
        sta efs_verify_byte + 1
        lda #$00
        adc #>rel_verify_byte_offset
        sta efs_verify_byte + 2

        txa
        clc
        adc #<rel_write_byte_offset
        sta efs_write_byte + 1
        lda #$00
        adc #>rel_write_byte_offset
        sta efs_write_byte + 2

        pla  ; high
        sta $ff
        tax
        clc
        adc #>rel_verify_byte_offset
        sta efs_verify_byte + 2

        txa
        clc
        adc #>rel_write_byte_offset
        sta efs_write_byte + 2

        beq :+
        ; copy code to X/Y
        ldy #<__EFS_REL_SIZE__ - 1
      : lda __EFS_REL_LOAD__, y
        sta ($fe), y
        dey
        bpl :-
*/

/*
      morefiles:
        ; check if deleted
        ; check if hidden or other wrong type
        ; we only allow prg ($01, $02, $03)
        jsr efs_read_byte    ; load next char
;        lda efs_dirsearch_entry + efs_directory::flags
        beq nextname    ; if deleted go directly to next name

        ; compare filename
        ldy #$00
      nameloop:
        lda #$2a   ; '*'
        cmp ($fe), y  ; character in name is '*', we have a match
        beq namematch
        lda ($fe), y  ; compare character with character in entry
        cmp efs_dirsearch_entry, y     ; if not equal nextname
        bne nextname
        iny
        cpy filename_length        ; name length check
        bne nameloop               ; more characters
        cpy #$10                   ; full name length reached
        beq namematch              ;   -> match
        lda efs_dirsearch_entry, y     ; character after length is zero
        beq namematch              ;   -> match
        jmp nextname               ; length check failed

      namematch:
        clc
        rts
*/

