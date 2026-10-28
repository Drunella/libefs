# libefs code review – findings

Review of libefs 1.0.0 (commit `ff7d2d4`). How the code works is described
in [architecture.md](./architecture.md).

**Status**:

- **confirmed**: reproduced by running the real, unmodified library
  binary in a scripted 6502 + EasyFlash emulator (see the last section).
  C1 and C3 were also reproduced on the real test cartridge in VICE 3.9.
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
| C5 | critical | confirmed | `EFS_chrout` keeps writing after "disk full" / EOF |
| C6 | critical | confirmed | `EFS_save` stores a wrong size when (end − start) mod 256 = 255; the file is corrupt |
| C7 | critical | confirmed | `EFS_save` with end < start writes a ~64K garbage file |
| C8 | critical | confirmed | `open(1)` with an `S:` command followed by `close` programs flash at a garbage address |
| M1 | major | confirmed | Verify flag is never cleared; every later load is a verify |
| M2 | major | confirmed | Scratch errors (write protected, write error) are swallowed, and the channel stays open |
| M3 | major | confirmed | Command prefix parsing loses the carry: wrong name pointer when the name crosses a page |
| M4 | major | confirmed | Drive-number check accepts `'`…`0` instead of `0`…`9` |
| M5 | major | confirmed | `EFS_close` (write), `EFS_defragment` and `EFS_format` clobber zero page `$35-$3f` |
| M6 | major | confirmed | `EFS_save` with MiniEAPI reports success but writes nothing |
| M7 | major | confirmed | Zero-length save returns a garbage error code (low byte of the end address) |
| M8 | major | confirmed | `EFS_save` while a file is open returns "file open" but closes that file |
| M9 | major | confirmed | "Blocks free" is garbage for read-only configurations |
| M10 | major | by code | No recovery from an interrupted defragment or an unclosed write file; `EFS_validate` is a stub that does not even set C |
| M11 | major | by code | Defragment callbacks must preserve Y (and should preserve X), which is not documented or enforced |
| m1 | minor | by code | Names longer than 16 characters desynchronise the directory scan |
| m2 | minor | by code | Directory bounds are not checked for deleted entries; dirlist uses a hard-coded `$b8` bound |
| m3 | minor | by code | `rom_filesave_blockedspace` uses the stale "active file" area |
| m4 | minor | by code | `rom_defragment_erasearea` with size < 8 erases 256 sectors |
| m5 | minor | by code | Hard-coded `$80`/`$a0` file base and dir bank used as files bank |
| m6 | minor | confirmed | LOAD returns the last address, not last + 1 like the KERNAL |
| m7 | minor | by code | Various smaller API inconsistencies (see list) |
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

**Fixed** (branch `fix/defragment-callbacks`): the PR #1 code is removed
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

**Fixed** (branch `fix/defragment-callbacks`): `rom_config_get_value`
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

### C7 – `EFS_save` with end < start is not rejected

`src/lib/lib-efs-rw.s:1000-1017` (`rom_filesave_checkzero`): the
"less than" and "greater" branches both end in `clc`, so only
end = start is rejected. With end < start, all 16-bit subtractions wrap
and libefs writes a file of about 64K from wrapping RAM.

*Reproduced*: `save` with start `$4100`, end `$4000` → success, the
directory entry has size 65282.

*Fix*: return C set for end < start (`ERROR_SYNTAX_ERROR_30` or similar).

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

---

## Major

### M1 – Verify flag is never cleared

`src/lib/lib-efs.s:752-756` sets `LIBEFS_FLAGS_VERIFY` with `ora`. It is
only cleared when `EFS_util` setlfs overwrites `efs_flags`. After one
verify, every later `EFS_load` with A = 0 verifies instead of loading,
unless setlfs is called first.

*Reproduced*: verify `DATA1024` (mismatch), then load with A = 0 →
status `$10`, memory untouched.

*Fix*: clear the bit at the start of `rom_load_body` (`and #$ff - LIBEFS_FLAGS_VERIFY`).

### M2 – Scratch errors are swallowed

`src/lib/lib-efs.s:1606-1614`, `1634-1637`. After `rom_scratch_process`
the code always jumps to `@stop` (`lda #0; sec`). `rom_open_body` treats
"C set, Z set" as "stop, no error" and clears C. So `ERROR_WRITE_PROTECTED`
(file in area 0) and `ERROR_WRITE_ERROR` come back with C clear.
`internal_state` also stays "open", so a following `chrin` reads from a
stale EAPI pointer instead of returning "file not open".

*Reproduced*: `open "S:DATA1"` → A = `$1a`, C = 0.
`open "S0:DELME15"` then `chrin` → returns a byte with C clear. With
MiniEAPI, scratch returns `$19` with C clear.

### M3 – Command prefix: carry lost when advancing the name pointer

`src/lib/lib-efs.s:1573-1578` (`rom_command_begin`), same pattern as C6:

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

*Reproduced*: `"S0:DELME15"` stored at `$33fe` → file not found (looks at
`$3301`).

### M4 – Drive number check accepts the wrong characters

`src/lib/lib-efs.s:1553-1557`:

```
        clc
        adc #$ff - $30        ; lower bound $30
        adc #$39 - $30 + $01  ; upper bound $39
        bcc @nomatch
```

The accepted range is `$27`-`$30` (`'`, `(`, `)`, `*`, `+`, `,`, `-`, `.`,
`/`, `0`), not `0`-`9`.

*Reproduced*: `"$1:DATA1*"` is not treated as a directory command (the
file `$1:DATA1*` is searched instead), and `"/:DATA1"` gives a syntax
error instead of "not found".

*Fix*: `sec; sbc #$30; cmp #$0a; bcs @nomatch`.

### M5 – Zero page `$35-$3f` is not preserved by some calls

- `EFS_close` after writing: `rom_filesave_chrin_close` calls
  `rom_config_prepare_config` and writes `$35/$36` (rw.s:409-414).
- `EFS_defragment` and `EFS_format` (ROM calls `$8009`/`$800c`) use
  `$35-$3f` without `backup_zeropage`.

*Reproduced*: `$35-$3f` filled with `$a5` → after open/chrout/close
`$35/$36` = `$18 $bb`; after `EFS_format`, `$35-$38` and `$3a` are
changed. Directory chrin/close keep the zero page intact.

These locations are BASIC/KERNAL temporaries, and cc65 programs or games
may use them as well. Load, save, open and chrin restore them, so callers
will assume close does too.

### M6 – `EFS_save` / chrout with MiniEAPI report success but write nothing

MiniEAPI has no `EAPIWriteFlashInc`. Its slot `$df95` is the body of
`EAPISetBank` (`src/lib/lib-efs-minieapi.s:131-134`). It sets the bank
shadow and `$de00` to the data byte and returns with C unchanged (clear).
`rom_filesave_conditions` does not know that it runs on MiniEAPI.

*Reproduced*: `save` with MiniEAPI → A = 0, C = 0, 0 flash writes. The
file cannot be loaded afterwards.

*Fix*: make the MiniEAPI write entries return C set (e.g. `sec; rts`
stubs), or remember in `efs_flags` which EAPI was installed and reject
writes with `ERROR_WRITE_PROTECTED`.

### M7 – Zero-length save returns garbage in A

`rom_filesave_checkzero` (rw.s:1015-1017) returns C set with A = low
byte of `io_end_address`. `rom_filesave_conditions` stores A in
`error_byte`.

*Reproduced*: save `$4012-$4012` → A = `$12`, C = 1.

### M8 – `EFS_save` while a file is open closes that file

`rom_save_body` `@leave` (rw.s:354-357) always sets `internal_state = 0`,
also in the "file open" error path.

*Reproduced*: `open "DATA1"`, `save` → error 2. A following `chrin`
returns error 3 (not open).

### M9 – "Blocks free" is garbage for read-only configurations

`rom_dirload_sm_freelow` → `rom_space_maxspace` uses area 0's size
(0 in the test config, `$ff` in the default config). It subtracts
`$1800` and all file sizes, and shows the negative result.

*Reproduced*: test cartridge with `areas = 1` → `64067 BLOCKS FREE.`

*Fix*: show 0 blocks free when `areas` ≠ 3.

### M10 – No recovery from interrupted operations

*By code.*

- **Interrupted defragment** (reset or power loss after the copy, before
  the erase): both areas then contain a directory.
  `rom_config_prepare_config` picks area 1 whenever its first entry is
  used, so the old area may stay active. The directory listing shows
  both r/w areas. The next defragment copies into a non-erased area,
  where all writes fail, and the errors are ignored (rw.s:731).
- **Unclosed write file** (reset during chrout): the size stays
  `$ffffff`. Every later save then computes its position from this
  entry, and space calculations break.
- **`EFS_validate`** (`lib-efs.s:338-343`) only loads A = 5 and returns
  with C unchanged. The manual says it returns C set on corruption, so
  callers that follow the manual ("call EFS_defragment if EFS_validate
  returns an error") may never or always defragment, depending on C at
  call time.
- **`@` overwrite** scratches the old file before the new one is
  written. If the save then fails (disk full after the scratch, write
  error), the old file is lost.

### M11 – Defragment callbacks may clobber X/Y

*By code.* In `rom_defragment_copy_data` the loop reads the source with
`lda abs,y` and Y = 0 (`efs_init_readef_rely`). The warning callback is
called from `rom_defragment_copy_data_destinc` inside that loop. A
callback that changes Y makes all following reads use the wrong address.
Neither the manual nor `efs-config.s` says that the callbacks must
preserve X and Y.

*Fix*: save and restore X/Y around the `jmp (zp_var_x5)` in the callback
helpers.

---

## Minor

- **m1 – long names** (`lib-efs.s:2018-2066`, `rom_dirsearch_checkname`).
  A name longer than 16 characters is compared beyond the name field. If
  the mismatch happens after the 16th character, the `@next` loop
  (`cpx #$10`) never terminates normally and advances the read pointer by
  up to 256 bytes, skipping directory entries. Names > 16 should be
  rejected (or truncated) up front. The same applies to
  `rom_dirload_checkname`. The test with a 17-character name returned
  "not found" without a crash.
- **m2 – directory bounds.** `rom_dirsearch_find` only checks the
  directory boundary for non-deleted entries (`lib-efs.s:2097-2104`). A
  directory filled to the end with deleted entries is scanned into the
  file data. `rom_dirload_checkboundary` (`dirlist.s:430-433`)
  hard-codes `$b8`, which is only correct for directories at `$a000`.
  The r/w directories at `$8000` end at `$9800`.
- **m3 – stale "active file" area.** `rom_filesave_blockedspace`
  (`rw.s:1162`) uses `rom_config_get_area_dirhigh_active_file`, but
  during `rom_filesave_conditions` the file-area bits still describe the
  previously opened file. It should use `rom_config_get_area_dirhigh`.
  This only affects the bounds check.
- **m4 – erase count.** `rom_defragment_erasearea` uses `size >> 3` as
  the loop counter. A configured size below 8 gives 0, and the loop then
  runs 256 times (erasing everything from the area start through the
  wrapped bank numbers, including bank 0). Sizes are not validated.
- **m5 – hard-coded bases.** `rom_defragment_copy_dir` stores
  `offset_high = pointer − $80` (or `− $a0` for hhhh) instead of
  `pointer − files_high`. `rom_filesave_begin` uses the directory bank as
  the files bank for the first file. Both only work because the test
  config has `dir bank = files bank` and `dir high = files high`.
- **m6 – end address.** LOAD returns the address of the last byte
  (X/Y = `$3000` for a 1-byte file at `$3000`). The KERNAL returns the
  address after the last byte. BASIC-style code (e.g. setting `$2d/$2e`)
  must add 1. The manual should state this explicitly.
- **m7 – smaller inconsistencies**
  - Verify mismatch returns C set with A = 0. Only `readst` tells
    `$10`.
  - Status `$80` ("file in r/w area") is overwritten by EOF (`$40`) on
    LOAD.
  - `rom_command_begin` permanently moves `filename_address` /
    `filename_length` past the command prefix, so a second call without
    `setnam` uses the bare name.
  - `S` scratches only the first match of a wildcard name.
  - `EFS_format` does not check or reset `internal_state`.
  - The dirlist type table (`dirlist.s:380-392`) has 12 entries. Type
    values `$10-$1e` index past it.
  - `EFS_chrin` after EOF returns C set with A = 0 and no error code.
  - Open for writing reserves `$2000` + 2 bytes. With less free space
    `open` fails ("disk full") even for small files. Larger files can be
    written as long as the area has room.
  - Loading into `$d000-$dfff` while I/O is visible (or over the EAPI
    copy) destroys the library state. This should be mentioned in the
    manual next to the `setnam` restriction.
  - `SHOW_INDICATE_ACTIVITY = 1` (default) changes `$d020` during every
    load/save/search, and the `indicate_load` macro clobbers X.

## Documentation (D1)

- `docs/manual.md` configuration table: bytes `39-3f` are "unused", but
  the default config in `lib-efs.s:194-196` and `libefs_config` define
  `actcall`/`actvector` there (marked "not implemented").
- `docs/manual.md`, `EFS_validate`: says C is set on corruption, while
  the code is a stub (see M10).
- `docs/memory.txt` still shows the old `LIB`/`EFS` configuration layout
  and old zero page notes.
- `lib-efs.i`: comment "bit 5 and 6" for `LIBEFS_FLAGS_FILE_AREA0` is
  wrong (bits 4 and 5).
- PR #1's explanation in `lib-efs.s:1110-1117` is wrong (see C1) and
  should be removed together with the code.

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

## Suggested order of fixes

1. C1 + C2 (defragment unusable; one revert plus one instruction).
2. C4 + C5 (flash corruption of the library itself).
3. C3 (data corruption with mixed banking modes).
4. C6, C7, C8, M1, M2 (simple branch fixes).
5. M3-M9, then robustness (M10/M11) and the minor items.

Most critical items are one-instruction branch errors (`bne` instead of
`bcc`, `beq` instead of `bne`) or flag-handling errors. A regression test
in an emulator should cover them, see below.

## How the findings were verified

The library was built with the installed cc65 (`make
build/ef/test-libefs.bin`, default `BANKMODE=ll`, plus an `lh` build). The
resulting 1 MB cartridge image was run in a small Python harness:

- the `py65` 6502 core;
- C64 `$01` and PLA mapping for 16k, 8k, ultimax and cartridge-off modes;
- EasyFlash `$de00`/`$de02`/`$df00` RAM;
- two AM29F040 flash chips with the unlock, program, sector-erase and
  autoselect command state machine (programming can only clear bits).

It runs the original EAPI driver and libefs code unchanged and calls the
public entry points like a program would. It stops on illegal opcodes,
on code executed from ROM while `$de00 ≠ 0`, and on endless loops. The
harness was a one-off review aid and is not part of the repository.
Regression tests for libefs are to be done in VICE only.

C1 and C3 were cross-checked in VICE 3.9 (`x64sc`) with the real
`build/test-libefs.crt`. Keystrokes were fed into the KERNAL keyboard
buffer through the remote monitor, and screenshots were taken after the
operation.
