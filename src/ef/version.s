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


.include "../../version.txt"


.export _get_version_major
.export _get_version_minor
.export _get_version_patch


_get_version_major:
    lda #major_version
    ldx #$00
    rts


_get_version_minor:
    lda #minor_version
    ldx #$00
    rts


_get_version_patch:
    lda #patch_version
    ldx #$00
    rts

