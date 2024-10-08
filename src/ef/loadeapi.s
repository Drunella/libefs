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


;.include "easyflash.i"

EAPI_SOURCE  = $b800

EASYFLASH_CONTROL = $de02
EASYFLASH_LED     = $80
EASYFLASH_16K     = $07
EASYFLASH_KILL    = $04

.export _load_eapi


.segment "LOADEAPI"

    ; void __fastcall__ load_eapi(uint8_t highaddress)
    _load_eapi: 
        ; store high address
        sta load_eapi_adress_1 + $02
        sta load_eapi_adress_i + $02
        sta load_eapi_adress_2 + $02
        inc load_eapi_adress_2 + $02
        sta load_eapi_adress_3 + $02
        inc load_eapi_adress_3 + $02
        inc load_eapi_adress_3 + $02

        ; safe memory configuration
        lda $01
        pha

        ; bank in 16k mode
        lda #$37
        sta $01
        lda #EASYFLASH_LED | EASYFLASH_16K
        sta EASYFLASH_CONTROL

        ; switch to bank 0
        lda #$00
        sta $de00

        ; copy code
        ldx #$00
    :   lda EAPI_SOURCE + $0000, x
    load_eapi_adress_1:
        sta $fd00, x
        lda EAPI_SOURCE + $0100, x
    load_eapi_adress_2:
        sta $fe00, x
        lda EAPI_SOURCE + $0200, x
    load_eapi_adress_3:
        sta $ff00, x

        dex
        bne :-

        ; now bank out
        lda #EASYFLASH_KILL
        sta EASYFLASH_CONTROL
        lda #$37
        sta $01

        ; init
    load_eapi_adress_i:
        jsr $fd14

        ; return
        pla
        sta $01
        rts
