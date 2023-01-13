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

;.define version
;.include "../../version.txt"
; configuration
;ZEROPAGE_SIZE .set 9
;GENERIC_COMMAND_SIZE .set 14


.import __EFS_RAM1_LOAD__
.import __EFS_RAM1_RUN__
.import __EFS_RAM1_SIZE__

.import __EFS_RAM2_LOAD__
.import __EFS_RAM2_RUN__
.import __EFS_RAM2_SIZE__

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
;.import efs_device

.import efs_io_byte
.import efs_generic_command
.import efs_bankin
.import efs_bankout
.import efs_enter_pha
.import efs_enter

.export rom_chrout_body
.export rom_save_body
.export rom_chrin_body
.export rom_close_body
.export rom_open_body
.export rom_load_body
.export rom_setnam_body
.export rom_setlfs_body



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
        jmp $ffff

    EFS_init_YYY: ; @ $800c
        jmp $ffff

    efs_magic: ; @ $800f
    efs_default_config:
        .byte "libefs"
        .byte major_version, minor_version, patch_version

        .byte $01
        .byte $00, $00, $a0, $d0, $00  ; area 0: bank 0, $a000, mode lhlh, unlimited
        .byte $00, $00, $00, $00, $00  ; area 1: none
        .byte $00, $00, $00, $00, $00  ; area 2: none
        .byte $00, $00, $00            ; defragment: no
        .byte $00, $00, $00, $00  ; dummy

    efs_config_size = * - efs_default_config
    .if efs_call_size <> 32
    .error "efs config size mismatch"
    .endif

        .byte $00

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
    :   lda $ff - ZEROPAGE_SIZE + 1, x
        sta backup_zeropage_data, x
        dex
        bpl :-
        rts

    restore_zeropage:
        ldx #ZEROPAGE_SIZE - 1  ; restore zp
    :   lda backup_zeropage_data, x
        sta $ff - ZEROPAGE_SIZE + 1, x
        dex
        bpl :-
        rts


    efs_init_body:
        ; copy code to df00
        ldx #<__EFS_RAM1_SIZE__ - 1
    :   lda __EFS_RAM1_LOAD__,x
        sta __EFS_RAM1_RUN__,x
        dex
        bpl :-
        clc

        clc
        rts


    efs_init_minieapi_body:
        ; copy code to df80
        ldx #<__EFS_RAM2_SIZE__ - 1
    :   lda __EFS_RAM2_LOAD__,x
        sta __EFS_RAM2_RUN__,x
        dex
        bpl :-
        clc
        rts


    efs_init_eapi_body:
        tax

        lda $65
        cmp $b800
        bne @error
        lda $61
        cmp $b801
        bne @error
        lda $70
        cmp $b802
        bne @error
        lda $69
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
        lda ($fe), y  ; read from memory
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
        lda $8000  ; read from banked memory
        jmp efs_enter_pha
      @codeend:
      .if (@codeend - @code) > GENERIC_COMMAND_SIZE
      .error "dynamic code readef to large"
      .endif

    efs_readef = efs_generic_command
    efs_readef_low = efs_generic_command + 7
    efs_readef_high = efs_generic_command + 8


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


; --------------------------------------------------------------------
; efs body functions
; need to leave with 'jmp efs_bankout'
; zerpage usage only after zeropage backup

    rom_setlfs_body:
        ;stx efs_device
        ;lda #$00
        cpy #$00
        bne :+    ; zero => relocate
        lda #LIBEFS_FLAGS_RELOCATE
      : sta efs_flags
        jmp efs_bankout  ; ends with rts


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
        beq @dircheck
        lda #ERROR_FILE_OPEN
        sta error_byte
        sec
        bne @leave

      @dircheck:
        jsr rom_directory_list_check
        bcc @dirfind
        lda #%01000000  ; directory processing
        sta internal_state
        jsr rom_dirload_begin
        clc
        jmp @leave

      @dirfind:
        jsr rom_directory_find
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
        jsr rom_directory_list_check
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
        jsr rom_directory_find
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
; efs load and verify functions
; parameter:
;   f8: bank
;   f9/fa: offset in bank (with $8000 added)
;   fb/fc/fd: size
; using
;   f7: temporary
;   fe/ff: pointer to data
; 
    rom_fileload_begin:
        jsr efs_init_eapireadinc  ; repair dynamic code

        ; directory entry
        ldx $f9  ; efs_directory_entry + efs_directory::offset_low
        lda $fa  ; efs_directory_entry + efs_directory::offset_high
        clc
        adc #$80
        tay
        lda #$d0  ; eapi bank mode
        jsr EAPISetPtr

        ldx $fb  ; efs_directory_entry + efs_directory::size_low
        ldy $fc  ; efs_directory_entry + efs_directory::size_high
        lda $fd  ; efs_directory_entry + efs_directory::size_upper
        jsr EAPISetLen

        jsr efs_init_setstartbank
        lda $f8  ; efs_directory_entry + efs_directory::bank
        jsr efs_generic_command

        rts


    rom_fileload_address:
        jsr efs_io_byte ; load address
        sta $fe
        jsr efs_io_byte
        sta $ff
        ;lda efs_secondary  ; 0=load to X/Y, 1=load to prg address
        lda #LIBEFS_FLAGS_RELOCATE
        bit efs_flags
        bne :+              ; set: load to X/Y, clear: no relocate
        jmp :++
      : lda io_start_address  ; load to relocation address (X/Y)
        sta $fe
        lda io_start_address + 1
        sta $ff

      : lda $fe
        sta io_start_address
        lda $ff
        sta io_start_address + 1

        rts


    rom_fileload_transfer:
        ldy #$00
      @loop:
        jsr efs_io_byte
        bcs @eof
        sta ($fe), y
        iny
        bne @loop
        inc $ff
        jmp @loop

      @eof:
        clc
        tya
        adc $fe
        sta $fe
        bcc :+
        inc $ff
      : lda $fe
        bne :+
        dec $ff
      : dec $fe
     
        lda #$40
        sta status_byte

        lda $fe
        sta io_end_address
        lda $ff
        sta io_end_address + 1

        clc
        rts


    rom_fileload_verify:
        jsr efs_init_readmem  ; prepare verify command
        ldy #$00
      @loop:
        jsr efs_io_byte
        bcs @eof  ; eof
        sta $f7
        jsr efs_generic_command
        cmp $f7
        bne @mismatch
        iny
        bne @loop
        inc $ff
        jmp @loop

      @eof:
        lda #$40
        sta status_byte
        lda $fe  ; verify successful, reduce address by one
        bne :+
        dec $ff
      : dec $fe
        jmp @leave

      @mismatch:
        lda #$10
        sta status_byte
        
      @leave:
        clc
        tya
        adc $fe
        sta $fe
        bcc :+
        inc $ff

      : lda $fe
        sta io_end_address
        lda $ff
        sta io_end_address + 1

        lda status_byte
        and #$10
        bne :+
        clc
        rts
      : sec
        rts



; --------------------------------------------------------------------
; directory list functions
; usage:
;   f7: temporary state machine state
;   f8/f9: temporary file size
;   fa: temporary variable
;   fc/fd: address to state maching processing function
;   fe/ff: pointer to destination / pointer to filename
;   io_end_address: state machine state
;   io_end_address + 1: state machine variable

    dirload_state_var = io_end_address + 1

    rom_directory_list_check:
        lda filename_address
        sta $fe
        lda filename_address + 1
        sta $ff

        ldy #$00
        lda #$24        ; '$'
        cmp ($fe), y     ; no fit
        bne :+

        sec
        rts
      : clc
        rts


    rom_dirload_begin:
        jsr efs_init_setstartbank
        lda #$00  ; ### 0, could be different bank CONFIG ###
        jsr efs_generic_command

        ; set read code
        jsr efs_init_readef
        lda #$00
        sta efs_readef_low
        lda #$a0
        sta efs_readef_high

        lda internal_state
        and #$c0
        ora #$01
        sta internal_state
        lda #$01
        ;sta dirload_state
        sta $f7
        lda #$00
        sta dirload_state_var
        rts


    rom_dirload_address:
        lda #$01
        sta $fe
        lda #$04
        sta $ff
        ;lda efs_secondary  ; 0=load to X/Y, 1=load to prg address
        lda #LIBEFS_FLAGS_RELOCATE
        bit efs_flags
        bne :+              ; set: load to X/Y, clear: no relocate
        jmp :++
      : lda io_start_address  ; load to relocation address (X/Y)
        sta $fe
        lda io_start_address + 1
        sta $ff

      : lda $fe
        sta io_start_address
        lda $ff
        sta io_start_address + 1

        rts


    rom_dirload_chrin:
        jsr backup_zeropage
        lda internal_state
        and #$3f  ; remove the upper bits
        sta $f7
      @again:
        jsr rom_dirload_next_byte
        tay
        lda internal_state
        and #$c0    ; only take the upper bits
        ora $f7     ; or the state
        sta internal_state
        lda $f7     ; check if state is zero
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
        ldx $f7
        beq @eof   ; state 0 means end
        bcs @loop  ; C set, skip writing and repeat
        sta ($fe), y
        iny
        bne @loop
        inc $ff
        jmp @loop

      @eof:
        clc
        tya
        adc $fe
        sta $fe
        bcc :+
        inc $ff
      : lda $fe
        bne :+
        dec $ff
      : dec $fe

        lda #$40
        sta status_byte
        lda #$00
        sta internal_state  ; must be reset here

        lda $fe
        sta io_end_address
        lda $ff
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
        lda $f7
        asl
        tax
        lda rom_dirload_statemachine, x
        sta $fc
        lda rom_dirload_statemachine + 1, x
        sta $fd
        clc
        jmp ($00fc)

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
        .addr rom_dirload_sm_type_begin    ; 36
        .addr rom_dirload_sm_type_next     ; 37
        .addr rom_dirload_sm_type_next     ; 38
        .addr rom_dirload_sm_type_next     ; 39
        .addr rom_dirload_sm_writeprot     ; 40
        .addr rom_dirload_sm_space         ; 41
        .addr rom_dirload_sm_space         ; 42
        .addr rom_dirload_sm_linenend      ; 43


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
        ; ### other areas
        lda #$3c  ; '<'
        inc $f7
        clc
        rts

    rom_dirload_sm_finish:
        ; finish does not produce a byte
        lda #$00
        sta $f7
        clc
        rts

    rom_dirload_sm_skip:
        lda #$00
        sta dirload_state_var
        inc $f7
        sec
        rts

    rom_dirload_sm_space:
        lda #$20
        inc $f7
        rts

    rom_dirload_sm_linenend:
        ; produces $00 and decides if new filename
        ; if filename -> 20
        ; if finish -> 15
        lda #16  ; pointer starts at begin of dir entry
        jsr dir_pointer_advance
        bcs :+  ; directory terminates
        jsr efs_readef
        ; ### test hidden
        and #%00011111  ; mask out hidden and reserved flag fields
        sta $fa
        bne :+  ; is file invalid
        lda #8  ; invalid
        jsr dir_pointer_advance
        jmp rom_dirload_sm_linenend

      : lda $fa  ; terminator ?
        cmp #$1f
        bne :+
        lda #sm_finish  ; finish directory
        sta $f7
        lda #$00
        clc
        rts

      : lda #sm_nextfile  ; go to file line
        sta $f7
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
      : inc $f7
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
      : inc $f7
        rts*/


    rom_dirload_sm_addresslow:
        lda io_start_address
        inc $f7
        rts

    rom_dirload_sm_addresshigh:
        lda io_start_address + 1
        inc $f7
        rts

    rom_dirload_sm_addrdummy:
        lda #$00
        sta dirload_state_var
        lda #$01
        inc $f7
        rts

    rom_dirload_sm_zero:
        lda #$00
        inc $f7
        rts

    rom_dirload_sm_reverseon:
        lda #$12
        inc $f7
        rts

    rom_dirload_sm_quotationmark:
        lda #$00
        sta dirload_state_var
        lda #$22
        inc $f7
        rts

    rom_dirload_sm_diskname:
        ldx dirload_state_var
        lda rom_dirload_diskname_text, x
        inc dirload_state_var
        cpx #rom_dirload_diskname_textlen
        bne :+
        inc $f7
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
        inc $f7
        ldx #$00
        stx dirload_state_var
      : clc
        rts

    rom_dirload_sm_filename:
        ; pointer is at the name
        ldx dirload_state_var
        jsr dir_read_and_pointer_inc
        bne :+
        lda #$20  ; space if 0 char
      : inc dirload_state_var
        cpx #15
        bne :+
        inc $f7
        ldx #$00
        stx dirload_state_var
        
      : clc
        rts

    rom_dirload_sm_sizelow:
        ; pointer is at flags
        lda #5  ; advance to size low
        jsr dir_pointer_advance
        jsr dir_read_and_pointer_inc  ; size low
        beq :+
        lda #$01
      : sta $f8  ; a is 0 after branch
        jsr efs_readef  ; read mid
        clc
        adc $f8
        inc $f7
        rts


    rom_compare16:
        ; A: high value
        ; X: low value
        ; val1(X/A) >= Val2(f8/f9) => C set
        ; https://codebase64.org/doku.php?id=base:16-bit_comparison
        ; a            ; Val1 high
        cmp $f9        ; Val2 high
        bcc @LsThan    ; hiVal1 < hiVal2 --> Val1 < Val2
        bne @GrtEqu    ; hiVal1 != hiVal2 --> Val1 > Val2
        txa            ; Val1 low
        cmp $f8        ; Val2 low
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
        jsr dir_pointer_dec
        jsr dir_read_and_pointer_inc  ;low
        beq :+
        lda #$01
      : sta $f8  ; a is zero iafter branch
        jsr dir_read_and_pointer_inc  ;mid
        clc
        adc $f8
        sta $f8
        lda #$00
        sta $f9
        jsr efs_readef ; high
        adc $f9
        sta $f9

        inc $f7
        lda #23  ; reverse pointer to name
        jsr dir_pointer_reverse

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
        lda $f9
        clc
        rts


    rom_dirload_sm_sizeskip:
        lda dirload_state_var
        bne :+
        inc $f7
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
        jsr dir_pointer_advance
        ; no return here

    rom_dirload_sm_type_next:
        lda dirload_state_var
        inc dirload_state_var
        tax
        lda rom_dirload_types_text, x
        inc $f7
        clc
        rts


    rom_dirload_sm_freelow:
        ; calculate the free blocks
        ; ### other area  
        ; in area 0 nothing free
        lda #$00
        sta dirload_state_var
        inc $f7
        clc
        rts

    rom_dirload_sm_freehigh:
        lda dirload_state_var
        inc $f7
        clc
        rts


; --------------------------------------------------------------------
; directory search functions
; usage:
;   f7: name check result
;   fe/ff: pointer to name
; return:
;   f8: bank
;   f9/fa: offset in bank (with $8000 added)
;   fb/fc/fd: size

;    dir_read_byte_low = efs_io_byte + 1
;    dir_read_byte_high = efs_io_byte + 2

    dir_namecheck_result = $f7
    dir_name_pointer = $fe
    dir_directory_entry = $fb

    dir_read_and_pointer_inc:
        jsr efs_readef
        pha
        jsr dir_pointer_inc
        pla
        rts

    dir_pointer_inc:
        ; ### check if pointer leaves directory
        inc efs_readef_low
        bne :+
        inc efs_readef_high
      : lda efs_readef_high
        cmp #$b8  ; directory over ### configuration
        rts

    dir_pointer_dec:
        ; ### check if pointer leaves directory
        lda efs_readef_low
        bne :+
        dec efs_readef_high
      : dec efs_readef_low
        rts

    dir_pointer_advance:
        ; ### check if pointer leaves directory
        clc
        adc efs_readef_low
        sta efs_readef_low
        bcc :+
        inc efs_readef_high
      : lda efs_readef_high
        cmp #$b8  ; directory over ### configuration
        rts
        

    dir_pointer_reverse:
        ; ### check if pointer leaves directory
        tax
        lda efs_readef_low
        stx efs_readef_low
        sec
        sbc efs_readef_low
        sta efs_readef_low
        bcs :+
        dec efs_readef_high
      : lda efs_readef_high
        cmp #$b8  ; directory over ### configuration
        rts


    rom_directory_filedata:
        ; position is at flags, bank is the next data to load
        ; all zp variables are free and can be used
        jsr dir_read_and_pointer_inc  ; efs_io_byte  ; bank
        sta $f8
        jsr dir_read_and_pointer_inc  ; efs_io_byte  ; bank high

        ; offset
        jsr dir_read_and_pointer_inc  ; efs_io_byte
        sta $f9
        jsr dir_read_and_pointer_inc  ; efs_io_byte
        ; memory offset will be added later
        sta $fa

        ; size
        jsr dir_read_and_pointer_inc  ; efs_io_byte
        sta $fb
        jsr dir_read_and_pointer_inc  ; efs_io_byte
        sta $fc
        jsr dir_read_and_pointer_inc  ; efs_io_byte
        sta $fd

        rts


    rom_directory_begin_search:
        ; set pointer and length of directory
;        lda #$d0
;        ldx #$00  ; $A000
;        ldy #$a0  ; $A000
;        jsr EAPISetPtr
;        ldx #$00
;        ldy #$18  ; $1800 bytes, could be $2000
;        lda #$00
;        jsr EAPISetLen
        jsr efs_init_setstartbank
        lda #$00  ; ### 0, could be different bank
        jsr efs_generic_command

        ; set read code
        jsr efs_init_readef
        lda #$00  ; ### efs dir
        sta efs_readef_low
        lda #$a0  ; ### efs dir (usually $a0 or $80)
        sta efs_readef_high

        rts


    rom_directory_checkname:
        ; compare filename
        ; name is in (fe/ff)
        ldy #$00
        ldx #$00
      @loop:
        jsr dir_read_and_pointer_inc  ; efs_io_byte    ; load next char
        sta dir_directory_entry
        inx
        
        lda #$2a             ; '*'
        cmp (dir_name_pointer), y  ; character in name is '*', we have a match
        beq @match
        lda #$3f             ; '?'
        cmp (dir_name_pointer), y  ; character in name is '?', the char fits
        beq @fit
        lda (dir_name_pointer), y  ; compare character with character in entry
        cmp dir_directory_entry  ; if not equal nextname
        bne @next
      @fit:
        iny
        cpy filename_length  ; name length check
        bne @loop            ; more characters
        cpy #$10             ; full name length reached
        beq @match           ;   -> match
        jsr dir_read_and_pointer_inc  ; efs_io_byte    ; load next char
        sta dir_directory_entry
        inx
        lda dir_directory_entry  ; if == \0
        beq @match           ;   -> match
                             ; length check failed
      @next:
        cpx #$10
        beq :+
        jsr dir_read_and_pointer_inc  ; efs_io_byte    ; load next char
        inx
        bne @next
      : lda #$00
        sta dir_namecheck_result
        rts

      @match:
        cpx #$10
        beq :+
        jsr dir_read_and_pointer_inc  ; efs_io_byte    ; load next char
        inx
        bne @match
      : lda #$01
        sta dir_namecheck_result
        rts


    rom_directory_is_terminator:
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



    rom_directory_find:
        lda filename_address
        sta dir_name_pointer
        lda filename_address + 1
        sta dir_name_pointer + 1
        jsr rom_directory_begin_search

        lda filename_length
        bne @repeat
        lda #$08       ; no filename: status=0, error=8, C
        bne @error      ; jmp to error

      @repeat:
        ; checkname
        jsr rom_directory_checkname

        ; test if more entries
        jsr dir_read_and_pointer_inc  ; efs_io_byte    ; load next char
        bcs @error4
        jsr rom_directory_is_terminator
        bcc @next      ; if not terminator entry (C clear) next check
      @error4:
        lda #$04       ; file not found: status=0, error=4, C
      @error:
        sta error_byte
        sec
        rts

      @next:
        ; test if hidden ###

        lda dir_namecheck_result
        bne @match
        lda #$07
        jsr dir_pointer_advance
        jmp @repeat

      @match:
        ; found, read file info
        jsr rom_directory_filedata
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
;        lda efs_directory_entry + efs_directory::flags
        beq nextname    ; if deleted go directly to next name

        ; compare filename
        ldy #$00
      nameloop:
        lda #$2a   ; '*'
        cmp ($fe), y  ; character in name is '*', we have a match
        beq namematch
        lda ($fe), y  ; compare character with character in entry
        cmp efs_directory_entry, y     ; if not equal nextname
        bne nextname
        iny
        cpy filename_length        ; name length check
        bne nameloop               ; more characters
        cpy #$10                   ; full name length reached
        beq namematch              ;   -> match
        lda efs_directory_entry, y     ; character after length is zero
        beq namematch              ;   -> match
        jmp nextname               ; length check failed

      namematch:
        clc
        rts
*/

