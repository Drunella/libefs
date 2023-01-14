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


; constants

ERROR_FILE_OPEN          = $02
ERROR_FILE_NOT_OPEN      = $03
ERROR_FILE_NOT_FOUND     = $04
ERROR_DEVICE_NOT_PRESENT = $05
ERROR_NO_INPUT_FILE      = $06
ERROR_NO_OUTPUT_FILE     = $07
ERROR_MISSING_FILENAME   = $08

STATUS_EOF       = $40
STATUS_MISMATCH  = $10

; io rom
EFSLIB_ROM_START = $8000
EFSLIB_ROM_BANK  = 0

; configuration
LIBEFS_CONFIG_START = $bb18

; flags
LIBEFS_FLAGS_RELOCATE = $01
LIBEFS_FLAGS_VERIFY   = $02

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
    bank .byte
    addr .word
    mode .byte
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
    dfaddr .addr 
.endstruct

