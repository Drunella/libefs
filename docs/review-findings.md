# libefs code review – findings

Review of libefs 1.0.0 (commit `ff7d2d4`). How the code works is described
in [architecture.md](./architecture.md).

Last re-evaluation: after the fixes up to commit `ae9949a` (C1-C8, M7).
Line numbers of open items refer to that state; for fixed items they
refer to the original code.

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
| M4 | major | confirmed | Drive-number check accepts `'`…`0` instead of `0`…`9` |
| M5 | major | confirmed | `EFS_close` (write), `EFS_defragment` and `EFS_format` clobber zero page `$35-$3f` |
| M6 | major | confirmed | `EFS_save` with MiniEAPI reports success but writes nothing |
| M7 | major | **fixed** | Zero-length save returns a garbage error code (low byte of the end address) |
| M8 | major | confirmed | `EFS_save` while a file is open returns "file open" but closes that file |
| M9 | major | confirmed | "Blocks free" is garbage for read-only configurations |
| M10 | major | partly confirmed | No recovery from an interrupted defragment or an unclosed write file; `EFS_validate` is a stub that does not even set C (confirmed) |
| M11 | major | by code | Defragment callbacks must preserve Y (and should preserve X), which is not documented or enforced |
| m1 | minor | by code | Names longer than 16 characters can desynchronise the directory scan |
| m2 | minor | by code | Directory bounds are not checked for deleted entries; dirlist uses a hard-coded `$b8` bound |
| m3 | minor | by code | `rom_filesave_blockedspace` uses the stale "active file" area |
| m4 | minor | by code | `rom_defragment_erasearea` with size < 8 erases 256 sectors |
| m5 | minor | by code | Hard-coded `$80`/`$a0` file base and dir bank used as files bank |
| m6 | minor | confirmed | LOAD returns the last address, not last + 1 like the KERNAL |
| m7 | minor | partly confirmed | Various smaller API inconsistencies (see list) |
| D1 | doc | – | Documentation mismatches |
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
a directory command); `load "/:DATA1"` → `$1e` (`/` accepted as drive
number, then "syntax error").

*Fix*: `sec; sbc #$30; cmp #$0a; bcs @nomatch`.

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

### M9 – "Blocks free" is garbage for read-only configurations

`rom_dirload_sm_freelow` (`lib-efs-dirlist.s:800`) → `rom_space_maxspace` uses area 0's size
(0 in the test config, `$ff` in the default config). It subtracts
`$1800` and all file sizes, and shows the negative result.

*VICE*: test cartridge patched to `areas = 1` → the directory ends with
`64067 BLOCKS FREE.` (save correctly returns `$05`).

*Fix*: show 0 blocks free when `areas` ≠ 3.

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
- `docs/manual.md`, `EFS_validate`: says C is set on corruption, while
  the code is a stub (see M10).
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

Most of the critical items were one-instruction branch or flag errors
(`bne` instead of `bcc`, `beq` instead of `bne`, `plp` restoring the
wrong flags).

Suggested order for the remaining items:

1. M1, M2, M3, M4, M8: small, local fixes in the command and load/save
   entry code. M3 can scratch the wrong file.
2. M5 (zero page) and M6 (MiniEAPI writes): API contract.
3. M9 and the `chrout` return value / X register (m7).
4. M11 (save X/Y around the callbacks), then robustness (M10:
   `EFS_validate`, recovery after an interrupted defragment).
5. Remaining minor items, documentation (D1), tools and test cartridge
   (T1-T12).

## How the findings were verified

**VICE (current method).** The test cartridge (`make
build/test-libefs.crt`) is run in VICE 3.9 (`x64sc`, warp mode, headless
via `xvfb-run`) and controlled through the remote monitor. Two drivers
in the gitignored `work/` folder use only the Python standard library:

- `work/vrun.py` types keys into the test menu and takes screenshots.
- `work/vprg.py` loads a small ca65 test program into the running
  menu, starts it with `g`, waits for its "done" flag and reads back its
  result bytes.

The test programs are `work/c4test.s` … `work/c8test.s` for the fixes,
and `work/reeval.s` for the re-evaluation of the open items. Each fix
was compared against a build without the fix (control).

Pitfall: VICE writes the flash contents back into the `.crt` on exit
(EasyFlash write-back). The drivers therefore run a throwaway copy with
`+easyflashcrtwrite`. For the C8 test, write-back was used on purpose and
the written cartridge was compared with the original by
`work/crtdiff.py`.

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
