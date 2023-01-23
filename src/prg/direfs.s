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


.include "../ef/easyflash.i"


.import error_byte

.export rom_chrout_body
.export rom_command_begin
.export rom_command_process
.export rom_defragment_body
.export rom_format_body
.export rom_save_body

;.import __LOADER_LOAD__
;.import __LOADER_RUN__
;.import __LOADER_SIZE__

;.import __IO_WRAPPER_LOAD__
;.import __IO_WRAPPER_RUN__
;.import __IO_WRAPPER_SIZE__

;.import __EAPI_START__


;.import _load_eapi
;.import _wrapper_setnam
;.import _wrapper_load
;.import _wrapper_save


;.export _init_loader
;.export _init_loader_blank


.segment "CODE"

    _startup:

        ; ### check for easyflash

        lda $01
        sta direfs_memory_config
        lda #$37
        sta $01
        lda #$87   ; led, 16k mode
        sta $de02
        lda #$00   ; EFSLIB_ROM_BANK
        sta $de00

        jsr EFS_init
        jsr EFS_init_minieapi

        lda direfs_memory_config
        sta $01
        lda #$04   ; easyflash off
        sta $de02

        ; load "$"
        ldx #$ff  ; efs device
        ldy #$00  ; secondary address: relocate load
        jsr EFS_setlfs
        lda #dir_name_length
        ldx #<dir_name
        ldy #>dir_name
        jsr EFS_setnam
        ldx $2b
        ldy $2c  ; TXTTAB: start of basic program
        lda #$00  ; load to x/y
        jsr EFS_load

        ; relink basic
        jsr $A533

        rts

    direfs_memory_config:
        .byte $37
        
    dir_name:
        .byte "$"
    dir_name_length = * - dir_name


    ; external
    rom_chrout_body:
    rom_command_begin:
    rom_command_process:
    rom_defragment_body:
    rom_format_body:
    rom_save_body:
        lda #$05
        sta error_byte
        sec
        rts
    