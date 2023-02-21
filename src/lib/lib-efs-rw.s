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
.include "../../version.txt"


;.import __EFS_RAM_LOAD__
;.import __EFS_RAM_RUN__
;.import __EFS_RAM_SIZE__

;.import __EFS_MINIEAPI_LOAD__
;.import __EFS_MINIEAPI_RUN__
;.import __EFS_MINIEAPI_SIZE__

.import backup_zeropage_data
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
;.import efs_bankin
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
.export rom_defragment_body
.export rom_format_body
.export rom_filesave_chrin_prepare
.export rom_filesave_chrin_close
;.export rom_filesave_blocksfree

.export rom_command_save_process
;.import rom_command_process
.import rom_command_begin
.export rom_scratch_process

.import restore_zeropage
.import backup_zeropage

.import efs_setstartbank_ext

.import rom_flags_get_area
.import rom_flags_set_area
.import rom_flags_get_area_invert
.import rom_config_rw_available
.import rom_config_get_value
.import rom_config_prepare_config
.import rom_config_get_area_bank
;.import rom_config_get_area_mode_invert
;.import rom_config_get_area_addr_high_invert
;.import rom_config_get_area_addr_low_invert
;.import rom_config_get_area_bank_invert
;.import rom_config_get_area_addr_high
;.import rom_config_get_area_addr_low
.import rom_config_get_area_size
;.import rom_config_get_area_mode
.import rom_config_get_area_dirbank
.import rom_config_get_area_dirbank_invert
.import rom_config_get_area_dirhigh
.import rom_config_get_area_dirhigh_invert
.import rom_config_get_area_filesbank
.import rom_config_get_area_filesbank_invert
.import rom_config_get_area_fileshigh
.import rom_config_get_area_fileshigh_invert


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
.import efs_readef_swap
.import efs_readef_storedaddr_high
.import efs_readef_storedaddr_low
.import efs_readef_storedbank
.import efs_readef_dirboundary

.import efs_readmem
.import efs_init_readmem
.import efs_init_eapierasesector
.import efs_init_eapireadinc
.import efs_init_eapiwriteinc
.import efs_init_eapiwrite
.import efs_finish_tempvars
.import efs_temp_var1
.import efs_temp_var2
.import rom_config_call_defragment_allclear
.import rom_config_call_defragment_warning

.import efs_directory_search

.import rom_space_setdirstart
.import rom_space_subtractsize_blocks
.import rom_space_maxspace
.import rom_space_usedspace


.segment "EFS_ROM_RW"


; --------------------------------------------------------------------
; efs body functions
; need to leave with 'jmp efs_bankout'
; zeropage usage only after zeropage backup

    rom_defragment_body:
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


    rom_format_body:
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


    rom_chrout_body:
        ; character in a
        ; no zeropage usage
        tax
        lda internal_state
        bne @next1
        sec
        lda #ERROR_FILE_NOT_OPEN
        sta error_byte
        bne @done

      @next1:
        lda status_byte    ; previous eof -> error
        beq @next2
        lda #ERROR_WRITE_ERROR
        sta error_byte
        sec
        beq @done

      @next2:
        bit internal_state  ; we check for bit 7/6 == 1/1
        bpl @error  ; branch if bit 7 is clear
        bvc @error  ; branch if bit 6 is clear

        txa
        jsr efs_io_byte  ; write byte
        ; size field pointer in filename_address and filename_length(bank)
        ; size in io_start_address, io_end_address low
        bcs @writeerror

        clc ; increase size
        lda #$00
        inc io_start_address
        bne @next3
        inc io_start_address + 1
        bne @next3
        inc io_end_address
        beq @next3
      @next3:
        jsr EAPIGetBank  ; check overflow
        cmp io_end_address + 1
        beq @overflow
        lda #$00
        clc
        beq @done

      @overflow:
        lda #ERROR_DISK_FULL
        sta error_byte
        lda #STATUS_EOF
        sta status_byte
        bne @done

      @writeerror:
        sec
        lda #ERROR_WRITE_ERROR
        sta error_byte
        bne @done

      @error:
        sec
        lda #ERROR_NO_OUTPUT_FILE
        sta error_byte
        ;bne @done

      @done:
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
        beq @checkconditions
        lda #ERROR_FILE_OPEN
        sta error_byte
        sec
        bne @leave

      @checkconditions:
        jsr rom_filesave_conditions
        bcs @leave

      @commandcheck:
        jsr rom_command_begin
        bcs @filesearch
        jsr rom_command_save_process
        bcc @filesearch  ; .C clear: no error and continue
        bne :+
        clc              ; .C set and no error
      : jmp @leave       ; leave


/*      @dircheck:
        jsr rom_dirload_isrequested
        bcc @checkname
        lda #ERROR_MISSING_FILENAME
        sta error_byte
        sec
        bne @leave*/

/*      @checkname:
        jsr rom_filesave_conditions
        bcs @leave
        jsr rom_command_begin
        bcs @fileload
        jsr rom_command_save_process
        bcs @leave*/

      @filesearch:
        jsr efs_directory_search
        bcs @savefile ; not found
;        jsr rom_scratch_process
;        bcs @leave
        lda #ERROR_FILE_EXISTS
        sta error_byte
        sec
        bne @leave

      @savefile:
        lda #$00
        sta error_byte
        jsr rom_filesave_begin
        bcs @leave
        jsr rom_filesave_transfer_dir
        jsr rom_filesave_transfer_dir_size
        jsr rom_filesave_transfer_data
        
      @leave:
        php  ; save carry
        lda #$00
        sta internal_state
        jsr restore_zeropage
        plp
        lda error_byte
        jmp efs_bankout  ; ends with rts


    rom_filesave_chrin_prepare:
        ; size field pointer in filename_address and filename_length(bank)
        ; size in io_start_address, io_end_address low

/*        jsr rom_dirload_isrequested
        bcc @checkname
        lda #ERROR_MISSING_FILENAME
        sta error_byte
        sec
        bne @leave*/

      @checkname:
        ; assume certain filesize
        lda #$00
        sta io_start_address
        sta io_start_address + 1
        sta io_end_address
        lda #$20  ; ### assume ?
        sta io_end_address + 1

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

        ; prepare filesize
        jsr rom_filesave_begin
        bcs @leave
        jsr rom_filesave_transfer_dir
        jsr rom_filesave_transfer_data_prepare

      @leave:
        rts


    rom_filesave_chrin_close:
        jsr rom_config_prepare_config  ; first call to config

        jsr rom_filesave_transfer_dir_finish

        clc
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

        ; init erase sector call
        jsr efs_init_eapierasesector

        jsr rom_config_get_area_dirbank
        sta zp_var_x8

        ;jsr rom_config_get_area_mode
        lda #BANKING_MODE
        sta zp_var_x7

        lda #$80  ; for ll and lh
        sta zp_var_xa
;        lda zp_var_x7
;        cmp #$d4
;        bne :+
;        lda #$a0  ; for hh
;        sta zp_var_xa
;      :
        jsr rom_config_get_area_size
        lsr a
        lsr a
        lsr a
        tax

      @loop:
        lda zp_var_x8        
        ldy zp_var_xa
        jsr efs_io_byte

        ; mode lh
;        lda zp_var_x7  ; mode
;        cmp #$d0
;        bne @mode_ll_hh
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

;      @mode_ll_hh:
;        clc
;        lda #$08
;        adc zp_var_x8
;        sta zp_var_x8
;        ;bne @loopend

      @loopend:
        dex
        bne @loop

        ; mark the directory area
        jsr efs_init_eapiwrite

        jsr rom_config_get_area_dirbank
        jsr efs_setstartbank_ext

        lda #efs_directory::reserved
        tax
        jsr rom_config_get_area_dirhigh
        tay
        lda #$fe
        jsr efs_io_byte

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

        pla  ; old area
        jsr rom_flags_set_area

        jsr rom_config_get_area_dirbank
        sta efs_readef_bank

        ;jsr rom_config_get_area_addr_low
        lda #$00
        sta efs_readef_low
        jsr rom_config_get_area_dirhigh
        sta efs_readef_high

;        jsr rom_config_get_area_mode
;        lda #BANKING_MODE
;        sta efs_temp_var1

        ; prepare destination
        pla  ; new area
        jsr rom_config_get_area_filesbank_invert
        sta zp_var_x8
        jsr rom_config_get_area_dirbank_invert
        sta efs_temp_var2

        ;jsr rom_config_get_area_addr_low_invert
        lda #$00
        sta zp_var_x9  ; file pointer 
        sta zp_var_xe  ; dir pointer

        jsr rom_config_get_area_dirhigh_invert
        sta zp_var_xf  ; dir pointer
        jsr rom_config_get_area_fileshigh_invert
        clc
        adc #>DIRECTORY_SIZE  ; offset for files start
        sta zp_var_xa  ; file pointer

;        jsr rom_config_get_area_mode_invert
        lda #BANKING_MODE
        sta zp_var_x7

        ; start iterating through source directory
      @loop:
        jsr rom_config_get_area_dirhigh
        jsr efs_readef_dirboundary
        bcs @leave  ; directory out of bounds

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
        sta efs_readef_storedaddr_high
        jsr rom_config_get_area_fileshigh
        clc
        adc efs_readef_storedaddr_high
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

        jsr rom_config_call_defragment_warning  ; defragment warning

        ; copy directory
        jsr rom_defragment_copy_dir
        jsr rom_defragment_copy_data
        jmp @loop

      @skip:
        lda #24    ; next entry
        jsr efs_readef_pointer_advance
        jmp @loop

      @leave:
        jsr rom_config_call_defragment_allclear  ; defragment finished
        jsr efs_finish_tempvars
        clc
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
        ;jsr EAPIGetBank
        ;sta zp_var_x8  ; ### redundant ?

        jsr efs_readef_swap
        lda efs_temp_var2  ; has the destination directory bank
        jsr efs_setstartbank_ext

        clc
        rts


    rom_defragment_copy_data_destinc:
        ; increases dest file address according to mode (x7)
        ; inc to next position
        inc zp_var_x9  ; addr low
        bne @noinc

        jsr rom_config_call_defragment_warning  ; defragment warning

        ; inc page
        inc zp_var_xa  ; addr high
        lda zp_var_x7  ; mode
        and #$e0
        cmp zp_var_xa  ; addr high
        bne @noinc
        ; inc bank
        lda zp_var_x7  ; mode
        asl
        asl
        asl
        sta zp_var_xa  ; addr high
        inc zp_var_x8  ; bank
      @noinc:
        rts


    rom_defragment_copy_data_sourceinc:
        ; increases source file address according to mode (zp_var_x7)
        ; inc to next position
        inc efs_readef_low  ; addr low
        bne @noinc

        ; inc page
        inc efs_readef_high  ; addr high
        lda zp_var_x7    ; mode
        and #$e0
        cmp efs_readef_high  ; addr high
        bne @noinc
        ; inc bank
        lda zp_var_x7    ; mode
        asl
        asl
        asl
        sta efs_readef_high  ; addr high
        inc efs_readef_bank  ; bank
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
        jsr efs_init_eapireadinc

        ; rw areas available?
        jsr rom_config_rw_available   ; maybe check earlier?
        bcs @error

        ; init read_ef
        jsr rom_space_setdirstart

        ; check free space
        jsr rom_space_maxspace
        jsr rom_space_usedspace
        jsr rom_filesave_addsize
        jsr rom_filesave_checksize
        bcc @check1
        lda #ERROR_DISK_FULL
        jmp @error

      @check1:
        ; check file size zero
        jsr rom_filesave_checkzero
        bcs @error
        
      @check2:
        ; check conditions
        jsr rom_filesave_freedirentries  ; free disk entries
        bcs @defragment

        jsr rom_space_maxspace
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
        jsr efs_init_eapireadinc
        jsr rom_space_setdirstart   ; init readef

        ; check conditions again, this time error
        jsr rom_filesave_freedirentries  ; free disk entries
        lda #ERROR_DIRECTORY_ERROR
        bcs @error

        jsr rom_space_maxspace
        jsr rom_filesave_blockedspace  ; free space
        jsr rom_filesave_addsize
        jsr rom_filesave_checksize
        bcs @error

        lda #$00
        clc
        rts
      @error:
        sec
        sta error_byte
        rts


/*    rom_filesave_setdirstart:
        ; init read_ef
        jsr rom_config_get_area_bank
        sta efs_readef_bank
        jsr rom_config_get_area_addr_low
        sta efs_readef_low
        jsr rom_config_get_area_addr_high
        sta efs_readef_high
        rts*/


    rom_filesave_freedirentries:
        ; config must be set
        ; directory is set properly
        ; returns free directory entries in a
        ; the last entry does not count
        lda efs_readef_low
        pha
        lda efs_readef_high
        pha

        ldx #$ff  ; 255 free entries
        lda #16
        jsr efs_readef_pointer_advance

      @loop:
        dex
        beq @leave
        jsr efs_readef
        cmp #$ff
        beq @leave
        lda #24
        jsr efs_readef_pointer_advance
        jmp @loop

        ; reset directory
      @leave:
        pla
        sta efs_readef_high
        pla
        sta efs_readef_low

        txa
        bne @error

        lda #ERROR_DISK_FULL
        sec
        rts
      @error:
        lda #$00
        clc
        rts


/*    rom_filesave_subtractsize_blocks:
        ; checks used file in 3b/3c/3d
        ; against available size in 38/39/3a
        ; 38/39/3a - 3b/3c/3d -> 3b/3c/3d
        sec
        lda zp_var_x8
        sbc zp_var_xb
        sta zp_var_xb
        lda zp_var_x9
        sbc zp_var_xc
        sta zp_var_xc
        lda zp_var_xa
        sbc zp_var_xd
        sta zp_var_xd

        lda #$00
        sta zp_var_xb
        sec ; round down
        lda zp_var_xc
        sbc #$01
        sta zp_var_xc
        lda zp_var_xd
        sbc #$00
        sta zp_var_xd
        
        clc
        rts*/


    rom_filesave_checksize:
        ; checks used file in 3b/3c/3d 
        ; against available size in 38/39/3a
        ; val1 >= Val2
        ; 3b/3c/3d >= 38/39/3a
        lda zp_var_xd  ; Val1 +2    ; high bytes
        cmp zp_var_xa  ; Val2 +2
        bcc @LsThan    ; hiVal1 < hiVal2 --> Val1 < Val2
        bne @GrtEqu    ; hiVal1 != hiVal2 --> Val1 > Val2
        lda zp_var_xc  ; Val1 +1    ; high bytes
        cmp zp_var_x9  ; Val2 +1
        bcc @LsThan    ; hiVal1 < hiVal2 --> Val1 < Val2
        bne @GrtEqu    ; hiVal1 != hiVal2 --> Val1 > Val2
        lda zp_var_xb  ; Val1       ; low bytes
        cmp zp_var_x8  ; Val2
        ;beq @Equal     ; Val1 = Val2
        bcs @GrtEqu     ; loVal1 >= loVal2 --> Val1 >= Val2
      @LsThan:
        clc
        rts

      @GrtEqu:
        sec
        rts


    rom_filesave_checkzero:
        ; fill size: io_end_address - io_start_address
        lda io_end_address + 1    ; Val1 + 1    ; high bytes
        cmp io_start_address + 1  ; Val2 + 1
        bcc @LsThan    ; hiVal1 < hiVal2 --> Val1 < Val2
        bne @GrtEqu    ; hiVal1 != hiVal2 --> Val1 > Val2
        lda io_end_address        ; Val1       ; low bytes
        cmp io_start_address      ; Val2
        beq @Equal     ; Val1 = Val2
        ;bcs @GrtEqu     ; loVal1 >= loVal2 --> Val1 >= Val2
      @GrtEqu:
      @LsThan:
        clc
        rts

      @Equal:
        sec
        rts


    rom_filesave_addsize:
        ; fill size: io_end_address - io_start_address
        ; temp result in 3e/3f
        ; and add to 3b/3c/3d (low/mid/high)
        sec  ; calculate size
        lda io_end_address
        sbc io_start_address
        sta zp_var_xe
        lda io_end_address + 1
        sbc io_start_address + 1
        sta zp_var_xf

        clc  ; add load address
        lda #$02
        adc zp_var_xe
        sta zp_var_xe
        lda #$00
        adc zp_var_xf
        sta zp_var_xf

        clc  ; add to used space
        lda zp_var_xe
        adc zp_var_xb
        sta zp_var_xb
        lda zp_var_xf
        adc zp_var_xc
        sta zp_var_xc
        lda #$00
        adc zp_var_xd
        sta zp_var_xd

        rts


/*    rom_filesave_maxspace:
        ; config must be set
        ; returns max blocks in 38/39/3a (low/mid/high)
        ; one chip contains 32 pages
        jsr rom_config_get_area_size
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
        sbc #>DIRECTORY_SIZE
        sta zp_var_x9
        bcs :+
        dec zp_var_xa

      : rts*/


/*    rom_filesave_usedspace:
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
        lda #$00
        sta zp_var_xb
        sta zp_var_xc
        sta zp_var_xd

      @loop:
        jsr rom_config_get_area_addr_high
        jsr efs_readef_dirboundary
        bcs @leave  ; directory out of bounds
        jsr efs_readef
        cmp #$ff
        beq @leave
        and #$1f
        beq @skip
        lda #5  ; move to size
        jsr efs_readef_pointer_advance

        jsr efs_readef_read_and_inc
        clc
        adc zp_var_xb
        sta zp_var_xb
        jsr efs_readef_read_and_inc
        adc zp_var_xc
        sta zp_var_xc
        jsr efs_readef_read_and_inc
        adc zp_var_xd
        sta zp_var_xd

        lda #16
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
        jsr rom_config_get_area_dirhigh
        jsr efs_readef_dirboundary
        bcs @leave  ; directory out of bounds
        jsr efs_readef
        cmp #$ff
        beq @leave  ; leave
        lda #5  ; move to size
        jsr efs_readef_pointer_advance
        jsr efs_readef_read_and_inc
        clc
        adc zp_var_xb
        sta zp_var_xb
        jsr efs_readef_read_and_inc
        adc zp_var_xc
        sta zp_var_xc
        jsr efs_readef_read_and_inc
        adc zp_var_xd
        sta zp_var_xd
        lda #16
        jsr efs_readef_pointer_advance

        jmp @loop

        ; reset directory
      @leave:
        pla
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
        ;   3b/3c/3d: size
        ; parameter
        ;   fe/ff: name
        ;   io_start_address
        ;   io_end_address
        ;   filename_address
        ;   filename_length
        ; result
        jsr rom_config_prepare_config
        jsr efs_init_readef

        lda filename_length
        bne @next1
        lda #ERROR_MISSING_FILENAME
        jmp @error
 
        ; init read_ef
      @next1:
        jsr rom_config_get_area_dirbank
        sta efs_readef_bank
        sta zp_var_x8
        jsr efs_setstartbank_ext

        ;jsr rom_config_get_area_addr_low
        lda #$00
        sta efs_readef_low
        jsr rom_config_get_area_dirhigh
        sta efs_readef_high

        ; set file offset
        ;lda #<DIRECTORY_SIZE
        lda #$00
        sta zp_var_x9
        lda #>DIRECTORY_SIZE
        sta zp_var_xa

        jsr rom_filesave_nextentry
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

;        lda #BANKING_MODE
;        jsr rom_config_get_area_mode
;        cmp #$d0
;        beq @lhlh
;        cmp #$b0
;        beq @llll
;        cmp #$d4
;        beq @hhhh
;        lda #ERROR_DIRECTORY_ERROR
;        jmp @error

;      @lhlh:
        ; get bank from buffer for lhlh banking model
        asl zp_var_xd  ; high bits
        asl zp_var_xd

        lda zp_var_xc  ; low bits
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
;        jmp @next
;
;      @llll:
;      @hhhh:
;        ; get bank from buffer
;        asl zp_var_xd  ; high bits (3 shifts)
;        asl zp_var_xd
;        asl zp_var_xd
;
;        lda zp_var_xc  ; low bits (2)
;        and #$e0  ; mask %11100000
;        clc
;        ;rol
;        rol
;        rol
;        clc
;        adc zp_var_xd
;        adc zp_var_x8
;        sta zp_var_x8
;
;        lda zp_var_xc
;        and #$1f  ; mask %00011111
;        sta zp_var_xa
;
;        lda zp_var_xb
;        sta zp_var_x9
        ;jmp @next

        ; calculate size
;      @next:
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

      @error:
        sta error_byte
        sec
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
        lda #BANKING_MODE
        ;jsr rom_config_get_area_mode
        jsr EAPISetPtr        

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

        clc
        rts

    rom_filesave_transfer_dir_size:
        lda zp_var_xb
        jsr efs_io_byte
        lda zp_var_xc
        jsr efs_io_byte
        lda zp_var_xd
        jsr efs_io_byte

        clc
        rts


    rom_filesave_transfer_dir_finish:
        jsr efs_init_eapiwriteinc  ; repair dynamic code

        lda filename_length
        jsr efs_setstartbank_ext
        
        ldx filename_address
        ldy filename_address + 1
        ;jsr rom_config_get_area_mode
        lda #BANKING_MODE
        jsr EAPISetPtr

        lda io_start_address
        jsr efs_io_byte
        lda io_start_address + 1
        jsr efs_io_byte
        lda io_end_address
        jsr efs_io_byte

        clc
        rts


    rom_filesave_transfer_data_prepare:
        ; usage:
        ;   38: bank
        ;   39/3a: offset in bank (with $8000 added)
        clc
        lda efs_readef_low
        adc #21
        sta filename_address
        lda efs_readef_high
        adc #$00  ; add carry
        sta filename_address + 1
        jsr EAPIGetBank  
        sta filename_length

        ; get bank for overflow checking
        jsr rom_config_get_area_dirbank
        sta io_end_address + 1
        ;jsr rom_config_get_area_mode
;        lda #BANKING_MODE
;        cmp #$d0
;        beq @lhlh
;
;        jsr rom_config_get_area_size
;        clc
;        adc io_end_address + 1
;        and #%00111111  ; max bank
;        sta io_end_address + 1
;        jmp @continue
;
;      @lhlh:
        jsr rom_config_get_area_size
        lsr a
        clc
        adc io_end_address + 1
        and #%00111111  ; max bank
        sta io_end_address + 1

;      @continue:
        lda zp_var_x8
        jsr efs_setstartbank_ext

        jsr rom_config_get_area_fileshigh
        clc
        adc zp_var_xa
        tay
        ldx zp_var_x9
        ;jsr rom_config_get_area_mode
        lda #BANKING_MODE
        jsr EAPISetPtr

        ; prepare vars for filesize
        lda #$00
        sta io_start_address
        sta io_start_address + 1
        sta io_end_address
        ;sta io_end_address + 1

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
        
        jsr rom_config_get_area_fileshigh
        clc
        adc zp_var_xa
        tay
        ldx zp_var_x9
        ;jsr rom_config_get_area_mode
        lda #BANKING_MODE
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
        inc zp_var_xe
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
        ; no out of bounds check, has been done in confitions check
        ; result of last file
        ;   38: bank
        ;   39/3a: offset in bank (without $8000 added)
        ;   x/y: address of next dir entry
        lda #16
        jsr efs_readef_pointer_advance

      @loop:
;        jsr rom_config_get_area_addr_high
;        clc
;        adc #24  ; last entry must stay empty
;        jsr efs_readef_dirboundary
;        bcs @error16  ; directory out of bounds
        jsr efs_readef_read_and_inc
        cmp #$ff
        beq @leave17
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

;      @error16:
;        lda #16    ; to directory begin
;        jsr efs_readef_pointer_reverse
;        sec
;        rts
      @leave17:
        lda #17    ; to directory entry begin
        jsr efs_readef_pointer_reverse
        clc
        rts



; --------------------------------------------------------------------
; commands processing functions
; usage:
;  35/36: configuration pointer
;     38: command
;  3e/3f: pointer to name
; return:

    rom_command_save_process:
        ; .C set: error (.Z set) or stop processing (.Z clear)
        ; .C clear: no error and continue
        ; error_byte: error code
        ; commands in save can continue
        lda zp_var_x8
        cmp #$40    ; '@', overwrite
        bne @next1
        jsr efs_directory_search
        bcs :+      ; not found, ignore
        jsr rom_scratch_process
      : lda #$00    ; no error
        sta error_byte
        clc         ; continue after
        rts

      @next1:
        lda #ERROR_SYNTAX_ERROR_30
        sta error_byte
        sec
        rts


    rom_scratch_process:
        ; configuration is at the correct area
        ; efs_readef must be at the correct position
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
        jsr rom_config_get_area_dirbank
        jsr efs_setstartbank_ext

        ;jsr rom_config_get_area_mode
        lda #BANKING_MODE
        ldx efs_readef_low
        ldy efs_readef_high
        jsr EAPISetPtr

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

