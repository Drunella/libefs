# Introduction

A library to access the EasyFlash Filesystem (efs) in the manner of the c64
kernal routines.

The library uses the low rom space of the EasyFlash cartridge on bank
(0:l:0000 - 0:l:1fff) and the 128 bytes in the IO2 area (df00 - df7f).
No further ram is needed. All banking code and variables reside in the
IO2 space. Do not put any other code in the low rom bank 0.

If you only need read access to the efs, you can use MiniEAPI which contains
a subset of functions of eapi for reading. Of course there is no erase and
write. The MiniEAPI sits in the upper IO2 area (df80 - dfff) and replaces
the eapi jump table, code and variables there. No further ram space is
needed.

Libefs can be identified by the text "libefs" at 00:l:0018 (right after
the jump table), followed by the version number in major.minor.patch.

The configuration, which banks to use for the read/write part, resides
right after the EasyFlash name at 0:1:1b18.

The library has a read only storage (the EasyFlash fs as described in the
original documentation) and a writable area. For the writable part the
library alternates between two areas of equal size. If one area is used
up (by deleting and re-creating files) all active files will be copied
to the other area and the original area will be erased. The process for
copying is called defragmentation. Defragmentation can take up to several
minutes, depending on the used space.

The library is not suitable for storing large amount of data. Its
recommended usage is to store small files, eg savegames.

A reset or power loss during a defragmentation or while a file is being
written leaves the writable part in an inconsistent state; EFS_validate,
called at every start, repairs it (see "Initialize"). How the library
works internally is described in docs/architecture.md.


# Configuration

The configuration describes where the directories and the read/write area
can be found. Limits: the directory and the files of a read/write area
must start in the same bank and at the same address (the files follow the
directory, offset $1800); the size of a read/write area must be a multiple
of 8 (llll, hhhh) or 16 (lhlh) 8k banks; both read/write areas must have
the same size. The configuration is not validated. It also contains the vectors for defragmentation indication.
Defragmentation can take a long time, so it is helpful to show some
progress. In the example the border color flashes.

| 00:1:1bxx | Description |
| --------- | ----------- |
| 00-17     | EasyFlash name (8+16), see EasyFlash documentation |
| 18-1d     | LIBEFS ($4c, $49, $42, $45 $46 $53) |
| 1e-20     | empty ($00, $00, $00) |
| 21        | 1:only one area (default); 3:two additional read/write areas |
| 22        | bank of area 0 directory (default 0) |
| 23        | high address of area 0 directory (default $a0) |
| 24        | bank of area 0 files (default 1) |
| 25        | high address of area 0 files (default $80) |
| 26        | number of banks of area 0 (every 8k bank counts), can be zero for area 0 (default $ff) |
| 27        | banking mode of area 0 ($d0: lhlh, $b0: llll, $d4: hhhh) |
| 28        | bank of area 1 directory |
| 29        | high address of area 1 directory |
| 2a        | bank of area 1 files |
| 2b        | high address of area 1 files |
| 2c        | number of banks of area 1 used (must be divisible by 8) |
| 2d        | banking mode of area 1 ($d0: lhlh, $b0: llll, $d4: hhhh) |
| 2e        | bank of area 2 directory |
| 2f        | high address of area 2 directory |
| 30        | bank of area 2 files |
| 31        | high address of area 2 files |
| 32        | number of banks of area 2 used (must be divisible by 8) |
| 33        | banking mode of area 2 ($d0: lhlh, $b0: llll, $d4: hhhh) |
| 34        | call function on defragmentation (1: yes, 0: no) |
| 35,36     | vector to update defragmentation warning; see below |
| 37,38     | vector to the defragmentation all clear function; see below |
| 39        | activity indicator (not implemented, keep 0) |
| 3a,3b     | activity indicator vector (not implemented) |
| 3c-3f     | unused |

See src/ef/efs-config.s as example.

The defragmentation callbacks are called while the EasyFlash is banked in
(bank 0, 16k mode, $01 = $37) and must
* preserve X and Y (A may be changed),
* not use the zero page $35-$3f,
* not call any libefs function (not even EFS_readst: its code is used as
  temporary storage during defragmentation),
* return with rts.


# Initialize

To initialize libefs, EAPI or MiniEAPI you need to call the functions
EFS_init and EFS_init_eapi or EFS_init_minieapi while bank 0 must
be banked in as 16k cartridge. You should also call EFS_validate on every
start. Call EFS_defragment if EFS_validate returns .C set.

```
EFS_init ($8000):
Parameter: none
Returns: none
Initializes libefs by copying code and variables to the IO2 area ($df00 -
$df7f). EFS_init can be called before or after EFS_init_eapi
or EFS_initminieapi. Bank 0 must be banked in as 16k cartridge.
```

```
EFS_init_eapi ($8003):
Parameter:
  A: the high byte of the address where eapi will reside in c64 memory
Return:
  .C: set if eapi is not on the cartridge
Copies the eapi code (768 bytes) to the memory location given as high byte
in the eaccumulator. A low address is not necessary as the eapi must be page
aligned. C flag will be set if eapi is not on the cartridge. You can
overwrite a previously initialized MiniEAPI. Bank 0 must be banked in as 16k
cartridge.
```
```
EFS_init_minieapi ($8006):
Parameter: none
Returns: none
Initializes MiniEAPI in the IO2 area ($df80 - $dfff). You can overwrite a
previously initialized eapi. With MiniEAPI calls to EAPIWriteFlash,
EAPIEraseSector and EAPIGetSlot will do nothing. Bank 0 must be banked in
as 16k cartridge.
```

```
EFS_defragment ($8009):
Parameter: none
Returns:
  A: error code or 0 (1: invalid entries were dropped)
  .C: set if error occurs ($02: a channel is open, $1a: MiniEAPI,
      $47: the copy failed, $19: the erase failed)
Defragments the writable part of the efs. This process can take several
minutes depending on the size of writable part and used files. While
defragmenting a progress function can be called to indicate the process.
Directory entries with an impossible size (e.g. of a file that was never
closed because of a reset) are dropped; A = 1 with .C clear reports that
this happened. If the copy fails (write error, destination full), the
destination area is erased again, the source area stays valid and
A = $47 (directory error) is returned with .C set.
```

```
EFS_format ($800c):
Parameter: none
Returns:
  A: error code or 0
  .C: set if error occurs ($02: a channel is open, $1a: MiniEAPI,
      $19: the erase failed)
Formats (erases) both writeable areas of the efs.
```

```
EFS_validate ($800f):
Parameter: none
Returns:
  A: error code or 0
  .C: set if efs is corrupted
Call this on every start to check the writeable part of the efs:
* If both read/write areas are in use (a defragmentation was interrupted
  by a reset or power loss), the stale area is erased: libefs marks the
  source and the destination of a defragmentation in the last directory
  slot, so it can tell them apart. Without these markers (image written
  by another tool) A = $47 is returned with .C set; call EFS_defragment
  in that case.
* Entries with an impossible size (a file that was being written when
  the power was lost) or partially written flags are scratched.
A = 1 with .C clear reports that something was repaired, A = 0 that
nothing was found. With MiniEAPI nothing can be repaired; A = 0 is
returned. Unused banks are not checked or erased.
```

You can use the following code to bank in before calling an init function:
```
   lda #$37
   sta $01
   lda #$87     ; LED, 16k mode
   sta $de02
   lda #$00     ; rom bank of libefs
   sta $de00
```


# MiniEAPI

MiniEAPI provides the EAPI functions EAPIGetBank, EAPISetBank, EAPISetPtr,
EAPISetLen and EAPIReadFlashInc.
See the EasyFlash Programmer Reference for more information.

Do not use EAPIWriteFlash, EAPIWriteFlashInc, EAPIEraseSector, EAPISetSlot 
and EAPIGetSlot. They will damage the data integrity of MiniEAPI.



# libefs

To call libefs functions at least the IO area must be accessible. All memory 
configurations will be restored upon exit. Exrom and Game will be inactive
upon exit (meaning both high)

```
EFS_util ($df00)
Parameter:
  A: command
  X,Y: optional parameter
  .C set if error
Return:
  A: error code
  X,Y: optional return values

command: setlfs ($0x):
Parameter:
  A: $0x
  Y: secondary address (0: relocate, 1: load to loadaddress of file)
Return:
  none ($02 with .C set while a channel is open)
Without a setlfs call files are loaded to their own load address.

command: get load address ($10):
Parameter:
  A: $10
Return:
  X: load address low
  Y: load address high
```

```
EFS_setnam ($df06)
Parameter:
  A: name length
  X: name address low
  Y: name address high
Return:
  none ($02 with .C set while a channel is open)
Restrictions:
  The name must not be in memory areas where banking occurs: $8000 - $bfff
  and $e000 - $ffff, as well as the memory below io area ($d000 - $dfff).
  Names longer than 16 characters are truncated to 16. "*" and "?" in a
  name are wildcards for load, open and the directory listing.
```

```
EFS_load ($df0c)
Parameter:
  A: 0=load, 1-255=verify
  X: load address for relocation low
  Y: load address for relocation high
Return:
  A: error code or 0 (1 for file scratched)
  X: end address low
  Y: end address high
  .C: set if error
X/Y hold the address of the last byte written (the kernal returns the
address after the last byte; add 1 for kernal-style code). A verify
mismatch returns .C set with A = 0; EFS_readst then shows $10.
Supported commands:
  "$0:[pattern]" will load the directory (as a BASIC program listing)
  "@0:" is accepted and ignored
```

```
EFS_open ($df12)
Parameter:
  A: 0=read 1=write
Return:
  A: error code
  .C: set if error
Supported commands:
  "$0:[pattern]" will open the directory listing for chrin
  "S0:[filename]" will delete a file (the first match of a pattern; after
  the open only EFS_close is valid; $1a for a file in the read only area)
  "@0:[filename]" with A = 1 deletes an existing file before writing
  "@0:" with A = 0 is accepted and ignored
Opening a file for writing needs room for at least $2002 bytes in the
read/write area ("disk full" otherwise); the file may become larger as
long as the area has room.
```

```
EFS_close ($df18)
Parameter:
  none
Return:
  A: error code
  .C: set if error
```

```
EFS_chrin ($df1e)
Parameter:
  none
Return:
  A: character or error code
  .C: set if error
The last byte of a file (or of a directory listing) is delivered with
the status $40 (EOF) set, as the kernal does. Reading beyond it returns
A = 0 with .C set and no error code.
```

```
EFS_save ($df24)
Parameter:
  A: z-page variable to start address
  X: end address (plus 1) low
  Y: end address (plus 1) high
Return:
  A: error code
  .C: set if error ($1e if the end address is not above the start
      address, $3f if the file exists, $48 if it does not fit, $47 if
      the directory is full)
The data are read with the memory configuration of the caller (see
"Memory access"). If writing fails, the directory entry is removed again.
Supported commands:
  "@0:[filename]" will overwrite the file (the old file is deleted only
  after the space check, see "Memory access")
```

```
EFS_chrout ($df2a)
Parameter:
  A: character to output
Return:
  A: error code
  .C: set if error
X and Y are preserved. When the area is full the last byte is written
and $48 is returned with .C set and the status $40; further calls return
$19 without writing. EFS_close writes the size of the file; if that
fails, the entry is removed again and close returns $19.
```

```
EFS_readst ($df30)
Parameter:
  none
Return:
  A: status code
Status codes:
  $10: verify mismatch
  $40: EOF
  $80: file in rw area (set after EFS_open)
```


Error Codes:
```
  $01: file scratched (no error)
  $02: file open
  $03: file not open
  $04: file not found
  $05: device not present
  $06: no input file
  $07: no output file
  $08: missing filename
  $19: write error
  $1a: write protected (file in the read only area, or MiniEAPI)
  $1e: command syntax error (also: invalid address range for save)
  $3f: file exists
  $47: directory error (directory full after a defragmentation, copy
       failed, or EFS_validate cannot tell the areas apart)
  $48: disk full
```


# Usage

## Memory access

EFS_save and verify read the C64 memory with the memory configuration
($01) of the caller: data under the BASIC or KERNAL ROM can only be
saved or verified with $01 = $35 or $36; the I/O area must stay visible.
EFS_load writes with $01 = $37: loading into $d000-$dfff writes to the
I/O registers (and destroys libefs' own variables at $df00), loading
under the ROMs works.

The file name (EFS_setnam) is kept across EFS_load and EFS_save. After a
file was written with EFS_open/EFS_chrout/EFS_close the name must be
set again. EFS_setnam and EFS_util return "file open" ($02) while a
channel is open; close it first. EFS_load and EFS_save rejected with
"file open" return X and Y unchanged.

"@0:name" on EFS_save checks the free space before the old file is
scratched, so an overwrite that would not fit fails with "disk full"
and keeps the old file.

The build option SHOW_INDICATE_ACTIVITY in src/lib/config.i (default 1)
changes the border colour on every byte loaded, saved or searched. Set
it to 0 for a release build.

## Interrupts

Libefs does not disable interrupts (except for a few cycles while reading
the configuration). You have to take care of your interrupts
beforehand. RUN/STOP+RESTORE during a libefs call (minutes during a
defragmentation) makes the KERNAL NMI handler jump through ($a002),
which is the cartridge ROM at that moment: disable the NMI or make sure
it cannot be triggered. EAPI uses sei but restores the interrupt flag with plp.
You can block interrupts by calling sei and cli before and after calling
libefs functions.

libefs uses $37 (BASIC and KERNAL banked in) as memory configuration
(processor port 0x01). It will restore the processor port before returning. 
If this conflicts with your interrupt usage you need to turn interrupts 
off before calling libefs functions.


## Allowed commands

Not all commands are allowed to be used in load, open and save. The
drive number is optional ("S:name" and "S0:name" are the same).

```
S: scratch: open
$: directory: open (read), load
@: overwrite: save, open (write); ignored by load and open (read)
```

