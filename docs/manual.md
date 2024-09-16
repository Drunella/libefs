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

Libefs can be identified by the text LIBEFS (in PETSCII) at
00:l:0010, followed by the version number in major.minor.patch.

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


# Configuration

The configuration describes where the directories and the read/write area
can be found. It also contains the vectors for defragmentation indication.
Defragmentation can take a long time, so it is helpful to show some
progress. In the example the border color flashes.

| 00:1:1bxx | Description |
| --------- | ----------- |
| 00-17     | EasyFlash name (8+16), see EasyFlash documentation |
| 18-1d     | LIBEFS ($4c, $49, $42, $45 $46 $53) |
| 1e-1f     | empty ($00, $00) |
| 20        | empty ($00) |
| 21        | 1:only one area (default); 3:two additional read/write areas |
| 22        | bank of area 0 directory (default 0) |
| 23        | high address of area 0 directory (default $a0) |
| 24        | bank of area 0 files (default 1) |
| 25        | high address of area 0 files (default $80) |
| 26        | number of banks of area 0 (every 8k bank counts), can be zero for area 0 (default $ff) |
| 27        | bank of area 1 directory |
| 28        | high address of area 1 directory |
| 29        | bank of area 1 files |
| 2a        | high address of area 1 files |
| 2b        | number of banks of area 1 used (must be divisible by 8) |
| 2c        | bank of area 2 directory |
| 2d        | high address of area 2 directory |
| 2e        | bank of area 2 files |
| 2f        | high address of area 2 files |
| 30        | number of banks of area 2 used (must be divisible by 8) |
| 31        | call function on defragmentation (1: yes, 0: no) |
| 32,33     | vector to update defragmentation warning; must be callable while EasyFlash is banked in |
| 34,35     | vector to the defragmentation all clear function; must be callable while EasyFlash is banked in |
| 34-3f     | unused |

See src/ef/efs-config.s as example.


# Initialize

To initialize libefs, EAPI or MiniEAPI you need to call the functions
EFS_init and EFS_init_eapi or EFS_init_minieapi while bank 0 must
be banked in as 16k cartridge. You should also call EFS_validate on every
start. Call EFS_defragment if EFS_validate returns an error.

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
  A: error code or 0
  .C: set if error occurs
Defragments the writable part of the efs. This process can take several
minutes depending on the size of writable part and used files. While
defragmenting a progress function can be called to indicate the process.
```

```
EFS_format ($800c):
Parameter: none
Returns:
  A: error code or 0
  .C: set if error occurs
Formats the writeable part of the efs.
```

```
EFS_validate ($800f):
Parameter: none
Returns:
  .C: set if efs is corrupted
Call this to check if there are any corruptions in the writeable part of the
efs. The function returns .C set if any corruptions are found. The function
will delete corrupted files. Call EFS_defragment to repair the remaining
files. It will also check and erase all unused banks prior to usage. Some
hardware and older software implementations will not clear unused areas.
(eg older VICE, Kung Fu Flash)
Not yet implemented.
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

Calling EAPIWriteFlash, EAPIEraseSector and EAPIGetSlot in MiniEAPI will do
nothing, they will immediately return. Calling EAPIWriteFlashInc is identical
to EAPISetBank. Calling EAPISetSlot will change the current bank, but not the
shadow bank.



# libefs

```
EFS_setlfs ($df00)
Parameter:
  Y: secondary address (0: relocate, 1: load to loadaddress of file)
Return:
  none
```

```
EFS_setnam ($df06)
Parameter:
  A: name length
  X: name address low
  Y: name address high
Return:
  none
Restrictions:
  The name must not be in memory areas where banking occurs: $8000 - $bfff
  and $e000 - $ffff, as well as the memory below io area ($d000 - $dfff)
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
Supported commands:
  "$0:[filename]" will load the directory
```

```
EFS_open ($df12)
Parameter:
  A: 0=read 1=write
Return:
  A: error code
  .C: set if error
Supported commands:
  "$0:[filename]" will load the directory
  "S0:[filename]" will delete a file
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
```

```
EFS_save ($df24)
Parameter:
  A: z-page variable to start address
  X: end address low
  Y: end address high
Return:
  A: error code
  .C: set if error
Supported commands:
  "@0:[filename]" will overwrite the file
```

```
EFS_chrout ($df2a)
Parameter:
  A: character to output
Return:
  .C: set if error
Error
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
  $1a: write protected
  $1e: command syntax error
  $ef: file exists
  $47: directory error
  $48: disk dull
```


# Usage

## Interrupts

Libefs does not use sei. You have to take care of your interrupts
beforehand. EAPI uses sei but restores the interrupt flag with plp.
You can block interrupts by calling sei and cli before and after calling
libefs functions.

libefs uses $37 (BASIC and KERNAL banked in) as memory configuration. If
this conflicts with your interrupt usage you need to turn interrupts off
before calling libefs functions.


## Allowed commands

Not all acommands are allowed to be usesd in load, open and save.

```
S: scratch: open
$: directory: open, load
@: overwrite: save
```

