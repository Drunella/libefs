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


;.import error_byte

;.export rom_chrout_body
;.export rom_defragment_body
;.export rom_format_body
;.export rom_save_body
;.export rom_filesave_chrin_prepare
;.export rom_filesave_chrin_close
;.export rom_scratch_process
;.export rom_command_save_process


.segment "CODE"

    _startup:

        ; ### check for easyflash
        ; ### check for efslib

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
;    rom_chrout_body:
;    rom_defragment_body:
;    rom_format_body:
;    rom_save_body:
;    rom_filesave_chrin_prepare:
;    rom_filesave_chrin_close:
;    rom_command_save_process:
;    rom_scratch_process:
;        lda #$05
;        sta error_byte
;        sec
;        rts
    