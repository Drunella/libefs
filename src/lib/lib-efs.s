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

; call $8000 (EFS_init) to initialize
; you need to bank in bank 0 at least in 8k mode
; init code
;   lda #$37
;   sta $01
;   lda #$80 | $07  ; led, 16k mode
;   sta $de02
;   lda #$00        ; EFSLIB_ROM_BANK
;   sta $de00
;   jsr $8000       ; _efs_init

; ### implement conditional switches for non rom version


.feature c_comments
.localchar '@'

.include "lib-efs.i"

;.define version
;.include "../../version.txt"
; configuration
ZEROPAGE_SIZE .set 9
GENERIC_COMMAND_SIZE .set 12


.export EFS_init
.export EFS_setlfs
.export EFS_setnam
.export EFS_load
.export EFS_save
.export EFS_readst


.import __EFS_RAM_LOAD__
.import __EFS_RAM_RUN__
.import __EFS_RAM_SIZE__

;.import __EFS_REL_LOAD__
;.import __EFS_REL_RUN__
;.import __EFS_REL_SIZE__


.segment "EFS_RAM"

; --------------------------------------------------------------------
; efs jump table

    EFS_setlfs:  ; @ $DF00
        ; parameter:
        ;    X: number of efs structure; 
        ;    Y: secondary address (0: relocate)
        ; return: none
        jsr efs_bankin
        jmp rom_setlfs_body

    EFS_setnam:  ; @ $DF06
        ; parameter:
        ;    A: name length 
        ;    X: name address low
        ;    Y: name address high
        ; return: none
        jsr efs_bankin
        jmp rom_setnam_body

    EFS_load:    ; @ $DF0C
        ; parameter:
        ;    A: 0=load, 1-255=verify
        ;    X: load address low 
        ;    Y: load address high
        ; return: 
        ;    A: error code
        ;    X: end address low
        ;    Y: end address high
        ;    .C: 1 if error
        ; error:
        ;    $02: file open
        ;    $04: file not found
        ;    $05: device not present (?)
        ;    $08: missing filename
        jsr efs_bankin
        jmp rom_load_body

    EFS_open:    ; @ $DF12
        ; parameter: none
        ; return:
        ;    A: error code
        ;    .C: 1 if error
        ; error:
        ;    $02: file open
        ;    $04: file not found
        ;    $05: device not present (?)
        ;    $08: missing filename
        jsr efs_bankin
        jmp rom_open_body

    EFS_close:   ; @ $DF18
        ; parameter: none
        ; return:
        ;    A: error code
        ;    .C: 1 if error
        ; error:
        ;    $02: file not open
        jsr efs_bankin
        jmp rom_close_body

    EFS_chrin:   ; @ $DF1E
        ; parameter: none
        ; return:
        ;    A: character or error code
        ;    .C: 1 if error
        ; error:
        ;    $03: file not open
        ;    $05: device not present (?)
        jsr efs_bankin
        jmp rom_chrin_body

    EFS_save:    ; @ $DF24
        ; parameter:
        ;    A: z-page to start address
        ;    X: end address low
        ;    Y: end address high
        ; return:
        ;    A: error code
        ;    .C: 1 if error
        jsr efs_bankin
        jmp rom_save_body

    EFS_chrout: ; @ $DF2A
        ; parameter:
        ;    A: character
        ; return:
        ;    .C: 1 if error
        jsr efs_bankin
        jmp rom_chrout_body

    EFS_readst:  ; @ $DF30
        ; parameter: none
        ; return:
        ;    A: status code ($10: verify mismatch; $40: EOF; $80: device not present)
        lda status_byte
        rts
        ;jsr efs_bankin
        ;jmp rom_readst_body


; --------------------------------------------------------------------
; efs wrapper function that need to switch banks

    efs_bankin:
        ; changes status: N, Z
        ; does not work with disabled io area
        ; 13 bytes
        pha
        lda $01  ; save memory config
        sta backup_memory_config
        lda #$37  ; bank to rom area
        sta $01
        bne efs_enter

    efs_bankout:
        ; changes status: N, Z
        ; does not work with disabled io area
        ; 13 bytes
        pha
        lda backup_memory_config  ; restore memory config
        sta $01
        lda #EASYFLASH_KILL
        sta EASYFLASH_CONTROL
        pla
        rts

        ; variable code area
        ; 15 bytes
    efs_generic_command:

        .repeat GENERIC_COMMAND_SIZE
        .byte $60
        .endrepeat

;    efs_set_startbank:
        ; safest way to set eapi shadow bank
        ; A: bank
        ; 6 bytes
;        jsr EAPISetBank
;        jmp efs_enter_pha

;    efs_verify_byte:
;        jmp efs_return  ; rel_verify_byte

;    efs_write_byte:
;        jmp efs_return  ; rel_write_byte


    efs_io_byte:
        ; load byte in A
        ; 3 bytes
        ; lda $ffff  ; $ad, $ff, $ff
        ; jsr EAPIWriteFlashInc  ; $20, <EAPIWriteFlashInc, >EAPIWriteFlashInc
        jsr EAPIReadFlashInc  ; $20, <EAPIReadFlashInc, >EAPIReadFlashInc

    efs_enter_pha:
        ; changes status: N, Z
        ; 1 byte
        pha

    efs_enter:
        lda #EASYFLASH_LED | EASYFLASH_16K
        sta EASYFLASH_CONTROL
        lda #EFSLIB_ROM_BANK
        sta EASYFLASH_BANK
        pla

    efs_return:
        rts


; --------------------------------------------------------------------
; efs data

    backup_zeropage_data:
        .repeat ZEROPAGE_SIZE
        .byte $00
        .endrepeat

    libefs_configuration:
        .byte $00  ; $00: read only; bit 0: includes verify; bit 1: includes write

    backup_memory_config: ; exclusive usage
        .byte $00

    status_byte:  ; exclusive usage
        .byte $00

    error_byte:  ; exclusive usage
        .byte $00

    efs_flags:  ; exclusive usage
        .byte $00

    internal_state:  ; exclusive usage
        .byte $00    ; stores, open, closed, open, verify, read directory

    filename_address:
        .word $0000

    filename_length:
        .byte $00

    io_start_address:
        .word $0000

    io_end_address:
        .word $0000

    efs_device:
        .byte $00



.segment "EFS_REL"

    ; 15 byte: read and verify
/*
    rel_verify_byte_offset = rel_verify_byte - __EFS_REL_RUN__
    rel_verify_byte:
        ; 15 bytes
        jsr efs_bankout
        lda ($fe), y  ; read from memory
        ldx #$37
        stx $01
        jmp efs_enter_pha
        nop
        nop
        nop
*/       

/*
    rel_verify_byte_offset = rel_verify_byte - __EFS_REL_RUN__
    rel_verify_byte:
        ; 25 bytes
        pha
        lda backup_memory_config  ; restore memory config
        sta $01
        lda #EASYFLASH_KILL
        sta EASYFLASH_CONTROL
        pla
        
        cmp ($fe), y  ; ### jump to additional verify routine

        php        
        lda #$37
        sta $01
        lda #EASYFLASH_LED | EASYFLASH_16K
        sta EASYFLASH_CONTROL
        plp

        rts


    rel_write_byte_offset = ~rel_write_byte - __EFS_REL_RUN__
    rel_write_byte:
        ; 25 bytes
        lda backup_memory_config  ; restore memory config
        sta $01
        lda #EASYFLASH_KILL
        sta EASYFLASH_CONTROL

        jsr EAPIWriteFlashInc

        pha
        lda #$37
        sta $01
        lda #EASYFLASH_LED | EASYFLASH_16K
        sta EASYFLASH_CONTROL
        pla

        rts
*/


.segment "EFS_CALL"

; --------------------------------------------------------------------
; efs rom jump table
; 3 bytes jmp
; 10 byte magic & version
; 3 byte filler

    EFS_init:
        ; parameter:
        ;    A: configuration
        ;       $00: read only; 
        ;       bit0: includes verify
        ;       bit1: includes write
        ;    X/Y: relocation address
        ; return:
        ;    .C: 1 if error
        jmp efs_init_body

    efs_magic:
      .byte "lib-efs"
      .byte 0, 1, 0  ; ### read from version.txt
      .byte $ff, $ff, $ff



.segment "EFS_ROM"

; --------------------------------------------------------------------
; efs: init and utility function bodies
; $f9: temporary variable
; $fa/fb: source/destination address
; $fc
; $fd
; $fe/ff: temporary pointer

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


    efs_set_eapiread:
        lda #$ad  ; lda
        sta efs_io_byte
        lda #$00
        sta efs_io_byte + 1
        lda #$a0
        sta efs_io_byte + 2
        rts

    efs_set_eapireadinc:
        lda #$20  ; jsr
        sta efs_io_byte
        lda #<EAPIReadFlashInc
        sta efs_io_byte + 1
        lda #>EAPIReadFlashInc
        sta efs_io_byte + 2
        rts


    efs_init_body:
        pha  ; libefs_configuration
        tya
        pha  ; high
        txa
        pha  ; low

        ; copy code to df00
        ldx #<__EFS_RAM_SIZE__ - 1
    :   lda __EFS_RAM_LOAD__,x
        sta __EFS_RAM_RUN__,x
        dex
        bpl :-
        clc

        pla  ; ###
        pla  ; ###
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
*/
        pla  ; config
        sta libefs_configuration
/*
        beq :+
        ; copy code to X/Y
        ldy #<__EFS_REL_SIZE__ - 1
      : lda __EFS_REL_LOAD__, y
        sta ($fe), y
        dey
        bpl :-
*/
        clc

        rts


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


; --------------------------------------------------------------------
; efs body funtions
; need to leave with 'jmp efs_bankout'

;    rom_readst_body:
;        lda status_byte
;        jmp efs_bankout  ; ends with rts


    rom_setlfs_body:
        stx efs_device
        lda #$00
        cpy #$00
        bne :+    ; zero => relocate
        lda #LIBEFS_FLAGS_RELOCATE
      : sta efs_flags
;      : lda #LIBEFS_FLAGS_RELOCATE
;        sty efs_secondary
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
        ; ### try not to use zeropage
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
        lda internal_state
        cmp #$01
        bne @dirop       
        jsr efs_io_byte  ; read file
        bcc @done
        lda #STATUS_EOF
        sta status_byte
        lda #$00
        beq @done

      @dirop:
        lda internal_state
        cmp #$02
        bne @error
        ; read dir ###
        sec             ; ###
        lda #ERROR_DEVICE_NOT_PRESENT        ; ###
        sta status_byte ; ###
        jmp @done

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
        lda #ERROR_DEVICE_NOT_PRESENT
        sta error_byte
        sec
        ; process directory preparation ###
        jmp @leave

      @dirfind:
        jsr rom_directory_find
        bcs @leave ; not found

        jsr rom_fileload_begin
        jsr rom_fileload_address

        lda #$01
        sta internal_state
        clc

      @leave:
        php  ; save carry
        jsr restore_zeropage
        lda error_byte
        plp
        jsr restore_zeropage
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
        bcc @dirfind
        ; process directory ###
        lda #ERROR_DEVICE_NOT_PRESENT
        sta error_byte
        sec
        jmp @leave

      @dirfind:
        jsr rom_directory_find
        bcs @leave ; not found

        jsr rom_fileload_begin
        jsr rom_fileload_address

        ;lda efs_verify ###
        lda efs_flags
        and #LIBEFS_FLAGS_VERIFY  ; set: verify, clear: load
        bne @verify
        
        jsr rom_fileload_transfer
        jmp @leave
      @verify:
        lda libefs_configuration
        and #LIBEFS_CONFIG_VERIFY  ;  verify possible
        bne @verifyok
        lda #ERROR_DEVICE_NOT_PRESENT
        sta error_byte
        sec
        jmp @leave

      @verifyok:
        jsr rom_fileload_verify

      @leave:
        php  ; save carry
        jsr restore_zeropage

        ldx io_end_address
        ldy io_end_address + 1
        lda error_byte

        plp
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

;        jsr rom_save_execute
        sec  ; ###
        lda #ERROR_DEVICE_NOT_PRESENT
        sta error_byte

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
;   fe/ff: pointer to name
; return:

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


; ### single directory byte ###


; --------------------------------------------------------------------
; directory search functions
; usage:
;   f7: name check result
;   fb: current content of directory entry
;   fc: 
;   fe/ff: pointer to name
; return:
;   f8: bank
;   f9/fa: offset in bank (with $8000 added)
;   fb/fc/fd: size

    dir_read_byte_low = efs_io_byte + 1
    dir_read_byte_high = efs_io_byte + 2

    dir_namecheck_result = $f7
    dir_name_pointer = $fe
    dir_directory_entry = $fb

    dir_set_eapiread:
        lda #$ad
        sta efs_io_byte
        rts

    dir_pointer_advance:
        clc
        adc dir_read_byte_low
        sta dir_read_byte_low
        bcc :+
        inc dir_read_byte_high
      : rts
        

    dir_pointer_reverse:
        sec
        sbc dir_read_byte_low
        sta dir_read_byte_low
        bcs :+
        dec dir_read_byte_high
      : rts


;    rom_directory_entry_advance_to:
;        ; advance to position A in directory entry
;        cmp $fc

    rom_directory_filedata:
        ; position is at flags, bank is the next data to load
        ; all zp variables are free and can be used
        jsr efs_io_byte  ; bank
        sta $f8
        jsr efs_io_byte  ; bank high

        ; offset
        jsr efs_io_byte
        sta $f9
        jsr efs_io_byte
        ;clc
        ;adc #$80
        sta $fa

        ; size
        jsr efs_io_byte
        sta $fb
        jsr efs_io_byte
        sta $fc
        jsr efs_io_byte
        sta $fd

        rts


    rom_directory_begin_search:
        ; set pointer and length of directory
        lda #$d0
        ldx #$00  ; ### $A000
        ldy #$a0  ; ### $A000
        jsr EAPISetPtr
        ldx #$00
        ldy #$18  ; ### $1800 bytes, could be $2000
        lda #$00
        jsr EAPISetLen
        jsr efs_init_setstartbank
        lda #$00  ; ### 0, could be different bank
        jsr efs_generic_command
        rts


    rom_directory_checkname:
        ; compare filename
        ; name is in (fe/ff)
        ldy #$00
        ;sty $fc  ; position of directory entry ?
        ldx #$00
      @loop:
        jsr efs_io_byte    ; load next char
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
        jsr efs_io_byte    ; load next char
        sta dir_directory_entry
        inx
        lda dir_directory_entry  ; if == \0
        beq @match           ;   -> match
                             ; length check failed
      @next:
        cpx #$10
        beq :+
        jsr efs_io_byte    ; load next char
        inx
        bne @next
      : lda #$00
        sta dir_namecheck_result
        rts

      @match:
        cpx #$10
        beq :+
        jsr efs_io_byte    ; load next char
        inx
        bne @match
      : lda #$01
        sta dir_namecheck_result
        rts


    rom_directory_is_terminator:
        ; returns C set if current entry is empty (terminator)
        ; returns C clear if there are more entries
        ; uses A, status
        ; must not use X
        ;lda efs_directory_entry + efs_directory::flags
        lda $f9
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
        jsr efs_io_byte    ; load next char
        jsr rom_directory_is_terminator
        bcc @next      ; if not terminator entry (C clear) next check
        lda #$04       ; file not found: status=0, error=4, C
      @error:
        sta error_byte
        sec
        rts

      @next:
        ; test if hidden ###

        lda dir_namecheck_result
        bne @match
        jsr efs_io_byte 
        jsr efs_io_byte
        jsr efs_io_byte
        jsr efs_io_byte
        jsr efs_io_byte
        jsr efs_io_byte
        jsr efs_io_byte
        jmp @repeat

      @match:
        ; found, read file info
        jsr rom_directory_filedata
        clc
        rts



/*
      morefiles:
        ; check if deleted
        ; check if hidden or other wrong type ###
        ; we only allow prg ($01, $02, $03) ###
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

