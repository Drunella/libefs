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



.export EFS_init
.export EFS_setlfs
.export EFS_setnam
.export EFS_load
.export EFS_save
.export EFS_readst


.import __EFS_RAM_LOAD__
.import __EFS_RAM_RUN__
.import __EFS_RAM_SIZE__


.segment "EFS_RAM"

; --------------------------------------------------------------------
; efs jump table

    EFS_readst:  ; @ $DF00
        ; parameter: none
        ; return: 
        ;    A: status code ($10: verify mismatch; $40: EOF; $80: device not present)
        jsr efs_bankin
        jmp rom_readst_body

    EFS_setlfs:  ; @ $DF06
        ; parameter: 
        ;    X: number of efs structure; 
        ;    Y: secondary address(0=load, ~0=verify)
        ; return: none
        jsr efs_bankin
        jmp rom_setlfs_body

    EFS_setnam:  ; @ $DF0c
        ; parameter:
        ;    A: name length 
        ;    X: name address low
        ;    Y: name address high
        ; return: none
        jsr efs_bankin
        jmp rom_setnam_body

    EFS_load:    ; @ $DF12
        ; parameter:
        ;    A: 0=load, 1-255=verify
        ;    X: load address low 
        ;    Y: load address high
        ; return: 
        ;    A: error code ($04: file not found, $05: device not present; $08: missing filename; 
        ;    X: end address low
        ;    Y: end address high
        ;    .C: 1 if error
        jsr efs_bankin
        jmp rom_load_body

    EFS_save:    ; @ $DF18
        ; parameter:
        ;    A: z-page to start address
        ;    X: end address low
        ;    Y: end address high
        ; return:
        ;    A: error code
        ;    .C: 1 if error
        jsr efs_bankin
        jmp rom_save_body


; --------------------------------------------------------------------
; efs wrapper function that need to switch banks

    efs_bankin:
        ; changes status: N, Z
        ; does not work with disabled io area
        ; 13 bytes
        pha
        lda $01  ; save memory config
        sta store_memory_config
        lda #$37  ; bank to rom area
        sta $01
        jmp efs_enter

    efs_bankout:
        ; changes status: N, Z
        ; does not work with disabled io area
        ; 13 bytes
        pha
        lda store_memory_config  ; restore memory config
        sta $01
        lda #EASYFLASH_KILL
        sta EASYFLASH_CONTROL
        pla
        rts

    efs_set_startbank:
        ; safest way to set eapi shadow bank
        ; A: bank
        ; 6 bytes
        jsr EAPISetBank
        jmp efs_enter_pha

    efs_read_byte:
        ; load byte in A
        ; 6 bytes
        jsr EAPIReadFlashInc
        jmp efs_enter_pha

    efs_write_byte:
        ; write byte in A
        ; 3 bytes
        jsr EAPIWriteFlashInc

    efs_enter_pha:
        ; changes status: N, Z
        ; 13
        pha

    efs_enter:
        lda #EASYFLASH_LED | EASYFLASH_16K
        sta EASYFLASH_CONTROL
        lda #EFSLIB_ROM_BANK
        sta EASYFLASH_BANK
        pla
        rts


; --------------------------------------------------------------------
; efs data

    store_memory_config: ; exlusive
        .byte $00

    zeropage_backup:
        .byte $00, $00, $00, $00, $00, $00, $00

    status_byte:
        .byte $00

    error_byte:
        .byte $00

    filename_address:
        .word $0000

    filename_length:
        .byte $00

    io_start_address:
        .word $0000

    io_end_address:
        .word $0000

    efs_secondary:
        .byte $00

    efs_device:
        .byte $00

    efs_verify:
        .byte $00

    efs_directory_entry:
        .byte $00, $00, $00, $00, $00, $00, $00, $00
        .byte $00, $00, $00, $00, $00, $00, $00, $00
        .byte $00, $00, $00, $00, $00, $00, $00, $00



.segment "EFS_CALL"

; --------------------------------------------------------------------
; efs rom jump table
; 3 bytes jmp
; 10 byte magic & version
; 3 byte filler

    EFS_init:
        jmp efs_init_body

    efs_magic:
      .byte "lib-efs"
      .byte 0, 1, 0
      .byte $ff, $ff, $ff


.segment "EFS_ROM"

; --------------------------------------------------------------------
; efs: init and utility function bodies
; $f9
; $fa/fb: source/destination address
; $fc
; $fd
; $fe/ff: temporary pointer

    backup_zeropage:
        ldx #$06  ; backup zp
    :   lda $f9, x
        sta zeropage_backup, x
        dex
        bpl :-
        rts

    restore_zeropage:
        ldx #$06  ; restore zp
    :   lda zeropage_backup, x
        sta $f9, x
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
        rts


; --------------------------------------------------------------------
; efs body funtions
; need to leave with 'jmp efs_bankout'

    rom_readst_body:
        lda status_byte
        jmp efs_bankout  ; ends with rts


    rom_setlfs_body:
        stx efs_device
        sty efs_secondary
        jmp efs_bankout  ; ends with rts


    rom_setnam_body:
        ; A: length; X/Y: name address (x low)
        sta filename_length
        stx filename_address
        sty filename_address + 1;
        clc  ; no error
        jmp efs_bankout  ; ends with rts


    rom_load_body:
        ; return: X/Y: end address
        sta efs_verify
        stx io_start_address
        sty io_start_address + 1
        jsr backup_zeropage

        lda #$00
        sta status_byte
        sta error_byte

        jsr rom_directory_find
        bcs rom_load_body_leave ; not found

        jsr rom_fileload_begin
        jsr rom_fileload_address

        lda efs_verify
        bne :+  ; verify
        
        jsr rom_fileload_transfer
        jmp rom_load_body_leave
    :   jsr rom_fileload_verify

    rom_load_body_leave:
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
        php  ; save carry

        jsr restore_zeropage
        lda error_byte

        plp
        jmp efs_bankout  ; ends with rts


; --------------------------------------------------------------------
; efs load and verify functions

    rom_fileload_begin:
        ; directory entry in fe/ff
        ldx efs_directory_entry + efs_directory::offset_low
        lda efs_directory_entry + efs_directory::offset_high
        clc
        adc #$80
        tay
        lda #$d0  ; eapi bank mode
        jsr EAPISetPtr

        ldx efs_directory_entry + efs_directory::size_low
        ldy efs_directory_entry + efs_directory::size_high
        lda efs_directory_entry + efs_directory::size_upper
        jsr EAPISetLen

        lda efs_directory_entry + efs_directory::bank
        jsr efs_set_startbank

        rts


    rom_fileload_address:
        jsr efs_read_byte ; load address
        sta $fa
        jsr efs_read_byte
        sta $fb
        lda efs_secondary  ; 0=load to X/Y, 1=load to prg address
        bne :+
        lda io_start_address  ; load to given address
        sta $fa
        lda io_start_address + 1
        sta $fb

    :   lda $fa
        sta io_start_address
        lda $fb
        sta io_start_address + 1

        rts


    rom_fileload_transfer:
        ldy #$00
    @loop:
        jsr efs_read_byte
        bcs @eof
        sta ($fa), y
        iny
        bne @loop
        inc $fb
        jmp @loop

    @eof:
        clc
        tya
        adc $fa
        sta $fa
        bcc :+
        inc $fb
    :   lda $fa
        bne :+
        dec $fb
    :   dec $fa
     
        lda #$40
        sta status_byte

        lda $fa
        sta io_end_address
        lda $fb
        sta io_end_address + 1

        clc
        rts


    rom_fileload_verify:
        ldy #$00
    @loop:
        jsr efs_read_byte
        bcs @eof  ; eof
        cmp ($fa), y
        bne @mismatch
        iny
        bne @loop
        inc $fb
        jmp @loop

    @eof:
        lda #$40
        sta status_byte
        lda $fa  ; verify successful, reduce address by one
        bne :+
        dec $fb
    :   dec $fa
        jmp @leave

    @mismatch:
        lda #$10
        sta status_byte
        
    @leave:
        clc
        tya
        adc $fa
        sta $fa
        bcc :+
        inc $fb

    :   lda $fa
        sta io_end_address
        lda $fb
        sta io_end_address + 1

        lda status_byte
        and #$10
        bne :+
        clc
        rts
    :   sec
        rts


    ; --------------------------------------------------------------------
    ; directory functions

    directory_copy_next_entry:
        ; easyflash is banked in but on another bank
        ; EAPIReadFlashInc has been prepared (EAPISetPtr, EAPISetLen)
        ; carry set if no new entry
        ldy #$00

    :   jsr efs_read_byte
        bcs :+
        sta efs_directory_entry, y
        iny
        cpy #$18
        bne :-
        clc

    :   lda #EFSLIB_ROM_BANK
        sta EASYFLASH_BANK
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
        lda #$00  ; ### 0, could be different bank
        jsr efs_set_startbank
        rts


    rom_directory_is_terminator:
        ; returns C set if current entry is empty (terminator)
        ; returns C clear if there are more entries
        ; uses A, status
        ; must not use X
        lda efs_directory_entry + efs_directory::flags
        and #$1f
        cmp #$1f
        beq :+
        clc  ; in use or deleted
        rts
    :   sec  ; empty
        rts


    rom_directory_find:
        lda filename_address
        sta $fe
        lda filename_address + 1
        sta $ff
        jsr rom_directory_begin_search

        lda filename_length
        bne nextname
        lda #$08       ; no filename: status=0, error=8, C
        bne error      ; jmp to error

      nextname:
        ; next directory
        jsr directory_copy_next_entry

        ; test if more entries
        jsr rom_directory_is_terminator
        bcc morefiles  ; if not terminator entry (C clear) inspect entry
        lda #$04       ; file not found: status=0, error=4, C
      error:
        sta error_byte
        sec
        rts

      morefiles:
        ; check if deleted
        ; check if hidden or other wrong type ###
        ; we only allow prg ($01, $02, $03) ###
        lda efs_directory_entry + efs_directory::flags
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


