# libefs

A library to access the EasyFlash Filesystem (efs) in the manner of the C64
KERNAL routines, for reading and writing files on an EasyFlash cartridge.

## Features
* Reading from the read-only efs and reading, writing and deleting files in
  a writable part of the cartridge (two alternating flash areas, compacted
  by a "defragmentation")
* KERNAL style functions: setnam, load, verify, open, chrin, chrout, close,
  readst, directory listings with patterns, scratch and overwrite commands
* No RAM needed except 128 bytes in the IO2 area ($df00-$df7f) and the
  zero page $35-$3f, which is saved and restored
* EFS_validate repairs the writable part after a reset or power loss during
  a defragmentation or while a file was being written
* MiniEAPI: a read-only replacement for EAPI in the upper IO2 area, so that
  reading needs no RAM at all

## Status
The code was reviewed in October 2026 and every critical, major and minor
finding was fixed; see [docs/review-findings.md](./docs/review-findings.md)
for the list, including the remaining design decisions. The fixes are
covered by 36 regression tests that run the real cartridge in VICE
(`make test`). The library is still meant for small files such as save
games; see the limits in the manual.

## Building
You need:
* cc65 (ca65, ld65, cc65)
* Python 3.6 or later
* GNU Make
* VICE (cartconv and c1541 for the test cartridge and the test disk, x64sc
  for the tests)

Build the library and the test cartridge with

```
make
```

The library is `build/lib-efs.prg` (load address $8000, placed in bank 0
ROML), the test cartridge `build/test-libefs.crt`. The banking mode of the
writable areas of the test cartridge is selected with `BANKMODE` in the
Makefile (`ll`, `lh` or `hh`).

### Tests
```
make test
```
runs the regression tests in VICE (`tests/vice/run.py`). They need x64sc,
cartconv, the C64 ROMs (VICE's own search path or the directory in
`$VICE_ROMS`) and, without a display, `xvfb-run` (an SDL build of VICE
runs without it). Each test is a small program that is loaded into the
running test cartridge through VICE's remote monitor; some tests run on
patched cartridge images and some check that the flash written back by
VICE changed only where it should.

The runner starts half as many emulators as there are CPUs (at most 4)
and scales the timeouts with the measured boot time, so slow machines
such as a Raspberry Pi need no special settings; `make test
TESTFLAGS="-j 1"` runs one emulator at a time, `-s 3` triples the
timeouts. If VICE fails to start, the failure line shows its exit code and
the end of its output (missing ROMs, no display, ...); `-v` keeps the log
and the other temporary files of each test in `tests/vice/`.

## Documentation
* [docs/manual.md](./docs/manual.md): configuration, API and usage rules
* [docs/architecture.md](./docs/architecture.md): how the library works
  internally (memory layout, banking, directory format, each operation)
* [docs/review-findings.md](./docs/review-findings.md): the code review,
  what was fixed and how it was verified
* [docs/memory.txt](./docs/memory.txt): zero page, IO2 and directory layout
* [docs/todo.txt](./docs/todo.txt): open items

## Example
The test cartridge in `src/ef` shows how to initialise and call the
library: `init.s` boots the cartridge and loads the menu, `efs-wrapper.s`
wraps the calls for cc65, `efs-config.s` is the configuration block and
`menu.c` exercises every function (load, verify, open/chrin/chrout/close,
directory, scratch, save, format, defragment and a long-running
save/load/verify loop). The tools in `tools/` build the efs images and the
cartridge binary; see the Makefile for how they are used.

## License and Copyright

The code is © 2025 Drunella, available under the Apache 2.0 license.
