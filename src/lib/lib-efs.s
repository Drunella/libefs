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


; ### implement conditional switches for non rom version ???
; ### segments for read only


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
.import temporary_variable
.import backup_memory_config
.import memory_byte
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
.import efs_bankout_end
.import efs_enter_pha
.import efs_enter

.import rom_dirload_isrequested
.import rom_dirload_verify
.import rom_dirload_transfer
.import rom_dirload_address
.import rom_dirload_begin
.import rom_dirload_chrin

.import rom_format_body
.import rom_defragment_body
.import rom_chrout_body
.import rom_save_body
.import rom_filesave_chrin_prepare
.import rom_filesave_chrin_close
.export rom_chrin_body
.export rom_close_body
.export rom_open_body
.export rom_load_body
.export rom_setnam_body
.export rom_setlfs_body

.export restore_zeropage
.export backup_zeropage

.export efs_setstartbank_ext

.export rom_config_get_value
.export rom_config_prepare_config
.export rom_flags_get_area
.export rom_flags_set_area
.export rom_flags_get_area_invert
.export rom_config_rw_available
.export rom_config_get_area_bank
.export rom_config_get_area_mode_invert
.export rom_config_get_area_addr_high_invert
.export rom_config_get_area_addr_low_invert
.export rom_config_get_area_bank_invert
.export rom_config_get_area_addr_high
.export rom_config_get_area_addr_low
.export rom_config_get_area_size
.export rom_config_get_area_mode

.export efs_directory_search
.export efs_finish_tempvars
.export efs_temp_var1
.export efs_temp_var2
.export efs_init_eapierasesector
.export efs_init_eapireadinc
.export efs_init_eapiwriteinc
.export efs_init_readmem
.export efs_readef_dirboundary
.export efs_readef_storedaddr_high
.export efs_readef_storedaddr_low
.export efs_readef_storedbank
.export efs_readef_swap
.export efs_readmem

.export rom_command_begin
.import rom_command_save_process
.import rom_scratch_process

.export rom_config_call_defragment_allclear
.export rom_config_call_defragment_warning


.segment "EFS_CALL"

; --------------------------------------------------------------------
; efs rom jump table
; 3 bytes jmp
; 10 byte magic & version
; 3 byte filler

    EFS_init: ; @ $8000
        ; parameter: none
        ; return:
        ;    .C: 1 if error
        jmp efs_init_body

    EFS_init_eapi: ; @ $8003
        ; parameter:
        ;    A: high address to put EAPI to
        ; return: 
        ;    .C set if eapi not present
        jmp efs_init_eapi_body

    EFS_init_mini_eapi: ; @ $8006
        jmp efs_init_minieapi_body

    EFS_defragment: ; @ $8009
        ; validates (defragments) the rw area
        jmp rom_defragment_body

    EFS_format: ; @ $800c
        ; initializes (erases) the rw area
        jmp rom_format_body

    EFS_validate: ; @ $800f
        ; parameter: none
        ; return:
        ;    .C set if problems occured (defragmentation necessary)
        jmp rom_validate_body

    ; unused
        .byte $00, $00, $00, $00, $00, $00

    efs_magic: ; @ $8018
    efs_default_config:
        .byte "libefs"
        .byte major_version, minor_version, patch_version

        .byte $01                      ; one area
        .byte $00, $00, $a0, $d0, $ff  ; area 0: bank 0, $a000, mode lhlh, unlimited
        .byte $00, $00, $00, $00, $00  ; area 1: none
        .byte $00, $00, $00, $00, $00  ; area 2: none
        .byte $00, $00, $00            ; defragment: no
        .byte $00, $00, $00, $00  ; dummy
        .byte $00, $00, $00, $00  ; dummy
        .byte $00, $00, $00, $00  ; dummy

    efs_config_size = * - efs_default_config
    .if efs_config_size <> 40
    .error "efs config size mismatch"
    .endif

    efs_call_size = * - EFS_init
    .if efs_call_size <> 64
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
        lda #$00                ; init zp
        sta ZEROPAGE_BACKUP_END - ZEROPAGE_SIZE + 1, x
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
        rts


    efs_init_minieapi_body:
        pha
        txa
        pha
        tya
        pha

        ; copy code to df80
        ldx #<__EFS_MINIEAPI_SIZE__ - 1
    :   lda __EFS_MINIEAPI_LOAD__,x
        sta __EFS_MINIEAPI_RUN__,x
        dex
        bpl :-
        clc

        pla
        tay
        pla
        tax
        pla
        rts


    efs_init_eapi_body:
        sta temporary_variable
        pha
        txa
        pha
        tya
        pha
        ldx temporary_variable

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
        jsr efs_generic_command  ; init eapi
        clc
      @leave:
        pla
        tay
        pla
        tax
        pla
        rts

      @error:
        sec
        bcs @leave

      @code:
        jsr efs_bankout
      @dest = * - @code + 2
        sta $c000, x
        jmp efs_enter_pha
      @codeend:
      .if (@codeend - @code) > GENERIC_COMMAND_SIZE
      .error "dynamic code initeapi to large"
      .endif


    rom_validate_body:
        lda #ERROR_DEVICE_NOT_PRESENT
        ; ### todo implement ###
        ; return 0: everything is fine
        ; return 1: deleted invalid files; defragmentation necessary
        rts


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
        lda (zp_var_xe), y  ; read from memory
        ldx memory_byte
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
        ldx memory_byte
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
        efs_bankout_source := __EFS_RAM_LOAD__ + (efs_bankout_end - __EFS_RAM_RUN__)
        pha
        lda #$20  ; jsr
        sta efs_bankout_end - 6
        lda #<EAPISetBank
        sta efs_bankout_end - 5
        lda #>EAPISetBank
        sta efs_bankout_end - 4
        lda #$4c  ; jmp
        sta efs_bankout_end - 3
        lda #<efs_enter_pha
        sta efs_bankout_end - 2
        lda #>efs_enter_pha
        sta efs_bankout_end - 1
        pla

        jsr efs_bankout_end - 6

        ; repair changed code
        pha
        lda efs_bankout_source - 6
        sta efs_bankout_end - 6
        lda efs_bankout_source - 5
        sta efs_bankout_end - 5
        lda efs_bankout_source - 4
        sta efs_bankout_end - 4
        lda efs_bankout_source - 3
        sta efs_bankout_end - 3
        lda efs_bankout_source - 2
        sta efs_bankout_end - 2
        lda efs_bankout_source - 1
        sta efs_bankout_end - 1
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

.segment "EFS_ROM"

    rom_setlfs_body:
        ; Y: secondary address (relocation)
        lda internal_state
        bne @exit

        lda #$00  ; secondary address for relocation
        cpy #$00
        bne :+    ; zero => relocate
        lda #LIBEFS_FLAGS_RELOCATE
      : sta efs_flags

        jmp efs_bankout  ; ends with rts

      @exit:
;        pla
        lda #ERROR_FILE_OPEN
        sta error_byte
        sec
        jmp efs_bankout  ; ends with rts


    rom_setnam_body:
        ; A: length; X/Y: name address (x low)
        pha
        lda internal_state
        bne @exit
        pla
        sta filename_length
        stx filename_address
        sty filename_address + 1;
        clc  ; no error
        jmp efs_bankout  ; ends with rts

      @exit:
        pla
        lda #ERROR_FILE_OPEN
        sta error_byte
        sec
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
        bit internal_state  ; we check for bit 7/6 == 0/1
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
        ; parameters: A: 0: read; 1: write
        ; returns A, .C
        pha  ; save read/write
        jsr backup_zeropage

        lda #$00         ; reset state and error
        sta status_byte
        sta error_byte

        lda internal_state  ; check if file open
        beq @loadsavecheck
        pla
        lda #ERROR_FILE_OPEN
        sta error_byte
        sec
        bne @leave

      @loadsavecheck:
        ; set load/save
        pla
        beq :+
        lda #%11000000  ; file save processing
        sta internal_state
        jmp @commandcheck
      : lda #%10000000  ; file load processing
        sta internal_state
        ;jmp @commandcheck

      @commandcheck:
        jsr rom_command_begin
        bcs @loadcheck
        jsr rom_command_process
        bcc @loadcheck  ; .C clear: no error and continue
        bne :+
        clc             ; .C set and no error
      : jmp @leave      ; leave

;        jmp @leave  ; always finish after commands

      @loadcheck:
        lda internal_state
        and #%11000000
        cmp #%10000000
        bne @savecheck
        jsr rom_fileload_chrout_prepare
        jmp @leave

      @savecheck:
        lda internal_state
        and #%11000000
        cmp #%11000000  ; file save processing
        bne @dircheck
;        lda #%11000000  ; file save processing
;        sta internal_state
;        jsr rom_command_save_process
;        bcs @leave
        jsr rom_filesave_chrin_prepare
        jmp @leave

      @dircheck:
        lda internal_state
        and #%11000000
        cmp #%01000000  ; dir save processing
        bne @error
        jsr rom_dirload_begin  ; only command that will be executed here
        jmp @leave

      @error:
        lda #ERROR_SYNTAX_ERROR_30
        sta error_byte
        sec

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
        ;sta status_byte  ; don'k kill the status on close
        sta error_byte

        lda internal_state
        bne @close
        sec 
        lda #ERROR_FILE_NOT_OPEN
        sta error_byte

      @close:
        bit internal_state  ; we check for bit 7/6 == 1/1
        bpl @next  ; branch if bit 7 is clear
        bvc @next  ; branch if bit 6 is clear
        jsr rom_filesave_chrin_close

      @next:
        lda #$00
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
        beq @commandcheck
        lda #ERROR_FILE_OPEN
        sta error_byte
        sec
        bne @leave

      @commandcheck:
        jsr rom_command_begin
        bcs @fileload
        jsr rom_command_load_process
        bcc @fileload  ; .C clear: no error and continue
        bne :+
        clc            ; .C set and no error
      : jmp @leave     ; leave

/*      @dircheck: ; ### move to commands
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
        jmp @leave*/

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


    efs_readef_dirboundary:
        ; check if directory cursor is out of bounds
        ; .C set if out of bounds
        ; base address in a
        clc
        adc #>DIRECTORY_SIZE
;        lda efs_readef_high
;        cmp #$b8  ; directory boundary
        cmp efs_readef_high
        beq @out
        bcc @out
        clc
        rts
      @out:
        sec
        rts



; --------------------------------------------------------------------
; efs config functions
; 35/36 pointer to configuration

;    zp_pointer_configuration = zp_var_x5 ; $36

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


    rom_config_call_defragment_warning:
        lda #libefs_config::dfcall
        jsr rom_config_get_value
        beq @done

        lda zp_var_x5
        pha
        lda zp_var_x5 + 1
        pha

        ; copy warning call address
        lda #libefs_config::dfwarning
        jsr rom_config_get_value
        tax
        lda #libefs_config::dfwarning + 1
        jsr rom_config_get_value
        sta zp_var_x5 + 1
        txa
        sta zp_var_x5

        ; prepare return address
        lda #>(@return - 1)
        pha
        lda #<(@return - 1)
        pha

        jmp (zp_var_x5)
      @return:

        pla
        sta zp_var_x5 + 1
        pla 
        sta zp_var_x5

      @done:
        rts


    rom_config_call_defragment_allclear:
        lda #libefs_config::dfcall
        jsr rom_config_get_value
        beq @done

        lda zp_var_x5
        pha
        lda zp_var_x5 + 1
        pha

        ; copy warning call address
        lda #libefs_config::dfallclear
        jsr rom_config_get_value
        tax
        lda #libefs_config::dfallclear + 1
        jsr rom_config_get_value
        sta zp_var_x5 + 1
        txa
        sta zp_var_x5

        ; prepare return address
        lda #>(@return - 1)
        pha
        lda #<(@return - 1)
        pha

        jmp (zp_var_x5)
      @return:

        pla
        sta zp_var_x5 + 1
        pla
        sta zp_var_x5

      @done:
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
        php  ; save status
        sei
        pha  ; save a
        txa
        pha  ; save x
        tya
        pha  ; save y
 
        tsx
        lda $0103, x  ; a register
        tay
        lda (zp_var_x5), y
        sta $0103, x  ; a register

        pla
        tay
        pla
        tax
        pla  ; it will pop the result
        plp  ; restores interrupt flag
        rts


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
        sta zp_var_x5
        lda #>LIBEFS_CONFIG_START
        sta zp_var_x5 + 1
        jmp @next

      @default:
        lda #<efs_default_config
        sta zp_var_x5
        lda #>efs_default_config
        sta zp_var_x5 + 1

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
        jsr rom_flags_set_area
        rts


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
; commands processing functions
; usage:
;   35/36: configuration pointer
;      38: command
;   3e/3f: pointer to name
    rom_command_begin:
        ; return:
        ;   .C set if no command
        ;   38: 0 for no command
        lda filename_address
        sta zp_var_xe
        lda filename_address + 1
        sta zp_var_xf

        ldy #$00
        lda (zp_var_xe), y
        sta zp_var_x8

        lda filename_length
        cmp #$01  ; check for 1 char commands
        bne @next1

        ; check for '$'
        lda #$24        ; '$'
        cmp (zp_var_xe), y
        beq @match
        bne @nomatch

      @next1:        
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
        lda #$00
        sta zp_var_x8
        sec  ; no command
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
        ; .C set: error (.Z set) or stop processing (.Z clear)
        ; .C clear: no error and continue
        ; error_byte: error code
        ; commands in load can continue
        lda zp_var_x8
        cmp #$24    ; '$', dirload
        bne @next1
        lda #%01000000  ; directory processing
        sta internal_state
        jmp @continue

      @next1:
        lda zp_var_x8
        cmp #$53    ; 'S'
        bne @next2
        ; scratch
        jsr efs_directory_search
        bcs @error     ; not found
        jsr rom_scratch_process
        ; error and .C set in rom_scratch_process, may continue
        jmp @stop  ; error_byte is set to 1, due to scratch

      @next2:
        lda zp_var_x8
        cmp #$40    ; '@', overwrite
        bne @next3
        lda internal_state
        and #%11000000
        cmp #%11000000
        bne @next3  ; only for save
        jsr efs_directory_search
        bcs :+      ; not found, ignore
        jsr rom_scratch_process
      : lda #$00    ; no error
        sta error_byte
        clc         ; continue after
        rts

      @next3:

        lda #ERROR_SYNTAX_ERROR_30
        sta error_byte

      @error:
        lda #$00  ; auto close on error
        sta internal_state
        lda error_byte
        sec
        rts

      @stop:
        lda #$00
        sec
        rts

      @continue:
        clc
        rts


    rom_command_load_process:
        ; .C set: error (.Z set) or stop processing (.Z clear)
        ; .C clear: no error and continue
        ; error_byte: error code
        ; commands in load can continue
        lda zp_var_x8
        cmp #$24    ; '$', dirload
        bne @next1
        jsr rom_dirload_begin
        jsr rom_dirload_address
        jsr rom_dirload_transfer
        lda #$00
        sta error_byte
        sec  ; finish after
        rts

      @next1:
        ; next command

        lda #ERROR_SYNTAX_ERROR_30
        sta error_byte
        sec
        rts
        ;jmp @leave

;      @leave:
;        rts



; --------------------------------------------------------------------
; efs load and verify functions
; parameter:
;   38: bank
;   39/3a: offset in bank (with $8000 added)
;   3b/3c/fd: size
; using
;   37: temporary
;   3e/3f: pointer to data
 
    rom_fileload_chrout_prepare:
        lda #%10000000  ; file load processing
        sta internal_state

        jsr efs_directory_search
        bcc @found
        lda #$00
        sta internal_state  ; auto close on not found
        sec
        rts

      @found:
        jsr rom_fileload_begin
        clc
        rts


    rom_fileload_begin:
        jsr rom_config_prepare_config
        jsr efs_init_eapireadinc  ; repair dynamic code

        ; directory entry
        ldx zp_var_x9  ; efs_directory_entry + efs_directory::offset_low
        jsr rom_config_get_area_addr_high
        clc
        adc zp_var_xa  ; efs_directory_entry + efs_directory::offset_high
        sta zp_var_xa
        tay
        jsr rom_config_get_area_mode
        jsr EAPISetPtr

        ldx zp_var_xb  ; efs_directory_entry + efs_directory::size_low
        ldy zp_var_xc  ; efs_directory_entry + efs_directory::size_high
        lda zp_var_xd  ; efs_directory_entry + efs_directory::size_upper
        jsr EAPISetLen

        lda zp_var_x8  ; efs_directory_entry + efs_directory::bank
        jsr efs_setstartbank_ext

        rts


/*    rom_fileload_begin_fast:
        jsr rom_config_prepare_config
        ;jsr efs_init_eapireadinc  ; repair dynamic code

        ; directory entry
        ;ldx zp_var_x9  ; efs_directory_entry + efs_directory::offset_low
        jsr rom_config_get_area_addr_high
        clc
        adc zp_var_xa  ; efs_directory_entry + efs_directory::offset_high
        sta zp_var_xa
        ;tay
        ;jsr rom_config_get_area_mode
        ;jsr EAPISetPtr

        ;ldx zp_var_xb  ; efs_directory_entry + efs_directory::size_low
        ;ldy zp_var_xc  ; efs_directory_entry + efs_directory::size_high
        ;lda zp_var_xd  ; efs_directory_entry + efs_directory::size_upper
        ;jsr EAPISetLen

        ;lda zp_var_x8  ; efs_directory_entry + efs_directory::bank
        ;jsr efs_setstartbank_ext

        rts*/


    rom_fileload_address:
        jsr efs_io_byte ; load address
        sta zp_var_xe
        jsr efs_io_byte
        sta zp_var_xf
        ;lda efs_secondary  ; 0=load to X/Y, 1=load to prg address
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


    rom_fileload_transfer:
        ldy #$00
      @loop:
        jsr efs_io_byte
        bcs @eof
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
     
        lda #STATUS_EOF
        sta status_byte

        lda zp_var_xe
        sta io_end_address
        lda zp_var_xf
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
        inc zp_var_xe
        bne @loop
        inc zp_var_xf
        jmp @loop

      @eof:
        lda #STATUS_EOF
        sta status_byte
        lda zp_var_xe  ; verify successful, reduce address by one
        bne :+
        dec zp_var_xf
      : dec zp_var_xe
        jmp @leave

      @mismatch:
        lda #STATUS_MISMATCH
        sta status_byte
        
      @leave:
        clc
        tya
        adc zp_var_xe
        sta zp_var_xe
        bcc :+
        inc zp_var_xf

      : lda zp_var_xe
        sta io_end_address
        lda zp_var_xf
        sta io_end_address + 1

        lda status_byte
        and #STATUS_MISMATCH
        bne :+
        clc
        rts
      : sec
        rts



; --------------------------------------------------------------------
; directory search functions
; configuration has been set correctly
; usage:
;   35/36: pointer to configuration
;   37: name check result
;   3e/3f: pointer to name
; return:
;   38: bank
;   39/3a: offset in bank (with $8000 added)
;   3b/3c/3d: size
;   read_ef: pointer is at begin of directory entry
;   changed configuration settings

    efs_directory_search:
        lda filename_address
        sta zp_var_xe
        lda filename_address + 1
        sta zp_var_xe + 1

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


    rom_dirsearch_filedata:
        ; position is at flags, bank is the next data to load
        ; all zp variables are free and can be used
        jsr efs_readef_read_and_inc  ; efs_io_byte  ; bank
        sta zp_var_x8
        jsr efs_readef_read_and_inc  ; efs_io_byte  ; bank high

        ; offset
        jsr efs_readef_read_and_inc  ; efs_io_byte
        sta zp_var_x9
        jsr efs_readef_read_and_inc  ; efs_io_byte
        ; memory offset will be added later
        sta zp_var_xa

        ; size
        jsr efs_readef_read_and_inc  ; efs_io_byte
        sta zp_var_xb
        jsr efs_readef_read_and_inc  ; efs_io_byte
        sta zp_var_xc
        jsr efs_readef_read_and_inc  ; efs_io_byte
        sta zp_var_xd

        ; reverse to flag
        lda #24  ; reverse pointer to name
        jsr efs_readef_pointer_reverse
        clc

        rts


    rom_dirsearch_begin:
        ; set pointer and length of directory
        ; a offset in configuration
        sta zp_var_x8

        ; set read ef code
        jsr efs_init_readef

        ldy zp_var_x8
        lda (zp_var_x5), y  ; at libefs_config::libefs_area::bank
        jsr efs_setstartbank_ext
        sta efs_readef_bank

        inc zp_var_x8
        ldy zp_var_x8
        lda (zp_var_x5), y  ; at libefs_config::libefs_area::addr low
        sta efs_readef_low

        inc zp_var_x8
        ldy zp_var_x8
        lda (zp_var_x5), y  ; at libefs_config::libefs_area::addr high
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
        sta zp_var_xb
        inx
        
        lda #$2a             ; '*'
        cmp (zp_var_xe), y   ; character in name is '*', we have a match
        beq @match
        lda #$3f             ; '?'
        cmp (zp_var_xe), y   ; character in name is '?', the char fits
        beq @fit
        lda (zp_var_xe), y   ; compare character with character in entry
        cmp zp_var_xb        ; if not equal nextname
        bne @next
      @fit:
        iny
        cpy filename_length  ; name length check
        bne @loop            ; more characters
        cpy #$10             ; full name length reached
        beq @match           ;   -> match
        jsr efs_readef_read_and_inc  ; load next char
        sta zp_var_xb
        inx
        lda zp_var_xb        ; if == \0
        beq @match           ;   -> match
                             ; length check failed
      @next:
        cpx #$10
        beq :+
        jsr efs_readef_read_and_inc  ; load next char
        inx
        bne @next
      : lda #$00
        sta zp_var_x8
        rts

      @match:
        cpx #$10
        beq :+
        jsr efs_readef_read_and_inc  ; load next char
        inx
        bne @match
      : lda #$01
        sta zp_var_x8
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
        jsr rom_config_get_area_addr_high
        jsr efs_readef_dirboundary
;        bcs @leave  ; directory out of bounds
;        jsr rom_dirsearch_checkboundary
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
        lda zp_var_x8
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
        sta zp_var_x8

        jsr rom_config_prepare_config

        jsr efs_init_set startbank
        ;lda #$00  ; ### 0, could be different bank
        ldy zp_var_x8
        lda ($35), y  ; at libefs_config::libefs_area::bank
        jsr efs_generic_command

        ; set read ef code
        jsr efs_init_readef

        inc zp_var_x8
        ldy zp_var_x8
        lda ($35), y  ; at libefs_config::libefs_area::addr low
        sta efs_read ef_low

        inc zp_var_x8
        ldy zp_var_x8
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
