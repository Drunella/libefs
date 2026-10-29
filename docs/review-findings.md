# libefs code review – findings

Review of libefs 1.0.0 (commit `ff7d2d4`). How the code works is described
in [architecture.md](./architecture.md).

Last re-evaluation: after the fixes up to commit `ae9949a` (C1-C8, M7);
second full review after commit `dc8a186` (M1-M9), see "Second review"
below. Line numbers of open items refer to the state named in their
section; for fixed items they refer to the original code.

**Status**:

- **fixed**: fixed and verified in VICE, see the item for the test.
- **confirmed**: reproduced in VICE 3.9 with the real test cartridge on
  the current code (see "How the findings were verified").
- **by code**: found by reading the code, not reproduced.

**Severity**:

- **critical**: crash, or data loss/corruption in normal use.
- **major**: wrong results or API contract violations a program will hit.
- **minor**: edge cases and cosmetics.
- **doc**: documentation mismatch.

## Summary

| ID | Severity | Status | Short description |
| -- | -------- | ------ | ----------------- |
| C1 | critical | **fixed** | Defragment crashes: callback "fix" from PR #1 switches the ROM bank under running code |
| C2 | critical | **fixed** | `rom_config_get_value` returns the caller's flags, so `dfcall = 0` is ignored and the callbacks jump through `$0000` |
| C3 | critical | **fixed** | Defragment between areas with different banking modes corrupts every file that crosses a bank |
| C4 | critical | **fixed** | chrout-writing past the end of the last area wraps to bank 0 and overwrites libefs in flash |
| C5 | critical | **fixed** | `EFS_chrout` keeps writing after "disk full" / EOF |
| C6 | critical | **fixed** | `EFS_save` stores a wrong size when (end − start) mod 256 = 255; the file is corrupt |
| C7 | critical | **fixed** | `EFS_save` with end < start writes a ~64K garbage file |
| C8 | critical | **fixed** | `open(1)` with an `S:` command followed by `close` programs flash at a garbage address |
| M1 | major | **fixed** | Verify flag is never cleared; every later load is a verify |
| M2 | major | **fixed** | Scratch errors (write protected, write error) are returned with C clear |
| M3 | major | **fixed** | Command prefix parsing loses the carry: wrong name pointer when the name crosses a page |
| M4 | major | **fixed** | Drive-number check accepts `'`…`0` instead of `0`…`9` |
| M5 | major | **fixed** | `EFS_close` (write), `EFS_defragment` and `EFS_format` clobber zero page `$35-$3f` |
| M6 | major | **fixed** | `EFS_save` (and open for writing, defragment, format) with MiniEAPI report success but write nothing |
| M7 | major | **fixed** | Zero-length save returns a garbage error code (low byte of the end address) |
| M8 | major | **fixed** | `EFS_save`/`EFS_load` while a file is open return "file open" but close or corrupt that file |
| M9 | major | **fixed** | "Blocks free" is garbage for read-only configurations and full areas |
| M10 | major | **partly fixed** | No recovery from an interrupted defragment or an unclosed write file (open); `EFS_validate` stub returned C unchanged (fixed: returns A = 0, C clear) |
| M11 | major | by code | Defragment callbacks must preserve Y (and should preserve X), which is not documented or enforced |
| m1 | minor | by code | Names longer than 16 characters can desynchronise the directory scan |
| m2 | minor | by code | Directory bounds are not checked for deleted entries; dirlist uses a hard-coded `$b8` bound |
| m3 | minor | by code | `rom_filesave_blockedspace` uses the stale "active file" area |
| m4 | minor | by code | `rom_defragment_erasearea` with size < 8 erases 256 sectors |
| m5 | minor | by code | Hard-coded `$80`/`$a0` file base and dir bank used as files bank |
| m6 | minor | confirmed | LOAD returns the last address, not last + 1 like the KERNAL |
| m7 | minor | partly confirmed | Various smaller API inconsistencies (see list) |
| D1 | doc | – | Documentation mismatches |
| S1 | critical | **fixed** | Defragment copies size+1 bytes per file; the next save fails on the stray byte |
| S2 | critical | **fixed** | Defragment has no bounds checks: a `$ffffff` entry programs bank 0 and the whole cartridge |
| S3 | critical | **fixed** | `EFS_format` with an open file: next `chrin` erases banks 0-7 (read) / a later file gets a corrupt size (write) |
| S4 | critical | **fixed** | `EFS_open` while a write channel is full clears the status; the next `chrout` writes into bank 0 |
| S5 | critical | **fixed** | `EFS_save` of ≥ 64 KB passes the space check and writes past the area into bank 0 |
| S6 | major | **fixed** | A failed save leaves a live, corrupt directory entry |
| S7 | major | **fixed** | Write/erase errors ignored in defragment, erase and close |
| S8 | major | **fixed** | `chrin` signals EOF one byte late (KERNAL difference) |
| S9 | major | by code | Type `$1f` entries: terminator for search/dirlist, live file for space/save/defragment |
| S12 | minor | **fixed** | Verify end address of a file without data (with S8) |
| S10-S22 | minor | see section | Exact-fit save, dir `chrin` X/Y, verify end address, name consumed, parser bounds, `@` handling, 254 files, geometry assumptions, commit marker, API nits |
| S23 | doc | – | Callback and memory rules, activity indication, comment list |
| T1-T12 | various | see section | Tools (`tools/*.py`), Makefile and test cartridge |

---

## Critical

### C1 – Defragment crashes because the callbacks switch the ROM bank (regression from PR #1)

`src/lib/lib-efs.s:1131-1161` (`rom_config_call_defragment_warning`) and
`:1180-1210` (`rom_config_call_defragment_allclear`).

The functions save `efs_readef_bank`, select bank 0, and on exit do

```
        pla
        sta EASYFLASH_BANK      ; restore caller's bank
        sta efs_readef_bank
        rts
```

This code runs from ROML of bank 0 (`$84eb`/`$852b`). Writing a
non-zero value to `$de00` replaces the ROM the CPU is executing, so the
next instruction is fetched from the source bank. During defragmentation
`efs_readef_bank` is the source area's bank (32 in the test cartridge),
so the machine crashes at the first callback.

The premise of the PR is also wrong: `$de00` is always 0 while library
ROM code runs. Every flash access in another bank goes through
IO2 code that returns via `efs_enter`, which sets `$de00 = 0` again
(see architecture.md §2.2). The garbage `dfcall` value the PR describes
was really caused by C2.

*Reproduced*: `EFS_defragment` on the test cartridge →
`executing roml at $8527 with EASYFLASH_BANK=32`.

*Reproduced in VICE* (`build/test-libefs.crt`, menu key `0`): the
machine crashes and ends up in a blank, reset-like state. With only the
`sta EASYFLASH_BANK` restore removed, the same key prints
`defragment: rt=0, timer=33.278105 s`.

*Fix*: remove the bank save, select and restore code that PR #1 added,
and fix C2 instead.

**Fixed** (commit `564eb31`): the PR #1 code is removed
and the two functions are back to their state before PR #1, plus the C2
fix.

### C2 – `rom_config_get_value` returns the caller's processor flags

`src/lib/lib-efs.s:1365-1388`.

```
        php  ; save status
        sei
        ...
        pla  ; it will pop the result
        plp  ; restores interrupt flag
        rts
```

`plp` restores **all** flags from before the call. The flags therefore
do not reflect the returned value. The callback functions rely on them:

```
        lda #libefs_config::dfcall
        jsr rom_config_get_value
        beq @done
```

Before the call, Z is cleared by `lda #libefs_config::dfcall` (28), so
`beq` is never taken. The callbacks are always called. With
`dfcall = 0` and zero vectors (the defaults in `efs_default_config`),
`jmp ($0035)` jumps to `$0000` and the CPU crashes there. This is the
"CPU JAM at $0008" from PR #1.

*Reproduced*: test cartridge with `dfcall` and both vectors set to 0,
PR #1 bank code removed → `illegal opcode $2f at $0000`.

*Fix*: put `ora #$00` (or `cmp #$00`) after the `jsr` in both
callbacks, or let `rom_config_get_value` end with `plp` followed by
`ora #$00`. `ora` leaves C and I untouched. Check every other caller that
branches directly on the result.

**Fixed** (commit `564eb31`): `rom_config_get_value`
now ends with `ora #$00` after `plp`, so N/Z reflect the returned value,
while C and I are preserved. The two callback functions are the only
callers that branch on these flags.

Verified in VICE (menu key `0`, border set to green before the key):

| Cartridge | Result |
| --------- | ------ |
| test cart (callbacks on) | `defragment: rt=0`; border black at the end, i.e. the all-clear callback ran |
| test cart patched to `dfcall = 0`, vectors 0 | `defragment: rt=0`; border stays green, i.e. no callback was called and nothing jumped to `$0000` |
| unfixed `HEAD` (control) | crash |
| `lh` build: load `delme17k`, defragment, verify | `rt=0`, `st: $40` (file intact) |

### C3 – Defragment uses the destination's banking mode for the source pointer

`src/lib/lib-efs-rw.s:781-800` (`rom_defragment_copy_data_sourceinc`).

The source pointer is wrapped at the end of a bank using `zp_var_x7`.
In `rom_defragment_copy` that is the banking mode of the **destination**
area (`rom_config_get_area_mode_invert`). If the two areas have
different modes, the source bank wrap is wrong. This is the case in the
default test layout (`BANKMODE=ll` in the Makefile: area 1 `llll`,
area 2 `hhhh`).

- `llll` → `hhhh`: the source continues from `$9fff` to `$a000` of the
  same bank (area 2's ROMH) instead of `$8000` of the next bank.
- `hhhh` → `llll`: the source runs past `$bfff` into C64 memory.

*Reproduced* (C1 removed so defragment can run): before/after hashes of
the 7 test files in `ll` mode. `DELME15`, `DELME384`, `DELME640` and
`DELME641` survive. `DELME642`, `DELME17K` and `DELME50K`, the files
that cross a bank boundary, are corrupted. The same test with
`BANKMODE=lh` (both areas `lhlh`) leaves all files intact.

*Reproduced in VICE*: menu sequence "filename `delme17k`, load (1),
defragment (0), verify (2)":

- `ll` build: `v: rt=255 … st: $10` (mismatch).
- `lh` build: `rt=0 … ea=$8267 st: $40` (correct).

*Fix*: keep the source mode separately and use it in `sourceinc`.
`efs_temp_var1` was apparently intended for this; see the comment in
`rom_defragment_copy`.

**Fixed**: `rom_defragment_copy` stores the source area's banking mode
in `efs_temp_var1` (the previously commented-out code), and
`rom_defragment_copy_data_sourceinc` uses it instead of `zp_var_x7`.

Verified in VICE. Sequence: load `delme17k`, defragment, verify,
defragment, verify. That copies in both directions, `llll` → `hhhh` and
back.

| Cartridge | Result |
| --------- | ------ |
| `ll` build, fixed | both defragments `rt=0`, both verifies `rt=0 st: $40` |
| `ll` build before the fix (control) | verify mismatch `st: $10` after the first defragment |
| `lh` build, fixed (regression) | both defragments and both verifies OK |

### C4 – Writing with chrout past the area end overwrites libefs in bank 0

`src/lib/lib-efs-rw.s:1470-1492` (`rom_filesave_transfer_data_prepare`)
and `:229-234` (`rom_chrout_body`).

The overflow bank is calculated as `(dir bank + size) & $3f` (llll/hhhh)
or `(dir bank + size/2) & $3f` (lhlh). For an area that ends at the last
bank (area 1 in `ll` mode: 32 + 32; area 2 in `lh` mode: 48 + 16) the
result is 0. `EAPIGetBank` never returns 0 while writing, so "disk full"
is never detected. After bank 63, EAPI continues at bank 64, which the
hardware treats as bank 0. libefs's own code is there.

*Reproduced*: `open(1)` "BIG" and `chrout($00)` in a loop. After 186,665
bytes the first program cycle hits ROML bank 0 `$8000`, replacing the
`$4c` of `EFS_init`'s `jmp` with `$00`. The emulated machine then
crashes inside libefs. On real hardware this permanently damages the
cartridge's copy of libefs.

*Fix*: compute the end bank without the mask (or as the last valid bank)
and compare with `>=`. Better, check before writing (`EAPIGetBank`
before `efs_io_byte`), so the byte that would cross the end is never
written.

**Fixed**: `rom_filesave_transfer_data_prepare` no longer masks the end
bank with `$3f`. EAPI's bank counter goes to 64 after bank 63 (only the
hardware wraps to 0), so the end bank 64 is now reached right after the
last byte of bank 63 is written, and "disk full" is reported before
anything is written to bank 0.

Verified in VICE with a test program (`work/c4test.s`) that runs in the
test cartridge environment. It writes `BIG` with chrout until the first
error, closes it, reads it back with chrin, and copies bank 0 ROML to RAM
for comparison with the built image.

| | fixed | before the fix (control) |
| - | ----- | ------------------------ |
| bytes accepted before the error | 186,663 + 1 (the byte that reaches the end is written; C is set afterwards) | 186,664 |
| error | disk full (`readst` = `$40`) | write error `$19` |
| `close` | OK | – |
| read back | 186,664 bytes, 0 mismatches (= exactly the free space: 256K − `$1800` − 69,336) | – |
| bank 0 ROML | unchanged | `$8000` changed from `$4c` to `$08` (libefs `EFS_init` destroyed) |

Remaining, related: C5 is still open. A program that keeps calling
chrout after "disk full" would still write the next byte, and for an
area ending at bank 63 that byte lands in bank 0. Also, on disk full
chrout returns A = `$40` (the status value) instead of the error code
`$48`; `error_byte` is correct.

### C5 – `EFS_chrout` ignores a previous EOF / disk full

`src/lib/lib-efs-rw.s:214-220`:

```
        lda #ERROR_WRITE_ERROR
        sta error_byte
        sec
        beq @done      ; never taken, A = $19
```

After "disk full" (status `$40`) the next chrout falls through and writes
the byte anyway. Programs that ignore an error and keep writing (common
with KERNAL-style output loops) therefore write beyond the area,
including the next r/w area's directory (for `lh` area 1 the end bank 48
is area 2's first bank). Together with C4 this writes to bank 0.

*Reproduced*: after the first error, every further `chrout` still
causes a flash program cycle.

*Fix*: `bne @done` (or `jmp`).

**Fixed**: `beq @done` → `bne @done`.

Verified in VICE with `work/c5test.s`. It is the C4 test plus three more
`chrout` calls after the first error, before `close`.

| | fixed | before the fix (control, C4 already fixed) |
| - | ----- | ------------------------------------------ |
| 3 extra chrout calls | each returns `$19` with C set, nothing written | each returns `$40` with C set, but the byte **is** written |
| file size after close / read back | 186,664 bytes, 0 mismatches | 186,667 bytes, 3 mismatches |
| bank 0 ROML | unchanged | `$8000-$8002` overwritten with `$00` (libefs `EFS_init` destroyed) |

### C6 – `EFS_save` computes a wrong size when (end − start) mod 256 = 255

`src/lib/lib-efs-rw.s:1345-1352` (end of `rom_filesave_begin`):

```
        clc
        lda #$02
        adc zp_var_xb
        sta zp_var_xb
        bne :+          ; should be bcc
        inc zp_var_xc
```

If the low byte is `$fe`, `+2` gives `$00` and the carry is (correctly)
propagated. If it is `$ff`, `+2` gives `$01`, `bne` skips the increment,
and the size is 256 bytes too small. Both the directory entry and the
number of bytes written are wrong.

*Reproduced*: saving `$4000-$40ff` (255 bytes) creates an entry with
size 1 instead of 257. Loading it back does not return the data.

*Fix*: `bcc :+` / `inc zp_var_xc` / `bne :+` / `inc zp_var_xd`.
`rom_filesave_addsize` already does it right.

**Fixed**: `bne :+` → `bcc :+` after adding the 2 bytes for the load
address.

Verified in VICE with `work/c6test.s`. It saves 6 files from a pattern
with data lengths 255, 254, 511, 256, 1 and 767 (in this order). It then
loads each one back relocated to `$5000`, compares every byte, and
checks the end address and that the byte after the file is untouched.

| length | fixed | before the fix (control) |
| ------ | ----- | ------------------------ |
| 255 | OK, end `$50fe`, 0 mismatches | end `$4fff` (recorded size 1), 254 mismatches |
| 254 | OK | **save fails with write error `$19`**: the previous file wrote 257 bytes but recorded 1, so the next file was placed on already written flash |
| 511 | OK | 255 mismatches (same bug, length mod 256 = 255) |
| 256, 1 | OK | OK |
| 767 | OK | 255 mismatches |

So the bug corrupts the saved file, and also every following save into
the same area until the next defragmentation.

### C7 – `EFS_save` with end < start is not rejected

`src/lib/lib-efs-rw.s:1000-1017` (`rom_filesave_checkzero`): the
"less than" and "greater" branches both end in `clc`, so only
end = start is rejected. With end < start, all 16-bit subtractions wrap
and libefs writes a file of about 64K from wrapping RAM.

*Reproduced*: `save` with start `$4100`, end `$4000` → success, the
directory entry has size 65282.

*Fix*: return C set for end < start (`ERROR_SYNTAX_ERROR_30` or similar).

**Fixed** together with M7: `rom_filesave_checkzero` now rejects
end < start (in both the high and the low byte) and end = start with
C set and A = `ERROR_SYNTAX_ERROR_30` (`$1e`). It also runs before the
free-space checks, so an invalid range is reported as such and not as
"disk full".

Verified in VICE with `work/c7test.s` (5 saves, each loaded back and
compared) and `work/c7ctl.s` (one invalid save, then the directory):

| case | fixed | before the fix (control) |
| ---- | ----- | ------------------------ |
| `$4080`-`$4010` (end < start, same page) | `$1e`, C set, no file | accepted (A = 0, C clear); directory shows `V0`, blocks free 728 → 472 |
| `$4100`-`$4000` (end < start, page below) | `$1e`, C set, no file | – |
| `$4012`-`$4012` (empty) | `$1e`, C set, no file (was: A = `$12`, see M7) | – |
| `$4000`-`$4001`, `$40f0`-`$4110` | saved, loaded back, 0 mismatches | – |

### C8 – `open` for writing with an `S:` command, then `close`, writes to flash

`src/lib/lib-efs.s:1606-1614` and `src/lib/lib-efs-rw.s:409-414`.

`rom_open_body` sets `internal_state = %11000000` before the command is
processed. The `S` command scratches and returns via `@stop`, which
leaves `internal_state` unchanged. `EFS_close` sees "write mode" and
calls `rom_filesave_chrin_close`. That function programs 3 size bytes at
`filename_address` (now the name after `S:`, a RAM address) in bank
`filename_length` (the name length).

*Reproduced*: `setnam "S:DELME384"`, `open(1)`, `close` → one flash
program cycle during close, at an address that was never prepared.

*Fix*: let `rom_command_process` reset `internal_state` for commands that
finish the operation (`S`), or make close check a dedicated
"write prepared" flag.

**Fixed**: after a scratch, `rom_command_process` sets `internal_state`
to the new value `STATE_COMMAND_DONE` (`$01`, bits 7/6 = `00`). The
channel stays open, so the usual `open` … `close` sequence keeps working
without an error. `close` does nothing, `chrin` returns "no input file"
and `chrout` "no output file", and nothing is written.

Verified in VICE with `work/c8test.s`. VICE wrote the flash back into a
copy of the `.crt`, and `work/crtdiff.py` lists every changed flash
byte:

| step | fixed | before the fix (control) |
| ---- | ----- | ------------------------ |
| `open(1)` `S:DELME384` | `$01` scratched | `$01` scratched |
| `chrin` | C set ("no input file") | C set |
| `chrout $55` | `$07` "no output file", C set | `$19`, C set, **but written into the scratched entry** (its bank byte `$20` → `$00`) |
| `close` | OK | OK, **but programs bank 8 `$8000` `$52` → `$50`** (inside an area 0, i.e. read-only, file) |
| `open(0)` `DELME384` | `$04` not found | – (machine hung) |
| `open(0)` `S0:DELME640`, `close` | `$01`, OK | – |
| flash changes in total | only the 2 flags bytes (`$61` → `$60`) | 3 bytes, 2 of them corruption |

---

## Major

### M1 – Verify flag is never cleared

`src/lib/lib-efs.s:752-756` (`rom_load_body`) sets `LIBEFS_FLAGS_VERIFY` with `ora`. It is
only cleared when `EFS_util` setlfs overwrites `efs_flags`. After one
verify, every later `EFS_load` with A = 0 verifies instead of loading,
unless setlfs is called first.

*VICE*: verify `DELME15` against cleared memory (`readst` = `$10`),
then `EFS_load` with A = 0 without calling setlfs → `readst` is `$10`
again and the memory is still empty, so the "load" was a verify.

*Fix*: clear the bit at the start of `rom_load_body` (`and #$ff - LIBEFS_FLAGS_VERIFY`).

**Fixed**: `rom_load_body` clears the verify flag on every call and sets
it only if A ≠ 0.

Verified in VICE (`work/m1test.s`): verify `DELME15` against empty
memory (`$10`), then load with A = 0 without setlfs, then verify again.

| step | fixed | before the fix |
| ---- | ----- | -------------- |
| load after a verify | OK, `readst` = `$40`, data loaded | C set, `readst` = `$10`, no data (verified instead) |
| verify against loaded data | OK, `readst` = `$40` | – |

### M2 – Scratch errors are swallowed

`src/lib/lib-efs.s:1585-1591` (`rom_command_process`). After
`rom_scratch_process` the code always jumps to `@stop` (`lda #0; sec`).
`rom_open_body` treats "C set, Z set" as "stop, no error" and clears C.
So `ERROR_WRITE_PROTECTED` (file in area 0) and `ERROR_WRITE_ERROR`
come back with C clear. (Since the C8 fix the channel is in the
"command done" state afterwards, so `chrin` no longer reads from a stale
pointer.)

*VICE*: `open "S:DATA1"` (area 0) → A = `$1a`, C clear.

**Fixed**: `rom_command_process` now checks the carry from
`rom_scratch_process`. On an error it takes the normal error path: the
channel is closed and the error is returned with C set. On success the
channel goes into the "command done" state (C8) as before.

Verified in VICE (`work/m2test.s`):

| case | fixed | before the fix |
| ---- | ----- | -------------- |
| `open "S:DATA1"` (area 0) | `$1a`, C set; channel closed (`chrin`/`close` → `$03`) | `$1a`, C clear |
| `open(1) "S:DATA1*"` (area 0) | `$1a`, C set | `$1a`, C clear |
| `open "S0:DELME15"` | `$01`, C clear; `close` OK | same |
| same again (already scratched) | `$04`, C set | same |

### M3 – Command prefix: carry lost when advancing the name pointer

`src/lib/lib-efs.s:1546-1551` (`rom_command_begin`), same pattern as C6:

```
        sec
        tya
        adc zp_var_xe
        sta zp_var_xe
        bne :+          ; should be bcc
        inc zp_var_xf
```

If the name after `S0:`/`$0:`/`@0:` starts in the next page, the high
byte is not incremented and the wrong memory is used as the file name.
For `S` and `@` this can scratch the wrong file.

*VICE*: `"S0:DELME640"` stored at `$33fe` → `open` returns `$04`
(not found), because the name is read from `$3301` instead of `$3401`.

**Fixed**: `bne :+` → `bcc :+`.

Verified in VICE (`work/m3test.s`). `"S0:DELME640"` is placed at
`$33fe`, so the name part starts at `$3401`. `$3301` holds `DELME641`
as bait.

| case | fixed | before the fix |
| ---- | ----- | -------------- |
| `open "S0:DELME640"` | `$01`; `DELME640` gone, `DELME641` intact | `$01`, but **`DELME641` was scratched** (wrong file) |
| `load "$0:DELME6*"` at `$34fd` | listing shows `DELME641`, `DELME642` | – |

### M4 – Drive number check accepts the wrong characters

`src/lib/lib-efs.s:1526-1530`:

```
        clc
        adc #$ff - $30        ; lower bound $30
        adc #$39 - $30 + $01  ; upper bound $39
        bcc @nomatch
```

The accepted range is `$27`-`$30` (`'`, `(`, `)`, `*`, `+`, `,`, `-`, `.`,
`/`, `0`), not `0`-`9`.

*VICE*: `load "$1:*"` → `$04` (searched as a file name instead of being
a directory command).

Correction: the earlier example `"/:DATA1"` was wrong. There the `:` is at
position 1, so this is the one-character command form `/:` and the drive
number check is not involved (`$1e` before and after the fix). Wrongly
*accepted* prefixes are three-character ones such as `"$/:"` or `"S.:"`.

*Fix*: `sec; sbc #$30; cmp #$0a; bcs @nomatch`.

**Fixed**: the check is now `sec; sbc #$30; cmp #$0a; bcs @nomatch`.

Verified in VICE (`work/m4test.s`, `work/m4ctest.s`):

| case | fixed | before the fix |
| ---- | ----- | -------------- |
| `load "$1:*"` | directory | `$04` not found |
| `open "S1:DELME642"` | `$01` scratched | `$04` (taken as a file name) |
| `load "$9:DELME64*"` after the scratch | listing with `DELME640`, `DELME641` | `$04` not found |
| `load "0:DATA1"` | `$1e` (command `0`) | same |

### M5 – Zero page `$35-$3f` is not preserved by some calls

- `EFS_close` after writing: `rom_filesave_chrin_close` calls
  `rom_config_prepare_config` and writes `$35/$36` (`lib-efs-rw.s:409-414`).
- `EFS_defragment` and `EFS_format` (ROM calls `$8009`/`$800c`,
  `lib-efs-rw.s:156`, `:185`) use `$35-$3f` without `backup_zeropage`.

*VICE*: `$35-$3f` filled with `$a5`, then counting the changed bytes:

| call sequence | changed bytes |
| ------------- | ------------- |
| open(1) / chrout / close | 2 |
| open(0) / chrin / close | 0 |
| `EFS_defragment` | 11 (all) |
| `EFS_format` | 5 |

**Fixed**: `rom_close_body` backs up and restores the zero page around
`rom_filesave_chrin_close`. The ROM entries `EFS_defragment` and
`EFS_format` now go through `efs_defragment_entry`/`efs_format_entry`,
which do the same. `restore_zeropage_keep_ac` keeps A and C of the
result.

Verified in VICE (`work/m5test.s`), counting changed bytes in `$35-$3f`:

| call sequence | fixed | before the fix |
| ------------- | ----- | -------------- |
| open(1) / chrout / close | 0 | 2 |
| open(0) / chrin / close | 0 | 0 |
| `EFS_defragment` (result OK, file loads back afterwards) | 0 | 11 |
| `EFS_format` (result OK, file gone afterwards) | 0 | 5 |

These locations are BASIC/KERNAL temporaries, and cc65 programs or games
may use them as well. Load, save, open and chrin restore them, so callers
will assume close does too.

### M6 – `EFS_save` / chrout with MiniEAPI report success but write nothing

MiniEAPI has no `EAPIWriteFlashInc`. Its slot `$df95` is the body of
`EAPISetBank` (`src/lib/lib-efs-minieapi.s:131-134`). It sets the bank
shadow and `$de00` to the data byte and returns with C unchanged (clear).
`rom_filesave_conditions` does not know that it runs on MiniEAPI.

*VICE*: after `EFS_init_minieapi`, `save "MINI"` → A = 0, C clear;
loading `MINI` afterwards → `$04` not found.

*Fix*: make the MiniEAPI write entries return C set (e.g. `sec; rts`
stubs), or remember in `efs_flags` which EAPI was installed and reject
writes with `ERROR_WRITE_PROTECTED`.

**Fixed** (the second variant): the new `rom_check_writable` checks for
the real EAPI. Its jump table has a `jmp` (`$4c`) at `$df80`, where
MiniEAPI has an `rts`. `rom_filesave_conditions` (save, open for
writing), `rom_scratch_process`, `EFS_defragment` and `EFS_format`
return `ERROR_WRITE_PROTECTED` (`$1a`, C set) with MiniEAPI. MiniEAPI
itself is unchanged (no free space for failing stubs).

Verified in VICE (`work/m6test.s`):

| operation with MiniEAPI | fixed | before the fix |
| ----------------------- | ----- | -------------- |
| `save` | `$1a`, C set | `$00` (nothing written) |
| `open(1)` | `$1a`, C set | `$00` |
| scratch | `$1a`, C set | `$19`, C set |
| `EFS_defragment` | `$1a`, C set | `$00` (nothing done) |
| `EFS_format` | `$1a`, C set | `$00` (nothing done) |
| `load` | works | works |

Switching back with `EFS_init_eapi` makes saving work again.

### M7 – Zero-length save returns garbage in A

`rom_filesave_checkzero` (old code) returned C set with A = low
byte of `io_end_address`. `rom_filesave_conditions` stores A in
`error_byte`.

*Reproduced* (before the fix): save `$4012-$4012` → A = `$12`, C = 1.

**Fixed** with C7: A = `ERROR_SYNTAX_ERROR_30` (`$1e`).

### M8 – `EFS_save` while a file is open closes that file

`rom_save_body` `@leave` (`lib-efs-rw.s:354-357`) always sets
`internal_state = 0`, also in the "file open" error path.

*VICE*: `open "DATA1"`, `save` → `$02` (file open). The following
`chrin` returns `$03` (file not open).

While fixing this it turned out to be worse than described:
`rom_save_body` (and `rom_load_body`) stored the new start/end addresses
in `io_start_address`/`io_end_address` and reset the status *before*
checking for an open file. For a file being written with chrout these
variables hold the byte counter and end bank; for an open directory they
hold the listing state.

**Fixed**: `rom_save_body` and `rom_load_body` check `internal_state`
first and return `ERROR_FILE_OPEN` (C set) without touching any state.

Verified in VICE (`work/m8test.s`; control without the destructive
load-back: `work/m8dtest.s`):

| case | fixed | before the fix |
| ---- | ----- | -------------- |
| `load` and `save` while a chrout file is open | both `$02`; writing continues, `close` OK, file loads back with the right size and data | `$02`, but `save` closed the channel: `close` → `$03`, the size was never written, the directory shows `WF` with **8192 blocks** (size `$ffffff`), and loading it overwrites all memory |
| `save` while a file is open for reading | `$02`; `chrin` continues | `$02`, then `chrin` → `$03` (file closed) |
| `load` in the middle of a directory listing | `$02`; listing complete and unchanged | – |

### M9 – "Blocks free" is garbage for read-only configurations

`rom_dirload_sm_freelow` (`lib-efs-dirlist.s:800`) → `rom_space_maxspace` uses area 0's size
(0 in the test config, `$ff` in the default config). It subtracts
`$1800` and all file sizes, and shows the negative result.

*VICE*: test cartridge patched to `areas = 1` → the directory ends with
`64067 BLOCKS FREE.` (save correctly returns `$05`).

*Fix*: show 0 blocks free when `areas` ≠ 3.

The same underflow happens for a completely full r/w area: the free
space minus the rounding block becomes −1, shown as 65535.

**Fixed**: `rom_dirload_sm_freelow` shows 0 blocks free when there are
no r/w areas, and clamps a negative result to 0.

Verified in VICE (`work/m9test.s`: listing, fill the area with chrout,
listing again), on the test cartridge and on a variant with `areas = 1`:

| case | fixed | before the fix |
| ---- | ----- | -------------- |
| read-only configuration | `0 BLOCKS FREE.` | `64067 BLOCKS FREE.` |
| r/w area filled completely (`BIG`, 730 blocks) | `0 BLOCKS FREE.` | `65535 BLOCKS FREE.` |
| normal r/w area | `728 BLOCKS FREE.` | same |

### M10 – No recovery from interrupted operations

*By code*, except `EFS_validate`, which is confirmed in VICE.

- **Interrupted defragment** (reset or power loss after the copy, before
  the erase): both areas then contain a directory.
  `rom_config_prepare_config` picks area 1 whenever its first entry is
  used, so the old area may stay active. The directory listing shows
  both r/w areas. The next defragment copies into a non-erased area,
  where all writes fail, and the errors are ignored
  (`rom_defragment_copy_data`, `lib-efs-rw.s:722`).
- **Unclosed write file** (reset during chrout): the size stays
  `$ffffff`. Every later save then computes its position from this
  entry, and space calculations break.
- **`EFS_validate`** (`lib-efs.s:377`) only loads A = 5 and returns
  with C unchanged. *VICE*: called with C clear → A = 5, C clear; called
  with C set → A = 5, C set. The manual says it returns C set on corruption, so
  callers that follow the manual ("call EFS_defragment if EFS_validate
  returns an error") may never or always defragment, depending on C at
  call time.
- **`@` overwrite** scratches the old file before the new one is
  written. If the save then fails (disk full after the scratch, write
  error), the old file is lost.

**Partly fixed** (the `EFS_validate` part): until validation is
implemented, the stub returns A = 0 and C clear ("nothing found"),
independent of C at call time. That way programs that follow the manual
do not defragment on every start. `docs/manual.md` describes this. The
recovery issues above remain open.

Verified in VICE (`work/m10test.s`):

| call | fixed | before the fix |
| ---- | ----- | -------------- |
| `EFS_validate` with C clear | A = 0, C clear | A = 5, C clear |
| `EFS_validate` with C set | A = 0, C clear | A = 5, C set |

### M11 – Defragment callbacks may clobber X/Y

*By code.* In `rom_defragment_copy_data` the loop reads the source with
`lda abs,y` and Y = 0 (`efs_init_readef_rely`). The warning callback is
called from `rom_defragment_copy_data_destinc` (`lib-efs-rw.s:755`)
inside that loop, via `jmp (zp_var_x5)` (`lib-efs.s:1136`, `:1174`). A
callback that changes Y makes all following reads use the wrong address.
Neither the manual nor `efs-config.s` says that the callbacks must
preserve X and Y.

*Fix*: save and restore X/Y around the `jmp (zp_var_x5)` in the callback
helpers.

---

## Minor

- **m1 – long names** (`lib-efs.s:1993`, `rom_dirsearch_checkname`).
  A name longer than 16 characters is compared beyond the name field. If
  the mismatch happens after the 16th character, the `@next` loop
  (`cpx #$10`) never terminates normally and advances the read pointer by
  up to 256 bytes, skipping directory entries. Names > 16 should be
  rejected (or truncated) up front. The same applies to
  `rom_dirload_checkname` (`lib-efs-dirlist.s:480`). In VICE, loading
  the 17-character name `DATA567890123456X` (first 16 characters match
  an existing file) returned "not found" without a crash. The skipped
  entries only matter when the wanted file comes after the mismatch.
- **m2 – directory bounds.** `rom_dirsearch_find` only checks the
  directory boundary for non-deleted entries (`lib-efs.s:2060`ff). A
  directory filled to the end with deleted entries is scanned into the
  file data. `rom_dirload_checkboundary` (`lib-efs-dirlist.s:427`)
  hard-codes `$b8`, which is only correct for directories at `$a000`.
  The r/w directories at `$8000` end at `$9800`.
- **m3 – stale "active file" area.** `rom_filesave_blockedspace`
  (`lib-efs-rw.s:1163`) uses `rom_config_get_area_dirhigh_active_file`, but
  during `rom_filesave_conditions` the file-area bits still describe the
  previously opened file. It should use `rom_config_get_area_dirhigh`.
  This only affects the bounds check.
- **m4 – erase count.** `rom_defragment_erasearea` (`lib-efs-rw.s:430`) uses `size >> 3` as
  the loop counter. A configured size below 8 gives 0, and the loop then
  runs 256 times (erasing everything from the area start through the
  wrapped bank numbers, including bank 0). Sizes are not validated.
- **m5 – hard-coded bases.** `rom_defragment_copy_dir` (`lib-efs-rw.s:687`) stores
  `offset_high = pointer − $80` (or `− $a0` for hhhh) instead of
  `pointer − files_high`. `rom_filesave_begin` uses the directory bank as
  the files bank for the first file. Both only work because the test
  config has `dir bank = files bank` and `dir high = files high`.
- **m6 – end address** (*confirmed in VICE*). LOAD returns the address
  of the last byte (X/Y = `$3000` for the 1-byte file `DATA1` loaded to
  `$3000`). The KERNAL returns the
  address after the last byte. BASIC-style code (e.g. setting `$2d/$2e`)
  must add 1. The manual should state this explicitly.
- **m7 – smaller inconsistencies**
  - Verify mismatch returns C set with A = 0. Only `readst` tells
    `$10`.
  - Status `$80` ("file in r/w area") is overwritten by EOF (`$40`) on
    LOAD. *Confirmed in VICE* (`readst` = `$40` after loading `DELME15`).
  - `rom_command_begin` permanently moves `filename_address` /
    `filename_length` past the command prefix, so a second call without
    `setnam` uses the bare name.
  - `S` scratches only the first match of a wildcard name.
  - `EFS_format` does not check or reset `internal_state`.
  - The dirlist type table (`dirlist.s:380-392`) has 12 entries. Type
    values `$10-$1e` index past it.
  - `EFS_chrin` after EOF returns C set with A = 0 and no error code.
  - `EFS_chrout` destroys X (`rom_chrout_body`, `lib-efs-rw.s:202`,
    starts with `tax`); the KERNAL `CHROUT` preserves X and Y.
    *Confirmed in VICE* (X = `$5a` before, `$00` after `chrout $00`).
  - On "disk full", `EFS_chrout` returns A = `$40` (the status value,
    `lib-efs-rw.s:252`) instead of the error code `$48`; `error_byte` is
    correct. *Confirmed in VICE* (C4 test).
  - Open for writing reserves `$2000` + 2 bytes (`lib-efs-rw.s:381`). With less free space
    `open` fails ("disk full") even for small files. Larger files can be
    written as long as the area has room.
  - Loading into `$d000-$dfff` while I/O is visible (or over the EAPI
    copy) destroys the library state. This should be mentioned in the
    manual next to the `setnam` restriction.
  - `SHOW_INDICATE_ACTIVITY = 1` (default) changes `$d020` during every
    load/save/search, and the `indicate_load` macro clobbers X.

## Documentation (D1)

- `docs/manual.md` configuration table: bytes `39-3f` are "unused", but
  the default config in `lib-efs.s:208-211` and `libefs_config` define
  `actcall`/`actvector` there (marked "not implemented").
- (Done) `docs/manual.md`, `EFS_validate`: now states what the stub
  returns (see M10).
- `docs/memory.txt` still shows the old `LIB`/`EFS` configuration layout
  and old zero page notes.
- `lib-efs.i:85`: comment "bit 5 and 6" for `LIBEFS_FLAGS_FILE_AREA0` is
  wrong (bits 4 and 5).
- `docs/manual.md` does not describe the end address convention of
  `EFS_load` (m6), the new "command done" channel state after a scratch
  (C8), or the `$1e` error of `EFS_save` for invalid ranges (C7).
- (Done) PR #1's wrong explanation in `lib-efs.s` was removed with the C1
  fix.

---

## Second review (after the fixes, commit `dc8a186`)

A second full pass over the library after C1-C8 and M1-M9 were fixed:
my own re-read of all modules plus two independent reviews of
(a) `lib-efs.s`/`lib-efs-ram.s` and (b) `lib-efs-rw.s`, `-space.s`,
`-dirlist.s`, `-minieapi.s`. Everything marked *VICE* was reproduced on
the test cartridge with the programs in `work/r2*test.s`; flash damage
was measured by letting VICE write the flash back and comparing it with
`work/crtbanks.py`. Line numbers are those of commit `dc8a186`.

### Critical

#### S1 – Defragment copies one byte too many per file

`src/lib/lib-efs-rw.s:755-763` (`rom_defragment_copy_data`). The loop
is write → increment → `rom_filesave_decrease_size`; the counter
returns "done" only when it is already 0 *before* the decrement, so a
file of size S is copied as S+1 bytes and the destination pointer
advances S+1 times. `rom_filesave_transfer_data` (`:1568`) knows this
and decrements once "ahead"; the defragment loop does not.

Consequences: every copied file is followed by one stray byte (the byte
that followed it in the old area, i.e. the first byte of the next entry's
data, or `$ff`); the next save is placed by `rom_filesave_nextentry` at
`offset + size`, exactly on that stray byte; the space accounting counts
ΣS while the area really holds ΣS + N, so after many defragments a save
that passes the check can run past the area end (into bank 0 for an
area ending at bank 63; `EFS_save` has no bank check).

*VICE* (`work/r2ftest.s`): after a defragment the new directory reads
`DELME15 off $1800 size 17`, `DELME384 off $1812` (= 6161 + **1**),
`DELME640 off $1995` (+1), … Then: save `A1` (300 bytes from `$4000`),
save `B1` (load address `$4000`, first byte `$00`), scratch `B1`,
defragment, save `C1` from `$0801` → **`$19` write error** (the `$01`
cannot be programmed over the stray `$00`); see S6 for what is left.

*Fix*: one `jsr rom_filesave_decrease_size` before the loop, like
`transfer_data`.

**Fixed**: `rom_defragment_copy_data` decrements the counter once before
the loop (and copies nothing for a size of 0), like
`rom_filesave_transfer_data`.

*VICE* (`work/r2ftest.s`):

| | fixed | before the fix |
| - | ----- | -------------- |
| directory after defragment | `DELME384 off $1811` = previous end + 0, all files contiguous | every file + 1 |
| save `C1` after scratch/defragment, load it | save 0, load OK | save `$19`, entry live with `$ff` data (S6) |
| normal defragment (`work/m5test.s`) | OK | – |

#### S2 – Defragment has no bounds checks: a corrupt size programs bank 0 and the whole cartridge

`src/lib/lib-efs-rw.s:640-648`, `:744-763`, `:777-823`. The copy trusts
the size field of every live entry and increments the destination bank
without limit. An entry with size `$ffffff` — a write file never closed
because of a reset or power loss between `open(1)` and `close` (M10),
or a power loss during the first bytes of an `EFS_save` — makes the copy
run for 16.7 million bytes. After the destination area the bank counter
passes 63; the hardware maps bank 64 to bank 0. For an `hhhh`
destination that is ROMH of bank 0 (area 0 directory, EAPI, the libefs
configuration, the startup code), then banks 1, 2, … (area 0 files);
for an `llll` destination it is ROML of bank 0, libefs itself, and the
running copy loop crashes after about 3.8 KB. Flash programming only
clears bits, so this is unrecoverable without reflashing. `EFS_defragment`
is exactly what the manual recommends for recovery, and the automatic
defragment in save/open reaches the same code.

*VICE* (`work/r2btest.s`): `open(1) "UNCL"`, three `chrout`, then
`internal_state` cleared (as after a reset), `EFS_defragment`. After 15
minutes the copy was still running; the flash write-back shows **bank 0
ROMH: 7,737 bytes changed, banks 1-3 ROMH: ~8,100 each, bank 4 ROMH:
4,653** besides the destination area.

*Fix*: in `rom_defragment_copy` treat an entry whose `offset + size`
exceeds the area as corrupt (skip it, report it), clamp the destination
to the area end, and stop on write errors (S7).

**Fixed**: `rom_defragment_copy` now

- drops an entry whose size is not smaller than the source area
  (`size high byte ≥ area size >> 3`), counts it in
  `efs_defragment_skipped`, and returns A = 1 (`ERROR_FILE_SCRATCHED`,
  C clear) if any entry was dropped;
- computes the first bank after the destination area
  (`efs_defragment_endbank`, dir bank + size, size/2 for lhlh) and
  checks the destination bank before every byte;
- stops at the first write error (S7, copy part);
- on either abort, erases the partially written destination again (so
  the source stays the only valid area), restores the area flags and
  returns `ERROR_DIRECTORY_ERROR` (`$47`, C set). `rom_defragment_body`
  and the automatic defragment in `rom_filesave_conditions` propagate
  the error.

Two of the five unused IO2 bytes are used for the two new variables.

*VICE* (`work/r2btest.s`, `work/r2b2test.s`, flash write-back):

| | fixed | before the fix |
| - | ----- | -------------- |
| `UNCL` (size `$ffffff`) + `EFS_defragment` | returns A = 1, C clear after 9 s; no flash change outside the two areas; listing shows the 7 `DELME` files, `UNCL` gone, 728 blocks free; `DELME17K` loads | still copying after 15 min; bank 0 ROMH and banks 1-4 ROMH overwritten |
| normal defragment (`work/m5test.s`) | A = 0; files load back | – |

The abort path (destination full / write error) is verified by code only;
no input to the current layout reaches it before S1 is fixed.

#### S3 – `EFS_format` with an open file erases libefs or corrupts a later file

`src/lib/lib-efs-rw.s:200-214` (`rom_format_body`) does not check
`internal_state` (`rom_defragment_body:178-181` does).

(a) File open for reading: the format leaves `efs_io_byte` patched to
`jsr EAPIEraseSector` (`efs_init_eapierasesector`, called by
`rom_defragment_erasearea`). The next `EFS_chrin` (`lib-efs.s:624-636`)
calls `efs_io_byte` with A = 0 (from `lda status_byte / and #$40`) and
the caller's Y: `EAPIEraseSector(bank 0, Y)`. With Y = `$80` the 64 KB
sector of ROML banks 0-7 is erased: libefs and the first area 0 files.

*VICE* (`work/r2dtest.s`): `open(0) "DATA1"`, `EFS_format` → returns 0,
`chrin` with Y = `$80` → machine dead; write-back shows **bank 0 ROML:
6,042 bytes changed (erased), banks 1-7 ROML: ~8,160 each**.

(b) File open for writing: the format erases its directory entry; the
following `close` still programs the three size bytes into the erased
slot. The slot looks empty (flags `$ff`), a later save reuses it and
its size field is ANDed with the stale bytes.

*VICE* (`work/r2atest.s`): `open(1) "OP"` (slot 7), three `chrout`,
`EFS_format` (0), `close` (0), eleven saves of 300 bytes: the eighth
file `N7` is listed with **0 blocks** (size `302 & 3 = 2`).

*Fix*: refuse the format with `ERROR_FILE_OPEN` while a channel is open;
additionally re-initialise `efs_io_byte` to `EAPIReadFlashInc` at the
end of format and defragment.

**Fixed**: `rom_format_body` returns `ERROR_FILE_OPEN` while a channel is
open (like defragment), and both format and defragment reset
`efs_io_byte` to `EAPIReadFlashInc` before returning.

*VICE* (`work/s3test.s`):

| case | fixed | before the fix |
| ---- | ----- | -------------- |
| format while `DATA1` is open for reading, then `chrin` | format `$02`; `chrin` returns the next byte | format 0; `chrin` erases banks 0-7 ROML (6,042 + 7 × ~8,160 bytes changed) |
| format while `OP` is open for writing, then close, load | format `$02`; `OP` closes and loads back intact | format 0; a later file in slot 7 gets a corrupt size |
| format with nothing open, then open/chrin | 0; `chrin` reads normally | – |

#### S4 – `EFS_open` while a write channel is full clears the status; the next `chrout` writes into bank 0

`src/lib/lib-efs.s:671-681` (`rom_open_body`) zeroes `status_byte` and
`error_byte` *before* checking `internal_state`, and the "file open"
path leaves with status 0. `rom_chrout_body` (`lib-efs-rw.s:231-237`)
refuses further writes only via `status_byte & $40`, so the EOF/disk
full protection (C5) is undone by any rejected `open`. For an area
ending at bank 63 the next byte goes to EAPI bank 64 = hardware bank 0
ROML (libefs). M8 fixed this for `load`/`save`; `open` was missed.

*VICE* (`work/r2ctest.s`): `chrout` until disk full (`readst` `$40`),
`open(0) "DATA1"` → `$02`, `readst` now **0**, `chrout` → written:
write-back shows **bank 0 ROML: 1 byte changed** (`$8000`).

*Fix*: check `internal_state` before touching the status, as in
`rom_load_body:779-787`.

**Fixed**: `rom_open_body` checks `internal_state` first and returns
`ERROR_FILE_OPEN` without touching `status_byte`/`error_byte`.

*VICE* (`work/r2ctest.s`, flash write-back):

| step | fixed | before the fix |
| ---- | ----- | -------------- |
| `open(0)` during a full write channel | `$02`; `readst` stays `$40` | `$02`; `readst` becomes 0 |
| next `chrout` | `$19`, C set, nothing written | writes: bank 0 ROML, 1 byte changed |

#### S5 – `EFS_save` of 64 KB or more passes the space check

`src/lib/lib-efs-rw.s:1058-1064` (`rom_filesave_addsize`) adds the 2
address bytes to the 16-bit size and drops the carry out of the high
byte: end − start = `$fffe` or `$ffff` gives a size of 0 for the checks.
`rom_filesave_begin` then computes the real size (`$010000`) and
`transfer_data` writes 65,538 bytes with no bank check.

*VICE* (`work/r2gtest.s`): fill the area with `chrout` until 30,000 bytes
are free, then `save` `$0001-$fffe` → the save is accepted and the
machine crashes; write-back shows **bank 0 ROML: 5,434 bytes changed**
(libefs overwritten).

*Fix*: compute the size once in 24 bits (or reject end − start ≥ `$fffe`).

**Fixed**: `rom_filesave_addsize` keeps the carry of the "+2" and adds
it to the high byte of the 24-bit sum.

*VICE* (`work/r2gtest.s`, 30,000 bytes free, save of `$0001-$fffe`):
fixed → `$48` disk full, no flash change; before the fix → accepted,
machine crashed, bank 0 ROML 5,456 bytes changed. The C6 save test
still passes.

### Major

#### S6 – A failed save leaves a live, corrupt directory entry

`src/lib/lib-efs-rw.s:372-374`: name, flags `$61`, bank, offset and
size are written before the data. A write error in
`rom_filesave_transfer_data` (`:1595-1599`) returns `$19` with the
entry live: the listing shows it, `load` returns `$ff` data, the name is
taken (`FILE_EXISTS`). The library could always repair this, because
programming `$61` → `$60` (scratch) only clears a bit.

*VICE* (S1 scenario): after the failed save of `C1`, `load "C1"` →
A = 0, end `$512b` (full size), first data byte `$ff`.

*Fix*: scratch the entry in the error paths of `transfer_data` and of
`rom_filesave_chrin_close` (S7).

**Fixed** (with the remaining S7 parts): the new
`rom_filesave_scratch_entry` programs the flags of the entry whose size
field address is kept in `filename_address`/`filename_length` to `$60`
and returns `ERROR_WRITE_ERROR`. `rom_save_body` records the entry
before the data transfer (as the chrout path already did), and
`rom_filesave_transfer_data` calls the helper on a write error.
`rom_filesave_transfer_dir_finish` checks the three size writes and
calls it too, and `rom_filesave_chrin_close` passes the result on, so
`EFS_close` returns `$19` with C set when the size cannot be written.

*VICE* (`work/s6btest.s`, flash bytes pre-programmed in the image so
that the next write fails):

| case | fixed | before the fix |
| ---- | ----- | -------------- |
| save `A1` whose third byte hits a pre-programmed byte | `$19`; `load "A1"` → `$04` (entry scratched) | `$19`; `load "A1"` → 0 (live entry with wrong data) |
| open(1) `W`, 5 bytes, close, with the size byte of its slot pre-programmed | close `$19`, C set; `W` not listed, 726 blocks free | close 0; `W` listed with 65,280 blocks (size `$ffff00`), 982 blocks free |

#### S7 – Write and erase errors are ignored in defragment, erase and close

- `src/lib/lib-efs-rw.s:759` (`;bcs @error ignore errors :(`): the copy
  continues after a failed write, and `rom_defragment_body` then erases
  the only good copy. With a non-blank destination (interrupted earlier
  defragment, M10) or worn flash this is silent data loss.
- `rom_defragment_erasearea` (`:491-493`, `:540-542`) never tests C from
  `EAPIEraseSector` and returns success; a failed erase leaves both areas
  populated (M10 state).
- `rom_filesave_transfer_dir_finish` (`:1469-1477`) ignores C of the
  three size writes; `close` returns 0 while the size stays `$ffffff`
  (the precondition of S2).

*By code.* The copy should stop at the first error and leave the source
alone; close should scratch the entry when the size cannot be written.

**Fixed**: the copy stops at the first write error (with S2, the
destination is erased again), `rom_defragment_erasearea` returns
`ERROR_WRITE_ERROR` when `EAPIEraseSector` fails and `EFS_defragment`,
`EFS_format` and the automatic defragment report it, and a failed size
write at close scratches the entry and returns `$19` (verified with S6).
Erase errors cannot be produced in VICE; that part is by code.

#### S8 – `chrin` signals EOF one byte late (differs from the KERNAL)

`src/lib/lib-efs.s:636-641`. EOF is set only when `EAPIReadFlashInc`
returns C set, which (EAPI and MiniEAPI alike) happens on the (N+1)th
read for a length of N. The KERNAL sets status `$40` together with the
last real byte. The common idiom "chrin, store, readst, loop while 0"
stores one extra `$00` byte with libefs.

*VICE* (`work/r2etest.s`, `DATA1` = 2 address bytes + 1 data byte):
`chrin` ×3 → bytes `$00 $30 $64` with C clear and `readst` 0; 4th
`chrin` → A = 0, C set, `readst` `$40`. (`docs/todo.txt` lists this as
"no"; it should at least be documented in the manual.)

**Fixed**: `rom_fileload_begin` sets the EAPI length to size − 1, so the
read that returns C set carries the last valid byte. `EFS_chrin`
delivers that byte with status `$40`; the next call returns A = 0 with
C set as before. Load and verify store/compare the last byte, and a
file without data bytes (size ≤ 2, detected in `rom_fileload_address`)
ends with the end address = start − 1 (this also fixes S12). The
directory `chrin` flags its last byte the same way (state `sm_end`).

*VICE* (`work/s8test.s`, KERNAL-style loop "chrin, store, readst, loop
while 0"; `work/r2etest.s`):

| case | fixed | before the fix |
| ---- | ----- | -------------- |
| `DATA1` (3 bytes) | 3 bytes, the third with `readst` `$40`; the next `chrin` → A = 0, C set | 4 bytes (an extra `$00`) |
| directory via `chrin` | 810 bytes = exactly the listing loaded with `load "$"` | 811 bytes |
| verify of `E0` (size 2) | end `$4fff` (S12) | `$50fe` |

The load/save regression tests (`c6`, `m1`, `m8`) pass unchanged.

#### S9 – Entries with type `$1f` are a terminator for some code and a file for other code

`efs_directory_search` (`lib-efs.s:2085-2087`) and the dirlist
(`dirlist.s:457`) stop at `flags & $1f == $1f`; `rom_space_usedspace`
(`space.s:237-240`), `rom_filesave_blockedspace` (`:1191`),
`rom_filesave_freedirentries` (`:943`), `rom_filesave_nextentry`
(`:1641`) and `rom_defragment_copy` (`:617-621`) stop only at `$ff` and
treat such an entry as a live file. A partially programmed flags byte
(power loss during a save) is therefore invisible to `load` and `$`,
but is counted, copied verbatim by defragment (after which everything
behind it disappears for `load`), and if its size is `$ffffff` triggers
S2. *By code.* One shared "is terminator / is live" test is needed.

### Minor

- **S10 – exact-fit save refused.** `rom_filesave_checksize`
  (`rw.s:997`) treats used + new ≥ max as full; a file ending exactly at
  the area end is valid (chrout accepts it, C4 test). *VICE*
  (`work/r2atest.s`): 100 bytes free, save of 98 data bytes → `$48`;
  97 → OK.
- **S11 – `chrin` on a directory destroys X and Y** (`dirlist.s:228`,
  `:309-312`); file `chrin` preserves them, the KERNAL always does.
  *VICE*: X `$5a`/Y `$a5` → `$ff`/`$00` after a directory `chrin`,
  unchanged after a file `chrin`.
- **S12 – verify of a file without data bytes returns a wrong end
  address.** `efs_init_readmem` (`lib-efs.s:411`) leaves Y = `$ff`;
  `rom_fileload_verify` sets Y = 0 only after the first successful read.
  *VICE* (`work/r2etest.s`): file `E0` (size 2): verify → X/Y =
  `$50fe`, load → `$4fff`. **Fixed** with S8.
- **S13 – `EFS_save` consumes the file name.** `rom_filesave_transfer_dir`
  (`rw.s:1420`) decrements `filename_length` to 0 (or the remainder for
  names > 16). A second `EFS_save` without `setnam` fails with `$08`;
  with `rom_command_begin` also moving `filename_address` (m7), a
  program must call `setnam` before every call. *By code.*
- **S14 – command parser reads past short names.** `rom_command_begin`
  (`lib-efs.s:1538-1570`) inspects name bytes 1-2 regardless of
  `filename_length` and decrements the length Y+1 times without a lower
  bound: a 2-character name followed by `:` in memory becomes a command
  with `filename_length` = `$ff` (m1 desync, possibly scratching a wrong
  file); a length of 0 or 1 can pick up stale `0:`. *By code.*
- **S15 – `@` in save ignores the scratch result.**
  `rom_command_save_process` (`rw.s:1687-1696`) falls through regardless
  of C; `@0:X` with X in area 0 ends as `FILE_EXISTS` instead of
  "write protected". *By code.*
- **S16 – the directory holds 254 files.** `rom_filesave_freedirentries`
  (`rw.s:935-947`) reports "full" when entries 0-253 are used although
  slot 254 is free (255 is the terminator). *By code.*
- **S17 – garbage error code after a failed post-defragment check.**
  `rom_filesave_conditions:899-903` branches to `@error` with A = a size
  byte (same pattern as M7); hard to reach. *By code.*
- **S18 – `@` overwrite checks the space before scratching.**
  `rom_save_body` runs the conditions before the `@` scratch, so the
  file about to be replaced still counts as used: replacing a large file
  on a nearly full area fails with "disk full". *By code.*
- **S19 – `EFS_init_eapi` ignores EAPIInit's result** (`lib-efs.s:376-377`,
  unconditional `clc`): an unsupported flash is reported as success;
  only the `eapi` signature is checked. *By code.*
- **S20 – API nits** (*by code* unless noted): `?` matches the NUL
  padding, so `DATA?` matches `DATA` (`lib-efs.s:2040-2056`);
  `setlfs`/`setnam` return `$02` while a channel is open, the KERNAL
  never rejects them (`:570`, `:597`); `@0:` is a syntax error for read
  open and load, a 1541 ignores it (`:1629`); `EFS_util` mode 0 is
  accepted as setlfs although the comment says 1-15; `EFS_util` `$10`
  returns the chrout byte counter while a write channel is open;
  `load`/`save` rejected with "file open" return X/Y unchanged;
  "blocks free" is one block low (`space.s:170-178` subtracts a block
  although max is a multiple of 256: 186,664 free bytes = 729 blocks,
  shown as 728 — *VICE*, M9 table).
- **S21 – area geometry assumptions** (extends m4/m5): the chrout end
  bank is `dir_bank + size` (`rw.s:1495-1516`), erase and copy_dir use
  fixed `$80`/`$a0`, the offset reduction assumes `files_high` =
  `$80`/`$a0`. Correct for the three test layouts, wrong for
  `files_bank ≠ dir_bank`, lhlh with `files_high = $a0`, or an lhlh size
  that is not a multiple of 16. Sizes and modes are never validated.
  *By code.*
- **S22 – no commit marker.** `EFS_save` writes the complete entry
  before the data; a power loss during the data leaves an entry that
  looks valid with `$ff` data, which nothing can detect later (also the
  reason S6 is possible). A marker bit cleared last would make such
  entries recognisable. *Design.*

### Documentation and comments (S23)

- The manual must state for the defragment callbacks: preserve X and Y
  (M11), do not use `$35-$3f`, and do not call any libefs function —
  `EFS_readst` in particular is not executable during a defragment,
  because its `lda #` opcode and its `rts` are used as temporary
  variables (`efs_temp_var1/2`, `lib-efs.s:538-546`); an IRQ handler
  calling `$df30` has the same problem.
- RUN/STOP+RESTORE during any libefs call (minutes during a defragment)
  makes the KERNAL NMI handler jump through `($a002)`, which is the
  cartridge's ROMH at that moment.
- Memory rules: `EFS_save` and verify read C64 memory with the caller's
  `$01` (data under BASIC/KERNAL ROM needs `$35`/`$36`, I/O must stay
  visible); `EFS_load` writes with `$01 = $37`, so loading into
  `$d000-$dfff` writes to I/O and to the library's own RAM.
- `src/lib/config.i:18`: `SHOW_INDICATE_ACTIVITY = 1` flashes `$d020`
  on every byte; a release build should have it off.
- Comments that contradict the code: `lib-efs.s:1601`/`:1665` (".C set:
  error (.Z set) or stop (.Z clear)" is reversed), `:776` ("no internal
  state will be set": a `$` load sets `$01` until the transfer ends),
  `:1704` (`rom_fileload_chrout_prepare` prepares the chrin channel),
  `:1968` ("position is at flags": one past), `lib-efs-ram.s:18` ("8k
  mode": `EFS_init_eapi` needs 16k), `:72` ("01-15"), `:165` ("`$80`:
  device not present" is `STATUS_RW`), `manual.md:316` ("does not use
  sei": `rom_config_get_value` does, harmlessly), `dirlist.s:680-698`
  (`rom_compare16` comment says ≥ ⇒ C set, code is the opposite; the
  three call-site comments too), `dirlist.s:438-439` (state numbers),
  `rw.s:553`, `:929`, `:1172`, `:1226`/`:1239`, `space.s:218`,
  `minieapi.s:132`, `lib-efs.i:25` (`01:0:1FFF` → `01:0:0000`).

### Checked and found clean

The `$df00` trampolines and the `efs_setstartbank_ext` patch window,
`efs_init_eapi_body` stack arithmetic, `rom_config_get_value`, the
callback return-address push, the `efs_readef_*` pointer arithmetic,
`rom_filesave_begin`'s bank/offset conversion for all three modes (and
the C6 fix), the chrout 24-bit counter and end-bank detection (C4), the
`internal_state` decoding in `chrin`/`chrout`/`close` including
`STATE_COMMAND_DONE`, the M8 entry checks, the automatic defragment's
re-derivation of area flags and config, the defragment pointer swap and
source-mode use (C3), the dirlist state machine's counter reuse, and
MiniEAPI's slot layout and `ReadFlashInc` semantics.

### Suggested order

1. S3, S4, S5, S2 (flash corruption of the library itself; S3/S4 are
   one-line guards).
2. S1 (every defragment corrupts the layout) together with S6/S7.
3. S8 (API contract), S9, then the minor items and the documentation.

---

## Tools, Makefile and test cartridge

These are from a separate review of `tools/`, `src/ef/` and `src/prg/`.
"confirmed" means reproduced by running the tool, or visible in the
compiled code.

| ID | Severity | Status | Location | Finding |
| -- | -------- | ------ | -------- | ------- |
| T1 | major (test) | confirmed | Makefile:117-118, 128-130, 145-147 | `menu.prg` is added to `files.list` only by the `menu.prg` recipe (`echo >>`). If `files.list` is rebuilt while `menu.prg` is up to date, MENU is missing from the cartridge. `init.s` ignores the load error and jumps to `$0801`. Every rebuild of `menu.prg` appends another line. `BANKMODE`/`BANKMODE_VALUE` must be changed together and do not trigger rebuilds. |
| T2 | major (test) | confirmed | src/ef/menu.cfg | The C stack starts at `$3e00` (end of MAIN) and grows down into BSS (`$3d00-$3d55`). The reserved STACK area `$3e00-$3fff` is never used. |
| T3 | major (test) | by code | src/ef/menu.c `longtest` | Tests less than its comment claims. It uses one file and verifies it against the data just loaded from it (always equal); only the counter is checked. The first save without `@0:` fails on a second run. `%d` is used with a `uint32_t`. |
| T4 | major (test) | by code | src/ef/menu.c | Loading with secondary 1 (load address `$3000`) of files larger than `$d00` bytes overwrites the menu's BSS/stack. `data1000k` relocated runs into I/O and the library at `$df00`. `readfile` has no bound either. |
| T5 | minor | confirmed | src/ef/menu.c:563,569,575,581 | `repaint == true;` (comparison) instead of `=`, so no redraw after Directory/Scratch/Save/Format. |
| T6 | minor | by code | src/ef/util.c:164-167 | `gettextxy`: DEL at position 0 underflows `n` to 255. A further DEL writes outside the 17-byte buffer. Cancel returns the edited text like Enter. |
| T7 | minor | confirmed | tools/mkefs.py:48-51,75 | Dedup never works: a `hashlib.sha256` object is used as dict key (identity comparison). If it is ever fixed, it must stay off for r/w images, because `rom_filesave_nextentry` assumes the last entry ends the used data. |
| T8 | minor | confirmed | tools/mkefs.py:85-86 | The duplicate-name check is dead (`entries_directory` is never filled) and would raise `TypeError` (str + dict). |
| T9 | minor | confirmed | tools/mkefs.py:54 | `>= maxsize` rejects data that exactly fits `-s`. |
| T10 | minor | confirmed | tools/mkefs.py:94,105; mkbin.py:129-130 | The directory holds 255 files (one slot is needed for the terminator; this is fine but should be documented). The mkbin `hh` shift is applied only when the map gives an explicit address. The mkbin format comment does not match the parser. |
| T11 | minor | by code | tools/mkefs.py, mkdata.py | No check of the 64-bank limit; default `-s` is wrong for ll/hh. Fragile list parsing (empty line, `01`). `random.randbytes` needs Python 3.9 (README says 3.6). `-s 0` crashes. |
| T13 | minor | confirmed | tools/mkefs.py | Files in the generated images are placed with a one-byte gap after each file (`DELME15` offset `$1800` size 17, `DELME384` offset `$1812`). libefs places the next save at `offset + size` of the last entry, i.e. on the gap byte (harmless, it is blank), but the space accounting counts one byte less per file than is used. |
| T12 | minor | by code | src/ef/init.s:229-256; src/prg/direfs.s:68-76; src/ef/efs-wrapper.s | `init.s` checks no results and never calls `EFS_validate`. `direfs` does not set VARTAB after loading `$`, and does not check that the cartridge is present. `TIMER_get_system` returns the bytes swapped (unused). `SYS_readdir` leaves a subroutine via `jmp` (unused). The `efs-config.s` comments for `BANKMODE=2` have llll/hhhh swapped. |

The 24-byte directory entries produced by `mkefs.py` were checked
against the library's interpretation for area 0 (lh) and the r/w area in
ll, lh and hh mode. All files resolve to the correct data.

---

## Fix history and suggested order for the rest

Fixed on `main`, each verified in VICE:

| commit | items |
| ------ | ----- |
| `564eb31` | C1, C2 |
| `f208146` | C3 |
| `eea4b14` | C4 |
| `40bef68` | C5 |
| `337ed59` | C6 |
| `9c0dd25` | C7, M7 |
| `ae9949a` | C8 |
| "Fix verify flag staying set after a verify" | M1 |
| "Report scratch errors with carry set" | M2 |
| "Fix command prefix parsing for names crossing a page" | M3 |
| "Fix drive number check in command prefixes" | M4 |
| "Keep open files intact when load or save is rejected" | M8 |
| "Preserve zero page in close, defragment and format" | M5 |
| "Refuse write operations when MiniEAPI is installed" | M6 |
| "Fix blocks free for read-only and full areas" | M9 |
| "Make the EFS_validate stub return a defined result" | M10 (part) |
| "Refuse EFS_format while a channel is open" | S3 |
| "Keep the channel status when EFS_open is rejected" | S4 |
| "Fix space check for saves of 64 KB or more" | S5 |
| "Guard defragment against corrupt sizes and destination overflow" | S2, S7 (copy) |
| "Fix defragment copying one byte too many per file" | S1 |
| "Scratch the entry when a save or the size write at close fails" | S6, S7 |
| "Report end of file together with the last byte" | S8, S12 |

Most of the critical items were one-instruction branch or flag errors
(`bne` instead of `bcc`, `beq` instead of `bne`, `plp` restoring the
wrong flags).

Suggested order for the remaining items: see "Suggested order" at the
end of the second review (S3/S4/S5/S2 first, then S1 with S6/S7, then
S8/S9, then the minor items, M10/M11, documentation, tools and test
cartridge).

## How the findings were verified

**VICE (current method).** The test cartridge (`make
build/test-libefs.crt`) is run in VICE 3.9 (`x64sc`, warp mode, headless
via `xvfb-run`) and controlled through the remote monitor. Two drivers
in the gitignored `work/` folder use only the Python standard library:

- `work/vrun.py` types keys into the test menu and takes screenshots.
- `work/vprg.py` loads a small ca65 test program into the running
  menu, starts it with `g`, waits for its "done" flag and reads back its
  result bytes.

The test programs are `work/c4test.s` … `work/c8test.s` and
`work/m1test.s` … `work/m10test.s` for the fixes, `work/reeval.s` for
the re-evaluation of the open items, and `work/r2[a-g]test.s` for the
second review. Each fix was compared against a build without the fix
(control). `work/mkcarts.sh` builds the fix/control cartridges,
`work/runtest.sh` runs a test on both.

Pitfall: VICE writes the flash contents back into the `.crt` on exit
(EasyFlash write-back). The drivers therefore run a throwaway copy with
`+easyflashcrtwrite`. For the C8 test, write-back was used on purpose and
the written cartridge was compared with the original by
`work/crtdiff.py` (byte list) and `work/crtbanks.py` (changed bytes
per bank), which is how the flash damage of S2-S5 was measured.

**Initial review (historical).** The first round of findings was
reproduced with a one-off Python emulator built for the review:

- the `py65` 6502 core;
- C64 `$01` and PLA mapping for 16k, 8k, ultimax and cartridge-off modes;
- EasyFlash `$de00`/`$de02`/`$df00` RAM;
- two AM29F040 flash chips with the unlock, program, sector-erase and
  autoselect command state machine (programming can only clear bits).

It ran the original EAPI driver and libefs code unchanged and called
the public entry points like a program would. It is not part of the
repository and was not used for anything after the initial review.
Every item marked "confirmed" or "fixed" has since been reproduced in
VICE. Regression tests for libefs are to be done in VICE only.
