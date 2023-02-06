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

.include "easyflash.i"


.import __EFS_CONFIG_LOAD__
.import __EFS_CONFIG_RUN__


.segment "EFS_CONFIG"
    ef_name:
        .byte $65, $66, $2d, $6e, $41, $4d, $45, $3a
        .byte "efs test"
        .res 8, $00 

    efs_config:
        .byte "libefs"
        .byte 0, 0, 0

        .byte $03
        ;    bank lo/hi addr mode size
        .byte $00, $00, $a0, $d0,   0  ; area 0: bank 0, $a000, mode lhlh, ignore size
        .byte  32, $00, $80, $d0,  32  ; area 1: lower banks of 262144 bytes
        .byte  48, $00, $80, $d0,  32  ; area 2: upper banks of 262144 bytes
        .byte $01                      ; defragment warning: yes
        .addr __EFS_CONFIG_RUN__ + efs_defragment_warning_offset
        .addr __EFS_CONFIG_RUN__ + efs_defragment_allclear_offset
        .byte $00, $00, $00, $00  ; unused
        .byte $00, $00, $00, $00  ; unused
        .byte $00, $00            ; unused

    efs_config_size = * - efs_config
    .if efs_config_size <> 40
    .error "efs_config size mismatch"
    .endif


    efs_defragment_warning:
    efs_defragment_warning_offset = * - ef_name
        lda $d020
        clc
        adc #$01
        sta $d020
        rts

    efs_defragment_warning_size = * - efs_defragment_warning


    efs_defragment_allclear:
    efs_defragment_allclear_offset = * - ef_name
        lda #$00
        sta $d020
        rts

    efs_defragment_allclear_size = * - efs_defragment_allclear

;    .if efs_config_size > 200
;    .error "efs_defragment_warning too large"
;    .endif
