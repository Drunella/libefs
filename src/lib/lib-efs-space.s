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
.localchar '@'

.include "lib-efs.i"
.include "../../version.txt"


.import backup_zeropage_data
.import backup_memory_config
.import status_byte
.import error_byte
.import efs_flags
.import internal_state
.import filename_address
.import filename_length
.import io_start_address
.import io_end_address

.import efs_io_byte
.import efs_generic_command
.import efs_bankin
.import efs_bankout
.import efs_enter_pha
.import efs_enter

.import rom_dirload_isrequested
.import rom_dirload_verify
.import rom_dirload_transfer
.import rom_dirload_address
.import rom_dirload_begin
.import rom_dirload_chrin

.import rom_command_begin

.import restore_zeropage
.import backup_zeropage

.import efs_setstartbank_ext

.import rom_flags_get_area
.import rom_flags_set_area
.import rom_flags_get_area_invert
.import rom_config_rw_available
.import rom_config_get_value
.import rom_config_prepare_config
.import rom_config_get_area_bank
;.import rom_config_get_area_mode_invert
;.import rom_config_get_area_addr_high_invert
;.import rom_config_get_area_addr_low_invert
;.import rom_config_get_area_bank_invert
;.import rom_config_get_area_addr_high
;.import rom_config_get_area_addr_low
.import rom_config_get_area_size
;.import rom_config_get_area_mode
.import rom_config_get_area_dirbank
.import rom_config_get_area_dirbank_invert
.import rom_config_get_area_dirhigh
.import rom_config_get_area_dirhigh_invert
.import rom_config_get_area_filesbank
.import rom_config_get_area_filesbank_invert
.import rom_config_get_area_fileshigh
.import rom_config_get_area_fileshigh_invert


.import efs_init_readef
.import efs_init_readef_rely
.import efs_readef
.import efs_readef_low
.import efs_readef_high
.import efs_readef_bank
.import efs_readef_read_and_inc
.import efs_readef_pointer_inc
.import efs_readef_pointer_dec
.import efs_readef_pointer_advance
.import efs_readef_pointer_reverse
.import efs_readef_pointer_setall
.import efs_readef_pointer_set
.import efs_readef_swap
.import efs_readef_storedaddr_high
.import efs_readef_storedaddr_low
.import efs_readef_storedbank
.import efs_readef_dirboundary

.import efs_readmem
.import efs_init_readmem
.import efs_init_eapierasesector
.import efs_init_eapireadinc
.import efs_init_eapiwriteinc
.import efs_finish_tempvars
.import efs_temp_var1
.import efs_temp_var2
.import rom_config_call_defragment_allclear
.import rom_config_call_defragment_warning

.import efs_directory_search


.export rom_space_setdirstart
.export rom_space_subtractsize_blocks
.export rom_space_maxspace
.export rom_space_usedspace


.segment "EFS_ROM"


; --------------------------------------------------------------------
; efs functions for disk space calculations
; usage:
;   3b/3c/fd: free size
;   3e/3f: file size

    rom_space_blocksfree:
        jsr efs_init_readef
        jsr efs_init_eapireadinc

        ; init read_ef
        jsr rom_space_setdirstart

        jsr rom_space_maxspace
        jsr rom_space_usedspace

        jsr rom_space_subtractsize_blocks
        rts


    rom_space_setdirstart:
        ; init read_ef
        jsr rom_config_get_area_dirbank
        sta efs_readef_bank
        ;jsr rom_config_get_area_addr_low
        lda #$00
        sta efs_readef_low
        jsr rom_config_get_area_dirhigh
        sta efs_readef_high
        rts


    rom_space_subtractsize_blocks:
        ; checks used file in 3b/3c/3d
        ; against available size in 38/39/3a
        ; 38/39/3a - 3b/3c/3d -> 3b/3c/3d
        sec
        lda zp_var_x8
        sbc zp_var_xb
        sta zp_var_xb
        lda zp_var_x9
        sbc zp_var_xc
        sta zp_var_xc
        lda zp_var_xa
        sbc zp_var_xd
        sta zp_var_xd

        lda #$00
        sta zp_var_xb
        sec ; round down
        lda zp_var_xc
        sbc #$01
        sta zp_var_xc
        lda zp_var_xd
        sbc #$00
        sta zp_var_xd
        
        clc
        rts


    rom_space_maxspace:
        ; config must be set
        ; returns max blocks in 38/39/3a (low/mid/high)
        ; one chip contains 32 pages
        jsr rom_config_get_area_size
        tax       ; save value
        lsr
        lsr
        lsr
        sta zp_var_xa
        txa      ; calulate midbyte
        asl
        asl
        asl
        asl
        asl
        sta zp_var_x9
        lda #$00
        sta zp_var_x8

        sec       ; reduce by dirctory
        lda zp_var_x9
        sbc #>DIRECTORY_SIZE
        sta zp_var_x9
        bcs :+
        dec zp_var_xa

      : rts


    rom_space_usedspace:
        ; space by real active files
        ; config must be set correct
        ; directory is set properly
        ; returns free space in 3b/3c/3d (low/mid/high)
        lda efs_readef_low
        pha
        lda efs_readef_high
        pha

        ldx #$00
        lda #16
        jsr efs_readef_pointer_advance
        lda #$00
        sta zp_var_xb
        sta zp_var_xc
        sta zp_var_xd

      @loop:
        jsr rom_config_get_area_dirhigh
        jsr efs_readef_dirboundary
        bcs @leave  ; directory out of bounds
        jsr efs_readef
        cmp #$ff
        beq @leave
        and #$1f
        beq @skip
        lda #5  ; move to size
        jsr efs_readef_pointer_advance

        jsr efs_readef_read_and_inc
        clc
        adc zp_var_xb
        sta zp_var_xb
        jsr efs_readef_read_and_inc
        adc zp_var_xc
        sta zp_var_xc
        jsr efs_readef_read_and_inc
        adc zp_var_xd
        sta zp_var_xd

        lda #16
        jsr efs_readef_pointer_advance
        jmp @loop
      @skip:
        lda #24
        jsr efs_readef_pointer_advance
        jmp @loop

        ; reset directory
      @leave:
        pla
        sta efs_readef_high
        pla
        sta efs_readef_low

        rts
