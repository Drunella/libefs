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


.import rom_chrout_body
.import rom_save_body
.import rom_chrin_body
.import rom_close_body
.import rom_open_body
.import rom_load_body
.import rom_setnam_body
.import rom_setlfs_body

.export backup_zeropage_data
.export backup_memory_config
.export temporary_variable
.export memory_byte
.export status_byte
.export error_byte
.export efs_flags
.export internal_state
.export filename_address
.export filename_length
.export io_start_address
.export io_end_address
.export efs_io_byte
.export efs_generic_command
.export efs_enter_pha
.export efs_bankout
.export efs_enter


.segment "EFS_RAM"

; --------------------------------------------------------------------
; efs jump table

    EFS_setlfs:  ; @ $DF00
        ; parameter:
        ;    A: logical channel (will be ignored)
        ;    X: device number (will be ignored)
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
        ; parameter:
        ;    A: 0: read; 1: write
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
    status_byte = * + 1
        lda #$00
        rts


; --------------------------------------------------------------------
; efs wrapper function that need to switch banks

    efs_bankin:
        ; changes status: N, Z
        ; does not work with disabled io area
        ; 13 bytes
        pha
        lda $01  ; save memory config
        sta backup_memory_config
    memory_byte := * + 1
        lda #$37  ; bank to rom area
        sta $01
        bne efs_enter

    efs_bankout:
        ; changes status: N, Z
        ; does not work with disabled io area
        ; 13 bytes
        pha
    backup_memory_config := * + 1  ; exclusive usage
        lda #$37  ; restore memory config
        sta $01
        lda #EASYFLASH_KILL
        sta EASYFLASH_CONTROL
        pla
        rts

        ; variable code area
    efs_generic_command:
        .repeat GENERIC_COMMAND_SIZE
        .byte $60
        .endrepeat


    efs_io_byte:
        ; load byte in A
        ; 3 bytes
        ; jsr EAPIWriteFlashInc  ; $20, <EAPIWriteFlashInc, >EAPIWriteFlashInc
        ; jsr EAPIWriteFlash  ; $20, <EAPIWriteFlash, >EAPIWriteFlash
        jsr EAPIReadFlashInc  ; $20, <EAPIReadFlashInc, >EAPIReadFlashInc

    efs_enter_pha:
        ; changes status: N, Z
        ; 1 byte
        pha

    efs_enter:
        ; 11 bytes
        lda #EASYFLASH_LED | EASYFLASH_16K
        sta EASYFLASH_CONTROL
        lda #EFSLIB_ROM_BANK
        sta EASYFLASH_BANK
        pla

    efs_return:
        ; 1 byte
        rts


; --------------------------------------------------------------------
; efs data

    backup_zeropage_data:
        .repeat ZEROPAGE_SIZE
        .byte $00
        .endrepeat

;    backup_memory_config: ; exclusive usage
;        .byte $00

    error_byte:  ; exclusive usage
        .byte $00

    efs_flags:  ; exclusive usage
        .byte $00

    internal_state:  ; exclusive usage
        .byte $00
        ; bits 76543210
        ;      xx: 10: load; 01: dir; 11: save
        ;        xxxxxx : state machine value

    filename_address:
        .word $0000

    filename_length:
        .byte $00

    io_start_address:
        .word $0000

    io_end_address:
        .word $0000

    temporary_variable:
        .byte $00
