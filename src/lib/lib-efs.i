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


; sizes and zeropage
ZEROPAGE_SIZE .set 11
ZEROPAGE_BACKUP_END = $3f
GENERIC_COMMAND_SIZE .set 14

; must be page aligned
DIRECTORY_SIZE = $1800
BANKING_MODE = $d0


zp_var_xf := ZEROPAGE_BACKUP_END
zp_var_xe := ZEROPAGE_BACKUP_END - 1
zp_var_xd := ZEROPAGE_BACKUP_END - 2
zp_var_xc := ZEROPAGE_BACKUP_END - 3
zp_var_xb := ZEROPAGE_BACKUP_END - 4
zp_var_xa := ZEROPAGE_BACKUP_END - 5
zp_var_x9 := ZEROPAGE_BACKUP_END - 6
zp_var_x8 := ZEROPAGE_BACKUP_END - 7
zp_var_x7 := ZEROPAGE_BACKUP_END - 8
zp_var_x6 := ZEROPAGE_BACKUP_END - 9
zp_var_x5 := ZEROPAGE_BACKUP_END - 10

;.globalzp zp_var_x5, zp_var_x6, zp_var_x7, zp_var_x8, zp_var_x9, zp_var_xa,
;.globalzp zp_var_xb, zp_var_xc, zp_var_xd, zp_var_xe, zp_var_xf

; constants

ERROR_FILE_SCRATCHED     = $01
ERROR_FILE_OPEN          = $02
ERROR_FILE_NOT_OPEN      = $03
ERROR_FILE_NOT_FOUND     = $04
ERROR_DEVICE_NOT_PRESENT = $05
ERROR_NO_INPUT_FILE      = $06
ERROR_NO_OUTPUT_FILE     = $07
ERROR_MISSING_FILENAME   = $08

ERROR_WRITE_ERROR        = $19  ; 25
ERROR_WRITE_PROTECTED    = $1a  ; 26
ERROR_SYNTAX_ERROR_30    = $1e  ; 30
ERROR_FILE_EXISTS        = $3f  ; 63
ERROR_DISK_FULL          = $48  ; 72
ERROR_DIRECTORY_ERROR    = $47  ; 71

STATUS_EOF       = $40
STATUS_MISMATCH  = $10

; io rom
EFSLIB_ROM_START = $8000
EFSLIB_ROM_BANK  = 0

; configuration
EF_NAME = $bb08
LIBEFS_CONFIG_START = $bb18

; flags
LIBEFS_FLAGS_RELOCATE = $01
LIBEFS_FLAGS_VERIFY   = $02
LIBEFS_FLAGS_COMMAND  = $04
LIBEFS_FLAGS_AREA1    = $40  ; must be bit 6
LIBEFS_FLAGS_AREA2    = $80  ; must be bit 7

; eapi data and functions
EAPI_SOURCE  = $b800  ; $a000 (hirom) + 1800

EASYFLASH_BANK    = $de00
EASYFLASH_CONTROL = $de02
EASYFLASH_LED     = $80
EASYFLASH_16K     = $07
EASYFLASH_KILL    = $04

;EAPIInit          = address + $14
EAPIWriteFlash    = $df80
EAPIEraseSector   = $df83
EAPISetBank       = $df86
EAPIGetBank       = $df89
EAPISetPtr        = $df8c
EAPISetLen        = $df8f
EAPIReadFlashInc  = $df92
EAPIWriteFlashInc = $df95
EAPISetSlot       = $df98
EAPIGetSlot       = $df9b


; efs struct
.struct efs_directory
    .struct name
        .byte
        .byte
        .byte
        .byte
        .byte
        .byte
        .byte
        .byte
        .byte
        .byte
        .byte
        .byte
        .byte
        .byte
        .byte
        .byte
    .endstruct
    flags .byte
    bank .byte
    reserved .byte
    offset_low .byte
    offset_high .byte
    size_low .byte
    size_high .byte
    size_upper .byte
.endstruct


; lib efs config struct
.struct libefs_area
    dir_bank .byte  ; must not change
    dir_high .byte  ; this ordering !!!
    files_bank .byte
    files_high .byte
    size .byte
.endstruct

.struct libefs_config
    .byte 6      ; LIBEFS
    .byte 3      ; 0,0,0 (version in default config)
    areas .byte  ; 1 or 3
    area_0 .tag libefs_area
    area_1 .tag libefs_area
    area_2 .tag libefs_area
    dfcall .byte
    dfwarning .addr 
    dfallclear .addr

.endstruct

