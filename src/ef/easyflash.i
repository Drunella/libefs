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


; io functions
EF_SETNAM = $0200
EF_LOAD = $0203
EF_SAVE = $0206

; io rom
EF_ROM_START = $8000
EF_ROM_BANK  = 0

; efs banks
EFS_FILES_DIR_BANK     = 0
EFS_FILES_DIR_START    = $A000
EFS_FILES_DATA_BANK    = 1
EFS_FILES_DATA_START   = $8000
EFS_FILES_BANKSTRATEGY = $D0


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

; EFS lib

EFS_init    = $8000
EFS_init_minieapi = $8006
EFS_init_eapi = $8003
EFS_defragment = $8009
EFS_format = $800c

EFS_setlfs  = $DF00
EFS_setnam  = $DF06
EFS_load    = $DF0C
EFS_open    = $DF12
EFS_close   = $DF18
EFS_chrin   = $DF1E
EFS_readst  = $DF30
EFS_save    = $DF24
EFS_chrout  = $DF2A


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
