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

;.export efs_init_setstartbank
.export efs_setstartbank_ext

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

    EFS_defragment: ; @ $8009
        ; validates (defragments) the rw area
        jmp efs_defragment_body

    EFS_format: ; @ $800c
        ; initializes (erases) the rw area
        jmp efs_format_body

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


/*    efs_init_setstartbank:
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
      .endif*/


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

    efs_readmem = efs_generic_command


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

    efs_init_eapierasesector:
        lda #$20  ; jsr
        sta efs_io_byte
        lda #<EAPIEraseSector
        sta efs_io_byte + 1
        lda #>EAPIEraseSector
        sta efs_io_byte + 2
        rts


    efs_setstartbank_ext:
        ; jsr EAPISetBank  :  $20, <EAPISetBank, >EAPISetBank
        ; jmp efs_enter_pha : $4c, <efs_enter_pha, >efs_enter_pha
        efs_bankout_source := __EFS_RAM_LOAD__ + (efs_bankout - __EFS_RAM_RUN__)
        pha
        lda #$20
        sta efs_bankout + 0
        lda #<EAPISetBank
        sta efs_bankout + 1
        lda #>EAPISetBank
        sta efs_bankout + 2
        lda #$4c
        sta efs_bankout + 3
        lda #<efs_enter_pha
        sta efs_bankout + 4
        lda #>efs_enter_pha
        sta efs_bankout + 5
        pla

        jsr efs_bankout
        pha
        lda efs_bankout_source + 0
        sta efs_bankout + 0
        lda efs_bankout_source + 1
        sta efs_bankout + 1
        lda efs_bankout_source + 2
        sta efs_bankout + 2
        lda efs_bankout_source + 3
        sta efs_bankout + 3
        lda efs_bankout_source + 4
        sta efs_bankout + 4
        lda efs_bankout_source + 5
        sta efs_bankout + 5
        pla
        rts


    efs_temp_var1 := status_byte - 1
    efs_temp_var2 := status_byte + 1

    efs_finish_tempvars:
        lda #$a9
        sta status_byte - 1
        lda #$60
        sta status_byte + 1
        rts


; --------------------------------------------------------------------
; efs body functions
; need to leave with 'jmp efs_bankout'
; zeropage usage only after zeropage backup

    efs_defragment_body:
        jsr rom_config_prepare_config

        ; rw areas available?
        jsr rom_config_rw_available
        bcs @error

        lda internal_state  ; check if file open
        beq @process
        lda #ERROR_FILE_OPEN
        bne @error

      @process:
        jsr rom_flags_get_area
        tax
        jsr rom_flags_get_area_invert
        tay
        jsr rom_defragment_copy

        jsr rom_flags_get_area
        jsr rom_defragment_erasearea

        rts

      @error:
        sec
        rts


    efs_format_body:
        jsr rom_config_prepare_config

        ; rw areas available?
        jsr rom_config_rw_available
        bcs @error

        lda #$01
        jsr rom_defragment_erasearea
        bcs @error
        lda #$02
        jsr rom_defragment_erasearea
        rts
      @error:
        rts


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
        jsr rom_fileload_verify

      @leave:
        php  ; save carry
        jsr restore_zeropage
        plp

        ldx io_end_address
        ldy io_end_address + 1
        lda error_byte

        jmp efs_bankout  ; ends with rts


    rom_save_body:
        ; A: address of zero page with startaddress; X/Y: end address + 1
        stx io_end_address
        sty io_end_address + 1
        tax
        lda $00, x
        sta io_start_address
        lda $01, x
        sta io_start_address + 1

        jsr backup_zeropage

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
        bcc @checkname
        lda #ERROR_MISSING_FILENAME
        sta error_byte
        sec
        bne @leave

      @checkname:
        jsr rom_filesave_conditions
        bcs @leave
        jsr efs_directory_search
        bcs @savefile ; not found
        jsr rom_scratch_process
        bcs @leave
;        lda #ERROR_FILE_EXISTS  ; ### delete instead?
;        sta error_byte
;        sec
;        bne @leave

      @savefile:
        lda #$00
        sta error_byte
        jsr rom_filesave_begin
        jsr rom_filesave_transfer_dir
        jsr rom_filesave_transfer_data
        
      @leave:
        php  ; save carry
        lda #$00
        sta internal_state
        jsr restore_zeropage
        plp
        lda error_byte
        jmp efs_bankout  ; ends with rts


;        jsr backup_zeropage
;        bit internal_state  ; we check for bit 7/6 == 1/1
;        bpl @fileopen  ; branch if bit 7 is clear
;        bvs @fileopen  ; branch if bit 6 is clear
;        sec  ; ###
;        lda #ERROR_DEVICE_NOT_PRESENT
;        sta error_byte
;        jmp @done
;        jsr rom_save_execute ###
;        jmp @done
;      @fileopen:
;        lda #ERROR_FILE_OPEN
;        sta error_byte
;      @done:
;        php  ; save carry
;        jsr restore_zeropage
;        lda error_byte
;        plp
;        jmp efs_bankout  ; ends with rts


; --------------------------------------------------------------------
; ef read functions with manipulatable pointer

;.scope efs_readef

/*
.export efs_init_readef
.export efs_readef
.export efs_readef_low
.export efs_readef_high
.export efs_readef_read_and_inc
.export efs_readef_pointer_inc
.export efs_readef_pointer_dec
.export efs_readef_pointer_advance
.export efs_readef_pointer_reverse
.export efs_readef_pointer_setall
.export efs_readef_pointer_set

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

    efs_readef_pointer_set:
        ; X/Y
        stx efs_readef_low
        sty efs_readef_high
        rts

    efs_readef_pointer_inc:
        inc efs_readef_low
        bne :+
        inc efs_readef_high
      : rts

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
      : rts

    efs_readef_pointer_reverse:
        tax
        lda efs_readef_low
        stx efs_readef_low
        sec
        sbc efs_readef_low
        sta efs_readef_low
        bcs :+
        dec efs_readef_high
      : rts

    efs_readef_pointer_setall:
        pha  ; save a
        txa
        pha  ; save x
        tya
        pha  ; save y

;;        jsr efs_init_setstartbank
        tsx
        lda $0103, x  ; a register
;;        jsr efs_generic_command
        jsr efs_setstartbank_ext

        ; set read ef code
        jsr efs_init_readef

        pla
        sta efs_readef_high
        pla
        sta efs_readef_low
        pla
        rts
*/


; --------------------------------------------------------------------
; ef read functions with manipulatable pointer
; and independent bank storage

.export efs_init_readef
.export efs_init_readef_rely
.export efs_readef
.export efs_readef_low
.export efs_readef_high
.export efs_readef_bank
.export efs_readef_read_and_inc
.export efs_readef_pointer_inc
.export efs_readef_pointer_dec
.export efs_readef_pointer_advance
.export efs_readef_pointer_reverse
.export efs_readef_pointer_setall
.export efs_readef_pointer_set

    efs_init_readef:
        ldy #<(@codeend - @code - 1)
      : lda @code, y
        sta efs_generic_command, y
        dey
        bpl :-
        clc
        rts

      @code: ; 11 bytes; 3 bytes additional storage
        lda #$00
        sta EASYFLASH_BANK
        lda $8000  ; read from banked memory; byte 7, 8
        jmp efs_enter_pha
        .byte $00
        .word $8000
      @codeend:
      .if (@codeend - @code) > GENERIC_COMMAND_SIZE
      .error "dynamic code readef_bank to large"
      .endif

    efs_init_readef_rely:
        ldy #<(@codeend - @code - 1)
      : lda @code, y
        sta efs_generic_command, y
        dey
        bpl :-
        clc
        rts

      @code: ; 11 bytes; 3 bytes additional storage
        lda #$00
        sta EASYFLASH_BANK
        lda $8000, y  ; read from banked memory; byte 6, 7
        jmp efs_enter_pha
        .byte $00
        .word $8000
      @codeend:
      .if (@codeend - @code) > GENERIC_COMMAND_SIZE
      .error "dynamic code readef_bank to large"
      .endif

    efs_readef = efs_generic_command
    efs_readef_bank = efs_generic_command + 1
    efs_readef_low = efs_generic_command + 6
    efs_readef_high = efs_generic_command + 7
    efs_readef_storedbank = efs_generic_command + 11
    efs_readef_storedaddr_low = efs_generic_command + 12
    efs_readef_storedaddr_high = efs_generic_command + 13

    efs_readef_read_and_inc:
        jsr efs_readef
        pha
        jsr efs_readef_pointer_inc
        pla  ; to have the correct cpu states
        rts

    efs_readef_pointer_set:
        ; X/Y
        stx efs_readef_low
        sty efs_readef_high
        rts

    efs_readef_pointer_inc:
        inc efs_readef_low
        bne :+
        inc efs_readef_high
      : rts

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
      : rts

    efs_readef_pointer_reverse:
        tax
        lda efs_readef_low
        stx efs_readef_low
        sec
        sbc efs_readef_low
        sta efs_readef_low
        bcs :+
        dec efs_readef_high
      : rts

    efs_readef_pointer_setall:
        sta efs_readef_bank
        stx efs_readef_low
        sty efs_readef_high
        rts

    efs_readef_swap:
        ldx efs_readef_bank
        lda efs_readef_storedbank
        stx efs_readef_storedbank
        sta efs_readef_bank

        ldx efs_readef_low
        lda efs_readef_storedaddr_low
        stx efs_readef_storedaddr_low
        sta efs_readef_low

        ldx efs_readef_high
        lda efs_readef_storedaddr_high
        stx efs_readef_storedaddr_high
        sta efs_readef_high
        rts


; --------------------------------------------------------------------
; efs config functions
; 35/36 temporary variable

    zp_pointer_configuration = $35 ; $36


    rom_flags_set_area:
        ; area is in a
        pha
        lda efs_flags  ; clear area flags
        and #$ff - LIBEFS_FLAGS_AREA1 - LIBEFS_FLAGS_AREA2
        sta efs_flags
        
        pla
        cmp #$00
        bne :+
        rts            ; area 0

      : cmp #$01
        bne :+
        lda efs_flags  ; area 1
        ora #LIBEFS_FLAGS_AREA1
        sta efs_flags
        rts

      : lda efs_flags
        ora #LIBEFS_FLAGS_AREA2
;        ora #LIBEFS_FLAGS_AREA1
        sta efs_flags
        rts


    rom_flags_get_area:
        ; returns the active area in a
        lda efs_flags
        and #LIBEFS_FLAGS_AREA1
        beq :+
        lda #$01  ; area 1
        rts

      : lda efs_flags
        and #LIBEFS_FLAGS_AREA2
        beq :+
        lda #$02  ; area 2
        rts

      : lda #$00
        rts

    rom_flags_get_area_invert:
        ; returns the inactive area in a
        lda efs_flags
        and #LIBEFS_FLAGS_AREA1
        beq :+
        lda #$02  ; area 2
        rts

      : lda efs_flags
        and #LIBEFS_FLAGS_AREA2
        beq :+
        lda #$01  ; area 1
        rts

      : lda #$00
        rts


    rom_config_rw_available:
        ; rw areas available?
        lda #libefs_config::areas
        jsr rom_config_get_value
        cmp #$03
        beq :+
        lda #ERROR_DEVICE_NOT_PRESENT
        sec
        rts
      : clc
        rts

    rom_config_get_area_bank:
        jsr rom_flags_get_area
        jsr rom_config_areaoffset
        clc
        adc #libefs_area::bank
        jmp rom_config_get_value

    rom_config_get_area_bank_invert:
        jsr rom_flags_get_area_invert
        jsr rom_config_areaoffset
        clc
        adc #libefs_area::bank
        jmp rom_config_get_value

    rom_config_get_are_bank_zero:
        lda #libefs_config::area_0 + libefs_area::bank
        jmp rom_config_get_value


    rom_config_get_area_addr_low:
        jsr rom_flags_get_area
        jsr rom_config_areaoffset
        clc
        adc #libefs_area::addr
        jmp rom_config_get_value

    rom_config_get_area_addr_low_invert:
        jsr rom_flags_get_area_invert
        jsr rom_config_areaoffset
        clc
        adc #libefs_area::addr
        jmp rom_config_get_value


    rom_config_get_area_addr_high:
        jsr rom_flags_get_area
        jsr rom_config_areaoffset
        clc
        adc #libefs_area::addr + 1
        jmp rom_config_get_value

    rom_config_get_area_addr_high_invert:
        jsr rom_flags_get_area_invert
        jsr rom_config_areaoffset
        clc
        adc #libefs_area::addr + 1
        jmp rom_config_get_value


    rom_config_get_area_mode:
        jsr rom_flags_get_area
        jsr rom_config_areaoffset
        clc
        adc #libefs_area::mode
        jmp rom_config_get_value

    rom_config_get_area_mode_invert:
        jsr rom_flags_get_area_invert
        jsr rom_config_areaoffset
        clc
        adc #libefs_area::mode
        jmp rom_config_get_value


    rom_config_get_area_size:
        jsr rom_flags_get_area
        jsr rom_config_areaoffset
        clc
        adc #libefs_area::size
        jmp rom_config_get_value

    rom_config_get_area_size_invert:
        jsr rom_flags_get_area_invert
        jsr rom_config_areaoffset
        clc
        adc #libefs_area::size
        jmp rom_config_get_value


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


/*    rom_config_activearea:
        ; .C set if error
        ; config must be initialized
        jsr efs_init_readef

        lda #libefs_config::area_1
        jsr rom_config_checkarea
        bcc :+  ; check area 2
        ; in area 1
        lda #$01
        bne @check

      : lda #libefs_config::area_2
        jsr rom_config_checkarea
        bcc :+
        ; in area 2
        lda #$02
        bne @check
      : lda #$01  ; both empty, area 1
      @check:
        pha
        jsr rom_config_get_areastart
        jsr rom_config_set_activearea
        pla
        rts*/

    rom_config_areaoffset:
        ; the value to get to area x
        ; only values 0, 1, 2 are allowed
        clc
        cmp #$00
        beq @area0
        cmp #$01
        beq @area1
        cmp #$02
        beq @area2

      @area0:
        lda #libefs_config::area_0
        rts

      @area1:
        lda #libefs_config::area_1
        rts

      @area2:
        lda #libefs_config::area_2
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
;        rts
        jmp @next

      @default:
        lda #<efs_default_config
        sta zp_pointer_configuration
        lda #>efs_default_config
        sta zp_pointer_configuration + 1
;        rts

      @next:
        jsr rom_config_rw_available
        bcc @nextrw
        lda #$00
        jsr rom_flags_set_area
        rts

      @nextrw:
        jsr efs_init_readef

        lda #libefs_config::area_1
        jsr rom_config_checkarea
        bcc :+  ; check area 2
        ; in area 1
        lda #$01
        bne @check

      : lda #libefs_config::area_2
        jsr rom_config_checkarea
        bcc :+
        ; in area 2
        lda #$02
        bne @check
      : lda #$01  ; both empty, area 1
      @check:
;        pha
;        jsr rom_config_get_areastart
;        jsr rom_config_set_activearea
        jsr rom_flags_set_area
;        pla
        rts

/*    rom_config_get_areastart:
        ; the value to get to area x
        ; only values 0, 1, 2 are allowed
        cmp #$00
        beq @area0
        cmp #$01
        beq @area1
        cmp #$02
        beq @area2   

      @area0:
        lda #libefs_config::area_0
        rts

      @area1:
        lda #libefs_config::area_1
        rts

      @area2:
        lda #libefs_config::area_2
        rts

;        tay
;        lda #libefs_config::area_0
;      : clc
;        adc #.sizeof(libefs_area)
;        dey
;        bne :-
;        rts*/


/*    rom_config_set_activearea:
        ; sets the config pointer to the area start
        ; area distance value in a
        ;jsr rom_config_get_areastart
        clc
        adc zp_pointer_configuration
        sta zp_pointer_configuration
        bcc :+
        inc zp_pointer_configuration + 1
      : rts*/


    rom_config_checkarea:
        ; check which area is active
        ; returns .C set if area is in use
        tax
        txa
        jsr rom_config_get_value
        pha

        inx
        txa
        jsr rom_config_get_value
        pha

        inx
        txa
        jsr rom_config_get_value
        pha

        pla
        tay
        pla
        tax
        pla
        jsr efs_readef_pointer_setall

        lda #16
        jsr efs_readef_pointer_advance
        jsr efs_readef
        pha
        lda #16
        jsr efs_readef_pointer_reverse
        pla
        cmp #$ff
        beq :+
        sec  ; active area
        rts
      : clc  ; inactive area
        rts


; --------------------------------------------------------------------
; efs defragment functions
;   37: mode
;   38: bank
;   39/3a: start address high ($80 or $a0)
;   3b/3c/fd: size
; modes
;   $D0: 00:0:1FFF=>00:1:0000, 00:1:1FFF=>01:0:1FFF (lhlh...)
;   $B0: 00:0:1FFF=>01:0:0000 (llll...)
;   $D4: 00:1:1FFF=>01:1:0000 (hhhh...)

    rom_defragment_erasearea:
        ; area to erase in a
;        pha
;        jsr rom_config_prepare_config  ; ### necessary?

;        jsr rom_config_rw_available
;        bcs @error_pla

        ; rw areas available?
;        lda #libefs_config::areas
;        jsr rom_config_get_value
;        cmp #$03
;        bne @error_pla

;        pla
        cmp #$00
        beq @error
        cmp #$01
        beq @next
        cmp #$02
        beq @next
        jmp @error

        ; go to area
      @next:
        jsr rom_flags_set_area
;        jsr rom_config_get_areastart
;        jsr rom_config_set_activearea

        ; init erase sector call
        jsr efs_init_eapierasesector

;        lda #libefs_area::bank
;        jsr rom_config_get_value
        jsr rom_config_get_area_bank
        sta zp_var_x8

;        lda #libefs_area::mode
;        jsr rom_config_get_value
        jsr rom_config_get_area_mode
        sta zp_var_x7

        lda #$80  ; for ll and lh
        sta zp_var_xa
        lda zp_var_x7
        cmp #$d4
        bne :+
        lda #$a0  ; for hh
        sta zp_var_xa

;      : lda #libefs_area::size
;        jsr rom_config_get_value
      : jsr rom_config_get_area_size
        lsr a
        lsr a
        lsr a
        tax

      @loop:
        ; ### 
        ; ll, hh, lh mode
        lda zp_var_x8
        ldy zp_var_xa
        jsr efs_io_byte

        ; mode lh
        lda zp_var_x7  ; mode
        cmp #$d0
        bne @mode_ll_hh
        lda zp_var_xa
        cmp #$80   ; step from low to high
        bne :+
        lda #$a0
        sta zp_var_xa
        bne @loopend
      : lda #$80  ; step to next bank; high to low
        sta zp_var_xa
        clc
        lda #$08
        adc zp_var_x8
        sta zp_var_x8
        bne @loopend

      @mode_ll_hh:
        clc
        lda #$08
        adc zp_var_x8
        sta zp_var_x8
        ;bne @loopend

      @loopend:
        dex
        bne @loop
        lda #$00
        clc
        rts

      @error_pla:
        pla
      @error:
        lda #ERROR_DEVICE_NOT_PRESENT
        sec
        rts


    rom_defragment_copy:
        ; copies all files to the inactive area and formats the active area
        ; x : old area
        ; y : new area
        ; reading file and dir will be done by efs_readef (stores bank and address)
        ;   additional storage will save the unused address (dir when file reading, etc)
        ;   efs_temp_var1 (mode)
        ; writing will be done with EAPISetPtr and EAPIWriteFlashInc
        ;   data to write will be stored in 37: mode;  38: bank; 39/3a: address; 3b/3c/fd: size
        ;   directory pointer will be stored in 3e/3f and efs_temp_var2(bank)
        tya  ; new area
        pha
        txa  ; old area
        pha
        
        ; prepare reader and writer
        jsr efs_init_readef_rely
        jsr efs_init_eapiwriteinc

        ; prepare source
;        jsr rom_config_prepare_config
        pla  ; old area
        jsr rom_flags_set_area
;        jsr rom_config_get_areastart
;        jsr rom_config_set_activearea

        ;ldy #$00
;        lda #libefs_area::bank
;        jsr rom_config_get_value
        jsr rom_config_get_area_bank
        sta efs_readef_bank

;        lda #libefs_area::addr
;        jsr rom_config_get_value
        jsr rom_config_get_area_addr_low
        sta efs_readef_low
;        lda #libefs_area::addr + 1
;        jsr rom_config_get_value
        jsr rom_config_get_area_addr_high
        sta efs_readef_high

;        lda #libefs_area::mode
;        jsr rom_config_get_value
        jsr rom_config_get_area_mode
        sta efs_temp_var1
;        sta zp_var_x7

        ; prepare destination
;        jsr rom_config_prepare_config
        pla  ; new area
;        jsr rom_config_get_areastart
;        jsr rom_config_set_activearea
;        jsr rom_flags_set_area

;        lda #libefs_area::bank  ; bank
;        jsr rom_config_get_value
        jsr rom_config_get_area_bank_invert
        sta zp_var_x8
        sta efs_temp_var2

;        lda #libefs_area::addr  ; address low
;        jsr rom_config_get_value
        jsr rom_config_get_area_addr_low_invert
        sta zp_var_x9  ; file pointer 
        sta zp_var_xe  ; dir pointer

;        lda #libefs_area::addr + 1 ; address high
;        jsr rom_config_get_value
        jsr rom_config_get_area_addr_high_invert
        sta zp_var_xf  ; dir pointer
        clc
        adc #$18  ; ### offset for files start, from config?
        sta zp_var_xa  ; file pointer

        jsr rom_config_get_area_mode_invert
        sta zp_var_x7

        ; start iterating through source directory
      @loop:
        ; ### check overflow of directory
        ldy #16  ; offset for flag
        jsr efs_readef
        cmp #$ff  ; we are finished
        beq @leave
        and #$1f  ; only low 5 bits
        cmp #$00  ; file deleted
        beq @skip

        ; copy file
        ldy #17  ;  bank
        jsr efs_readef
        sta efs_readef_storedbank

        iny      ; reserved
        iny      ; offset low
        jsr efs_readef
        sta efs_readef_storedaddr_low
        iny      ; offset high
        jsr efs_readef
        clc
        adc #$80  ; ### correct value from config
        sta efs_readef_storedaddr_high

        iny      ; size low
        jsr efs_readef
        sta zp_var_xb
        iny      ; size mid
        jsr efs_readef
        sta zp_var_xc
        iny      ; size high
        jsr efs_readef
        sta zp_var_xd

        ; copy directory
        ; ### call defragment warning
        jsr rom_defragment_copy_dir
        jsr rom_defragment_copy_data
        jmp @loop

      @skip:
        lda #24    ; next entry
        jsr efs_readef_pointer_advance
        jmp @loop

      @leave:
        ; ### call defragment clearall
        jsr efs_finish_tempvars
        rts


    rom_defragment_copy_dir:
        ; all data prepared

        ; set dest address
        lda efs_temp_var2  ; has the destination directory bank
        jsr efs_setstartbank_ext
        lda zp_var_x7  ; mode
        ldx zp_var_xe
        ldy zp_var_xf
        jsr EAPISetPtr

        ; copy name and flag
        ldx #16  ; name
        ldy #$00
      @loop:
        jsr efs_readef_read_and_inc  ; read
        jsr efs_io_byte  ; write
        dex
        bne @loop

        ; copy flags
        jsr efs_readef_read_and_inc
        jsr efs_io_byte  ; write

        ; write new bank, reserved and offset
        lda zp_var_x8
        jsr efs_io_byte  ; write
        lda #$00
        jsr efs_io_byte  ; write
        lda zp_var_x9    ; offset low
        jsr efs_io_byte  ; write
        lda zp_var_xa    ; offset high
        sec
        sbc #$80  ; ### correct value from config
        jsr efs_io_byte  ; write

        ; write size
        lda zp_var_xb
        jsr efs_io_byte  ; write
        lda zp_var_xc
        jsr efs_io_byte  ; write
        lda zp_var_xd
        jsr efs_io_byte  ; write

        lda #$07         ; advance to next entry
        jsr efs_readef_pointer_advance

        lda #24          ; advance write directory pointer
        clc
        adc zp_var_xe
        sta zp_var_xe
        bcc :+
        inc zp_var_xf
      : 
        jsr efs_readef_swap

        rts


    rom_defragment_copy_data:

        ; set dest address
        lda zp_var_x8  ; has the destination file bank
        jsr efs_setstartbank_ext

        lda zp_var_x7  ; mode
        ldx zp_var_x9
        ldy zp_var_xa
        jsr EAPISetPtr

        ; copy data
        ldy #$00
      @loop:
        jsr efs_readef
        jsr efs_io_byte  ; use eapiwriteflash without inc?
        ;bcs @error ignore errors :(
        jsr rom_defragment_copy_data_sourceinc  ; ### unroll ?
        jsr rom_defragment_copy_data_destinc  ; ### unroll ?
        jsr rom_filesave_decrease_size  ; ### unroll ?
        bcc @loop

        ; save dest file address
        jsr EAPIGetBank
        sta zp_var_x8  ; ### redundant ?

        jsr efs_readef_swap
        lda efs_temp_var2  ; has the destination directory bank
        jsr efs_setstartbank_ext

        clc
        rts


    rom_defragment_copy_data_destinc:
        ; increases dest file address according to mode ($37)
        ; inc to next position
        inc zp_var_x9
        bne @noinc

        ; inc page
        inc zp_var_xa
        lda zp_var_x7
        and #$e0
        cmp zp_var_xa
        bne @noinc
        ; inc bank
        lda zp_var_x7
        asl
        asl
        asl
        sta zp_var_x8
        inc efs_temp_var2
        ; ### call defragment warning
      @noinc:
        rts


    rom_defragment_copy_data_sourceinc:
        ; increases source file address according to mode (efs_temp_var1)
        ; inc to next position
        inc efs_readef_low
        bne @noinc

        ; inc page
        inc efs_readef_high
        lda efs_temp_var1
        and #$e0
        cmp efs_readef_high
        bne @noinc
        ; inc bank
        lda efs_temp_var1
        asl
        asl
        asl
        sta efs_readef_high
        inc efs_readef_bank
      @noinc:
        rts


; --------------------------------------------------------------------
; efs save functions for condition checking
; usage:
;   3b/3c/fd: free size
;   3e/3f: file size
; parameter
;   io_start_address
;   io_end_address
;   filename_address
;   filename_length

    rom_filesave_conditions:
        ; checks if conditions to save are fulfilled
        ; .sec if save is not possible
        jsr rom_config_prepare_config  ; first call to config
        jsr efs_init_readef
        jsr efs_init_eapiwriteinc

        ; rw areas available?
        jsr rom_config_rw_available   ; maybe check earlier?
        bcs @error
;        lda #libefs_config::areas
;        jsr rom_config_get_value
;        cmp #$03
;        beq @check1
;        lda #ERROR_DEVICE_NOT_PRESENT
;        jmp @error

;        jsr rom_config_activearea
;        jsr rom_flags_set_area

        ; check free space
        jsr rom_filesave_maxspace
        jsr rom_filesave_usedspace
        jsr rom_filesave_addsize
        jsr rom_filesave_checksize
        bcc @check1
        lda #ERROR_DISK_FULL
        jmp @error

      @check1:
        ; ### check file size zero
        
      @check2:
        ; check conditions
        jsr rom_filesave_freedirentries  ; free disk entries
        bcs @defragment

        jsr rom_filesave_maxspace
        jsr rom_filesave_blockedspace  ; free space
        jsr rom_filesave_addsize
        jsr rom_filesave_checksize
        bcs @defragment

        clc
        rts

      @defragment:
        jsr rom_flags_get_area
        tax
        jsr rom_flags_get_area_invert
        tay
        jsr rom_defragment_copy
        jsr rom_flags_get_area
        jsr rom_defragment_erasearea

        jsr rom_config_prepare_config  ; set new configuration
        jsr efs_init_readef
        jsr efs_init_eapiwriteinc


;        jsr rom_config_activearea
;        jsr rom_flags_set_area

        ; check conditions again, this time error
        jsr rom_filesave_freedirentries  ; free disk entries
        bcs @error

        jsr rom_filesave_maxspace
        jsr rom_filesave_blockedspace  ; free space
        jsr rom_filesave_addsize
        jsr rom_filesave_checksize
        bcs @error

        clc
        rts
      @error:
        sec
        sta error_byte
        rts


    rom_filesave_freedirentries:
        ; config must be
        ; directory is set properly
        ; returns free directory entries in a
        ; the last entry does not count
        lda efs_readef_low
        pha
        lda efs_readef_high
        pha

        ldx #$00
        lda #16
        jsr efs_readef_pointer_advance

      : dex
        jsr efs_readef
        cmp #$ff
        beq :+
        lda #24
        jsr efs_readef_pointer_advance
        jmp :-

        ; reset directory
      : pla
        sta efs_readef_high
        pla
        sta efs_readef_low

        txa
        bne :+

        lda #ERROR_DISK_FULL
        sec
        rts
      : lda #$00
        clc
        rts


    rom_filesave_checksize:
        ; checks used file in 3b/3c/3d 
        ; against available size in 38/39/3a
;        sec
;        lda io_end_address
;        sbc io_start_address
;        sta zp_var_xe
;        lda io_end_address + 1
;        sbc io_start_address + 1
;        sta zp_var_xf

;        lda zp_var_xd
;        beq @compare
;        clc  ; high byte >0? enough space
;        rts
      sec
      lda zp_var_x8
      sbc zp_var_xb
      lda zp_var_x9
      sbc zp_var_xc
      lda zp_var_xa
      sbc zp_var_xd
      bmi :+
      clc
      rts
    : sec
      rts


/*      @compare: ; N1: file size(3b/3c/3d); N2: available size(38/39/3a)
        lda zp_var_xf  ; N1+1
	eor zp_var_xc  ; N2+1
	bmi @differentSigns
 
      @sameSigns:
	lda zp_var_xe  ; N1
	cmp zp_var_xb  ; N2
	lda zp_var_xf  ; N1+1
	sbc zp_var_xc  ; N2+1
	eor zp_var_xf  ; N1+1
	bmi @num1IsBigger
	jmp @num2IsBigger
 
      @differentSigns:
	clc
	lda zp_var_xe  ; N1
	adc zp_var_xb  ; N2
	lda zp_var_xf  ; N1+1
	adc zp_var_xc  ; N2+1
	eor zp_var_xf  ; N1+1
	bmi @num1IsBigger
 
      @num2IsBigger:
        clc
        rts
 
      @num1IsBigger:
        sec
        rts*/


    rom_filesave_addsize:
        ; fill size: io_end_address - io_start_address
        ; temp result in 3e/3f
        ; and add to 3b/3c/3d (low/mid/high)
        sec
        lda io_end_address
        sbc io_start_address
        sta zp_var_xe
        lda io_end_address + 1
        sbc io_start_address + 1
        sta zp_var_xf

        clc
        lda zp_var_xe
        adc zp_var_xb
        sta zp_var_xb
        lda zp_var_xf
        adc zp_var_xc
        sta zp_var_xc

        rts


    rom_filesave_maxspace:
        ; config must be set
        ; returns max blocks in 38/39/3a (low/mid/high)
        ; one chip contains 32 pages
        jsr rom_config_get_area_size
;        lda #libefs_area::size
;        jsr rom_config_get_value
        tax       ; save value
        lsr
        lsr
        lsr
        sta zp_var_xa
        txa      ; calulate midbyte
        asl
        asl
        asl
        asl
        asl
        sta zp_var_x9
        lda #$00
        sta zp_var_x8

        sec       ; reduce by dirctory
        lda zp_var_x9
        sbc #$18  ; ### value from config
        sta zp_var_x9
        bcs :+
        dec zp_var_xa

      : rts


    rom_filesave_usedspace:
        ; space by real active files
        ; config must be set correct
        ; directory is set properly
        ; returns free space in 3b/3c/3d (low/mid/high)
        lda efs_readef_low
        pha
        lda efs_readef_high
        pha

        ldx #$00
        lda #16
        jsr efs_readef_pointer_advance
        ;lda #$00
        ;sta zp_var_xb
        ;sta zp_var_xc
        ;sta zp_var_xd

      @loop:
        ; ### check overflow
        jsr efs_readef
        cmp #$ff
        beq @leave
        and #$1f
        beq @skip
        lda #5  ; move to size
        jsr efs_readef_pointer_advance

/*        jsr efs_readef_read_and_inc
        sec
        tax
        lda zp_var_xb
        stx zp_var_xb
        sdc zp_var_xb
        sta zp_var_xb
        jsr efs_readef_read_and_inc
        tax
        lda zp_var_xc
        stx zp_var_xc
        sdc zp_var_xc
        sta zp_var_xc
        jsr efs_readef_read_and_inc
        tax
        lda zp_var_xc
        stx zp_var_xc
        sdc zp_var_xc
        sta zp_var_xc*/

        clc
        jsr efs_readef_read_and_inc
        adc zp_var_xb
        sta zp_var_xb
        jsr efs_readef_read_and_inc
        adc zp_var_xc
        sta zp_var_xc
        jsr efs_readef
        adc zp_var_xd
        sta zp_var_xd

        lda #17
        jsr efs_readef_pointer_advance
        jmp @loop
      @skip:
        lda #24
        jsr efs_readef_pointer_advance
        jmp @loop

        ; reset directory
      @leave:
        pla
        sta efs_readef_high
        pla
        sta efs_readef_low

        rts


    rom_filesave_blockedspace:
        ; space blocked by real and deleted files
        ; config must be set, directory is set properly
        ; returns free space in 3b/3c/fd (low/mid/high)
        lda efs_readef_low
        pha
        lda efs_readef_high
        pha

        ldx #$00
        lda #16
        jsr efs_readef_pointer_advance
        lda #$00
        sta zp_var_xb
        sta zp_var_xc
        sta zp_var_xd

      @loop:
        ; ### check overflow
        jsr efs_readef
        cmp #$ff
        beq :+  ; leave
        lda #5  ; move to size
        jsr efs_readef_pointer_advance
        clc
        jsr efs_readef_read_and_inc
        adc zp_var_xb
        sta zp_var_xb
        jsr efs_readef_read_and_inc
        adc zp_var_xc
        sta zp_var_xc
        jsr efs_readef
        adc zp_var_xd
        sta zp_var_xd
        lda #17
        jsr efs_readef_pointer_advance

        jmp @loop

        ; reset directory
      : pla
        sta efs_readef_high
        pla
        sta efs_readef_low

        rts



; --------------------------------------------------------------------
; efs save functions for execution
; usage:
;   37: mode
;   38: bank
;   39/3a: offset in bank (with $8000 added)
;   3b/3c/fd: size
; parameter
;   fe/ff: name
;   io_start_address
;   io_end_address
;   filename_address
;   filename_length

    rom_filesave_begin:
        ; prepare variables for save
        ; usage:
        ;   38: bank
        ;   39/3a: offset in bank (with $8000 added)
        ;   3b/3c/fd: size
        ; parameter
        ;   fe/ff: name
        ;   io_start_address
        ;   io_end_address
        ;   filename_address
        ;   filename_length
        ; result
        jsr rom_config_prepare_config
        jsr efs_init_readef

;        jsr rom_config_activearea
;        jsr rom_flags_set_area
 
        ; file start area

;        lda #libefs_area::bank
;        jsr rom_config_get_value
        jsr rom_config_get_area_bank
        sta zp_var_x8
        jsr efs_setstartbank_ext

        lda #$00      ; ### get from config
        sta zp_var_x9
        lda #$18      ; ### get from config, relative offset
        sta zp_var_xa

;        jsr efs_init_readef

        jsr rom_filesave_nextentry
        ; add size to buffer ### depending on mode ll, hh or lh
        clc
        lda zp_var_x9
        adc zp_var_xb
        sta zp_var_xb
        lda zp_var_xa
        adc zp_var_xc
        sta zp_var_xc
        lda #$00
        adc zp_var_xd
        sta zp_var_xd

        ; get bank from buffer 
        asl zp_var_xd  ; high bits (### 2 or 3 shifts)
        asl zp_var_xd

        lda zp_var_xc  ; low bits (### 2 or 3 shifts)
        and #$c0
        clc
        rol
        rol
        rol
        clc
        adc zp_var_xd
        adc zp_var_x8
        sta zp_var_x8

        lda zp_var_xc
        and #$3f
        sta zp_var_xa

        lda zp_var_xb
        sta zp_var_x9

        ; calculate size
        sec
        lda io_end_address
        sbc io_start_address
        sta zp_var_xb
        lda io_end_address + 1
        sbc io_start_address + 1
        sta zp_var_xc
        lda #$00
        sta zp_var_xd

        clc
        lda #$02  ; for the address
        adc zp_var_xb
        sta zp_var_xb
        bne :+
        inc zp_var_xc
        bne :+
        inc zp_var_xd

      : clc
        rts


    rom_filesave_transfer_dir:
        ; usage:
        ;   38: bank
        ;   39/3a: offset in bank (with $8000 added)
        ;   3b/3c/fd: size
        ;   3e/3f: name
        jsr efs_init_eapiwriteinc  ; repair dynamic code

        lda efs_readef_low
        tax
        lda efs_readef_high
        tay
        lda #$d0   ; ### bank mode from config
        jsr EAPISetPtr        

;        ldx #24
;        ldy #$00
;        lda #$00
;        jsr EAPISetLen

        lda filename_address
        sta zp_var_xe
        lda filename_address + 1
        sta zp_var_xe + 1

        ; write name
        ldy #$00  ; filename length
      @loop:
        cpy #16
        beq @done
        lda filename_length
        beq @namedone
        lda (zp_var_xe), y
        jsr efs_io_byte
        iny
        dec filename_length
        jmp @loop
      @namedone:
        lda #$00
        jsr efs_io_byte
        iny
        jmp @loop

      @done:
        lda #$61  ;  flags and type
        jsr efs_io_byte

        lda zp_var_x8
        jsr efs_io_byte
        lda #$00
        jsr efs_io_byte

        lda zp_var_x9
        jsr efs_io_byte
        lda zp_var_xa
        jsr efs_io_byte

        lda zp_var_xb
        jsr efs_io_byte
        lda zp_var_xc
        jsr efs_io_byte
        lda zp_var_xd
        jsr efs_io_byte

        clc
        rts


    rom_filesave_transfer_data:
        ; usage:
        ;   38: bank
        ;   39/3a: offset in bank (with $8000 added)
        ;   3b/3c/fd: size
        ;   3e/3f: filedata
;        jsr efs_init_setstartbank   ; prepare bank
        lda zp_var_x8
;        jsr efs_generic_command
        jsr efs_setstartbank_ext

        jsr efs_init_readmem
        
        lda zp_var_xa
        clc
        adc #$80   ; ### memory offset from config
        tay
        ldx zp_var_x9
        lda #$d0   ; ### bank mode from config
        jsr EAPISetPtr

        lda io_start_address
        sta zp_var_xe
        lda io_start_address + 1
        sta zp_var_xe + 1

        lda zp_var_xe  ; start address
        jsr efs_io_byte
        jsr rom_filesave_decrease_size
        lda zp_var_xe + 1
        jsr efs_io_byte
        jsr rom_filesave_decrease_size

        ldy #$00
      @loop:
        jsr efs_readmem
        jsr efs_io_byte
        bcs @error
        inc zp_var_xe  ; ### change to iny
        bne :+
        inc zp_var_xf
      : jsr rom_filesave_decrease_size
        bcc @loop

        clc
        rts

      @error:
        lda #ERROR_WRITE_ERROR
        sta error_byte
        sec
        rts
        

    rom_filesave_decrease_size:
        ; decrease size
        lda zp_var_xb  ; size low
        bne @nomed
        lda zp_var_xc  ; size med
        bne @nohi
        lda zp_var_xd  ; size high
        beq @eof
        dec zp_var_xd  ; size high
      @nohi:
        dec zp_var_xc  ; size med
      @nomed:
        dec zp_var_xb  ; size low
        clc
        rts

      @eof:
        sec
        rts


    rom_filesave_nextentry:
        ; config must be set properly
        ; directory must be set properly
        ; result of last file
        ;   38: bank
        ;   39/3a: offset in bank (without $8000 added)
        ;   x/y: address of next dir entry
;        lda efs_readef_low
;        pha
;        lda efs_readef_high
;        pha
        
        lda #16
        jsr efs_readef_pointer_advance

      @loop:
        jsr efs_readef_read_and_inc
        cmp #$ff
        beq @leave
        jsr efs_readef_read_and_inc  ; reads bank
        sta zp_var_x8
        jsr efs_readef_pointer_inc   ; reserved
        jsr efs_readef_read_and_inc  ; offset low
        sta zp_var_x9
        jsr efs_readef_read_and_inc  ; offset high
        sta zp_var_xa
        jsr efs_readef_read_and_inc  ; size low
        sta zp_var_xb
        jsr efs_readef_read_and_inc  ; size mid
        sta zp_var_xc
        jsr efs_readef_read_and_inc  ; size high
        sta zp_var_xd

        lda #16    ; add by name 
        jsr efs_readef_pointer_advance
        jmp @loop

      @leave:
        lda #17    ; to directory begin
        jsr efs_readef_pointer_reverse
;        ldx efs_readef_low
;        ldy efs_readef_high

;        pla
;        sta efs_readef_high
;        pla
;        sta efs_readef_low

        rts




/*    rom_filesave_freeblocks:  ; ### ???
        ; config must be set to either area 1 or 2
        ; returns free blocks in X/Y (x=low)
        ; one chip contains 32 pages
        lda #libefs_area::size
        jsr rom_config_get_value
        tax
        dex      ; reduce by one for directory chip
        txa      ; calculate highbyte
        lsr
        lsr
        lsr
        tay
        txa      ; calulate lowbyte
        asl
        asl
        asl
        asl
        asl
        tax
        rts*/


/*    rom_filesave_freedirentries:  ; ### ???
        ; config must be set to either area 1 or 2
        ; directory is set properly
        ; returns free directory entries in a
        ; the last entry does not count
        lda efs_readef_low
        pha
        lda efs_readef_high
        pha
        
        ldx #$00
        lda #16
        jsr efs_readef_pointer_advance

      : dex
        jsr efs_readef
        cmp #$ff
        beq :+
        lda #24
        jsr efs_readef_pointer_advance
        jmp :-

        ; reset directory
      : pla 
        sta efs_readef_high
        pla
        sta efs_readef_low

        txa
        rts*/


/*    rom_filesave_usedspace:  ; ### ???
        ; space by real active files
        ; config must be set to either area 1 or 2
        ; directory is set properly
        ; returns free space in
        ; 3b/3c/3d (low/mid/high)
        lda efs_readef_low
        pha
        lda efs_readef_high
        pha
        
        ldx #$00
        lda #16
        jsr efs_readef_pointer_advance
        lda #$00
        sta zp_var_xb
        sta zp_var_xc
        sta zp_var_xd

      @loop:
        ; ### check overflow
        jsr efs_readef
        cmp #$ff
        beq @leave
        and #$1f
        beq @skip
        lda #5  ; move to size
        jsr efs_readef_pointer_advance
        clc
        jsr efs_readef_read_and_inc
        adc zp_var_xb
        sta zp_var_xb
        jsr efs_readef_read_and_inc
        adc zp_var_xc
        sta zp_var_xc
        jsr efs_readef
        adc zp_var_xd
        sta zp_var_xd
        lda #17
        jsr efs_readef_pointer_advance
        jmp @loop
      @skip:
        lda #24
        jsr efs_readef_pointer_advance
        jmp @loop

        ; reset directory
      @leave:
        pla 
        sta efs_readef_high
        pla
        sta efs_readef_low

        rts*/


/*    rom_filesave_blockedspace:  ; ### ???
        ; space blocked by real and deleted files
        ; config must be set to either area 1 or 2
        ; directory is set properly
        ; returns free space in
        ; 3b/3c/fd (low/mid/high)
        lda efs_readef_low
        pha
        lda efs_readef_high
        pha

        ldx #$00
        lda #16
        jsr efs_readef_pointer_advance
        lda #$00
        sta zp_var_xb
        sta zp_var_xc
        sta zp_var_xd

      @loop:
        ; ### check overflow
        jsr efs_readef
        cmp #$ff
        beq :+  ; leave
        lda #5  ; move to size
        jsr efs_readef_pointer_advance
        clc
        jsr efs_readef_read_and_inc
        adc zp_var_xb
        sta zp_var_xb
        jsr efs_readef_read_and_inc
        adc zp_var_xc
        sta zp_var_xc
        jsr efs_readef
        adc zp_var_xd
        sta zp_var_xd
        lda #17
        jsr efs_readef_pointer_advance

        jmp @loop

        ; reset directory
      : pla
        sta efs_readef_high
        pla
        sta efs_readef_low

        rts*/



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
        ; ### load config
        jsr efs_init_eapireadinc  ; repair dynamic code

        ; directory entry
        ldx $39  ; efs_directory_entry + efs_directory::offset_low
        lda $3a  ; efs_directory_entry + efs_directory::offset_high
        clc
        adc #$80
        tay
        lda #$d0  ; eapi bank mode ### from config
        jsr EAPISetPtr

        ldx $3b  ; efs_directory_entry + efs_directory::size_low
        ldy $3c  ; efs_directory_entry + efs_directory::size_high
        lda $3d  ; efs_directory_entry + efs_directory::size_upper
        jsr EAPISetLen

;        jsr efs_init_setstartbank
        lda $38  ; efs_directory_entry + efs_directory::bank
;        jsr efs_generic_command
        jsr efs_setstartbank_ext

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
      @loop:
        jsr efs_io_byte
        bcs @eof  ; eof
        sta zp_var_x7
        ldy #$00
        jsr efs_generic_command
        cmp zp_var_x7
        bne @mismatch
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
        bcs @notfound     ; not found
        jsr rom_scratch_process
        rts  ; error and .C set in rom_scratch_process

      @notfound:
        lda #ERROR_FILE_NOT_FOUND
        sta error_byte
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
        ; if in area 0 -> write protected
        jsr rom_flags_get_area
        cmp #$00  ; area0
        bne @scratch
        lda #ERROR_WRITE_PROTECTED
        sta error_byte
        bne @error

      @scratch:
        lda #16  ; advance pointer to flags
        jsr efs_readef_pointer_advance

        ; prepare bank
;        ;jsr efs_init_setstartbank
;        jsr rom_flags_get_area
;        jsr rom_config_get_areastart
;        tay
;        lda (zp_var_x5), y  ; at libefs_config::areax::bank
        ;jsr efs_generic_command
        jsr rom_config_get_area_bank
        jsr efs_setstartbank_ext

;        iny                 ; banking mode
;        iny
;        iny
;        lda (zp_var_x5), y  ; at libefs_config::areax::mode
        jsr rom_config_get_area_mode
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



; --------------------------------------------------------------------
; directory search functions
; usage:
;   35/36: pointer to configuration
;   37: name check result
;   3e/3f: pointer to name
; return:
;   38: bank
;   39/3a: offset in bank (with $8000 added)
;   3b/3c/3d: size
;   read_ef: pointer is at begin of directory entry

;    dir_read_byte_low = efs_io_byte + 1
;    dir_read_byte_high = efs_io_byte + 2

;    dirsearch_area_var_zp := $37
    dirsearch_temp_var_zp := $38
    dirsearch_name_pointer_zp := $3e
    dirsearch_entry_zp := $3b

    efs_directory_search:
        lda filename_address
        sta dirsearch_name_pointer_zp
        lda filename_address + 1
        sta dirsearch_name_pointer_zp + 1

        jsr rom_config_prepare_config
        lda #libefs_config::areas  ; ###
        jsr rom_config_get_value
        cmp #$03
        beq :+

        ; read only efs
        lda #$00
        jsr rom_flags_set_area
;        sta dirsearch_area_var_zp
        lda #libefs_config::area_0
        jsr rom_dirsearch_begin
        jsr rom_dirsearch_find
        bcc @found
        sec
        rts
        
        ; rw efs
      : lda #$00
;        sta dirsearch_area_var_zp
        jsr rom_flags_set_area
        lda #libefs_config::area_0
        jsr rom_dirsearch_begin
        jsr rom_dirsearch_find
        bcc @found
        lda #$01
;        sta dirsearch_area_var_zp
        jsr rom_flags_set_area
        lda #libefs_config::area_1
        jsr rom_dirsearch_begin
        jsr rom_dirsearch_find
        bcc @found
        lda #$02
;        sta dirsearch_area_var_zp
        jsr rom_flags_set_area
        lda #libefs_config::area_2
        jsr rom_dirsearch_begin
        jsr rom_dirsearch_find
        bcc @found

        ; not found
        lda #$00
        jsr rom_flags_set_area
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

        ; set read ef code
        jsr efs_init_readef

;        jsr rom_config_prepare_config

;        jsr efs_init_setstartbank
        ;lda #$00  ; ### 0, could be different bank
        ldy dirsearch_temp_var_zp
        lda ($35), y  ; at libefs_config::libefs_area::bank
;        jsr efs_generic_command
        jsr efs_setstartbank_ext
        sta efs_readef_bank

;        ; set read ef code
;        jsr efs_init_readef_bank

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

        jsr efs_init_set startbank
        ;lda #$00  ; ### 0, could be different bank
        ldy dirsearch_temp_var_zp
        lda ($35), y  ; at libefs_config::libefs_area::bank
        jsr efs_generic_command

        ; set read ef code
        jsr efs_init_readef

        inc dirsearch_temp_var_zp
        ldy dirsearch_temp_var_zp
        lda ($35), y  ; at libefs_config::libefs_area::addr low
        sta efs_read ef_low

        inc dirsearch_temp_var_zp
        ldy dirsearch_temp_var_zp
        lda ($35), y  ; at libefs_config::libefs_area::addr high
        sta efs_read ef_high

        ; banking mode and area size is irrelevant in dirsearch
        rts*/


/*    rom_scratch_process:
        ; configuration is at the correct area
        jsr efs_init_eapiwriteinc  ; prepare dynamic code

        ; filedata are set
        ; if in area 1 -> write protected
        lda zp_var _x7
        cmp #$01
        bne @scratch
        lda #ERROR_WRITE_PROTECTED
        sta error_byte
        bne @error

      @scratch:
        lda #16  ; advance pointer to flags
        jsr efs_read ef_pointer_advance

        ; prepare bank
        jsr efs_init_set startbank
        lda zp_var _x7
        jsr rom_config_get_areastart
        tay
        lda (zp_var_x5), y  ; at libefs_config::areax::bank
        jsr efs_generic_command

        iny                 ; banking mode
        iny
        iny
        lda (zp_var_x5), y  ; at libefs_config::areax::mode
;        tax                 ; save mode in x

;        lda efs_read ef_high  ; and address
;        cmp #$b0
;        bcc :+
;        clc
;        adc #$40
;      : tay
;        txa
        ldx efs_read ef_low
        ldy efs_read ef_high
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
