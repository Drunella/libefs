# libefs 

A library to access the EasyFlash Filesystem (efs) in the manner of the c64
kernal routines for reading and writing files.

## Features
* Reading and Writing to EasyFlash
* kernal style functions for access
* minieapi: readonly eapi without additional ram usage

## Building
To build your own version you need the following:
* cc65
* Python 3.6 or greater
* GNU Make
* C compiler

Then build with

```
make
```

Find the prg of libefs in the build sub-directory:
`build/lib-efs.prg`.



# Manual

Read more in [docs/manual.txt](./docs/manual.txt)

The library uses the low rom space of the EasyFlash cartridge on bank
(0:l:0000 - 0:l:1fff) and the 128 bytes in the io2 area (df00 - df7f). 
No further ram is needed. All banking code and variables reside in the 
io2 space. Do not put any other code in the low rom bank 0.

If you only need read access to the efs you can use minieapi which contains
a subset of functions of eapi for reading. Of course there is no erase and
write. The minieapi sits in the upper io2 area (df80 - dfff) and replaces
the eapi jump table, code and variables there. No further ram space is
needed.

The efs library can be identified by the text LIBEFS (in PETSCII) at
00:l:0010, followed by the version number in major.minor.patch.

The configuration, which banks to use for the read/write part, resides
right after the EasyFlash name at 0:1:1b18.

The library has a read only storage (the EasyFlash fs as described in the
orgiginal documentation) and a writable area. For the writable part the 
libray alternates between two areas of equal size. If one area is used
up (by deleting and re-creating files) all active files will be copied
to the other area and the original area will be erased. This defragmentation
process can take up to several minutes, depending on the used space.


## Configuration

The configuration describes where the directories and the read/write area
can be found. It also contains the vectors for defragmentation indicators.
The defragmentation can take a long time and it is helpful to show some
progress. In the example the border color flashes.

| 00:1:1bxx | Description |
| --------- | ----------- |
| 00-17     | EF-Name: name (8+16), see EasyFlash documentation |
| 18-1d     | LIBEFS ($4c, $49, $42) |
| 1e-1f     | empty ($00, $00, $00) |
| 21        | 1:only one area (default); 3:two additional read/write areas |
| 22        | bank of area 0 directory (default 0) |
| 23        | high address of area 0 directory (default $a0) |
| 24        | bank of area 0 files (default 1) |
| 25        | high address of area 0 files (default $80) |
| 26        | number of banks of area 0 (every 8k bank counts), can be anything (default $ff) |
| 27        | bank of area 1 directory |
| 28        | high address of area 1 directory, usually $00 |
| 29        | bank of area 1 files (must be identical to directory) |
| 2a        | high address of area 1 files, usually $18 |
| 2b        | number of banks of area 1 used (must be divisible by 8) |
| 2c        | bank of area 2 directory |
| 2d        | high address of area 2 directory, usually $00 |
| 2e        | bank of area 2 files (must be identical to directory) |
| 2f        | high address of area 2 files, usually $18 |
| 30        | number of banks of area 2 used (must be divisible by 8) |
| 31        | call function on defragmentation (1: yes, 0: no) |
| 32,33     | vector to update defragmentation warning; must be callable while easyflash is banked in. |
| 34,35     | vector to the defragmentation all clear function; must be callable while easyflash is banked in. |
| 34-3f     | unused |

See src/ef/efs-config.s as example.



## Initialize

To initialize libefs, eapi or minieapi you need to call the functions
EFS_init and EDS_init_eapi resp. EFS_init_minieapi while bank 0 must
be banked in as 16k cartridge. You should also call EFS_validate on every
start. Call EFS_defragment if EFS_validate returns an error.


```
EFS_init ($8000):
Parameter:
  none
Returns:
  none
Initializes the efs library, copies code and variables to the io2 area
($df00-$df7f). EFS_init can be called before or after EFS_init_eapi or
EFS_initminieapi. Bank 0 must be banked in as 16k cartridge.
```

```
EFS_init_eapi ($8003):
Parameter:
  A: the high byte of the address where eapi will reside in c64 memory
Return:
  .C: set if eapi is not on the cartridge
Copies the epi code (768 bytes) to the memory location given as high byte
in the eaccumulator. A low address is not necessary as the eapi must be page
aligned. C flag will be set if eapi is not on the cartridge. You can
overwrite a previous initialized minieapi. Bank 0 must be banked in as 16k 
cartridge.
```

```
EFS_init_minieapi ($8006):
Parameter: 
  none
Returns: 
  none
Initalizes minieapi in the io2 area ($df80-$dfff). You can overwrite a 
previously initialized eapi. With minieapi calls to EAPIWriteFlash, 
EAPIEraseSector and EAPIGetSlot will do nothing. Bank 0 must be banked in 
as 16k cartridge.
```

```
EFS_defragment ($8009):
Parameter: 
  none
Returns:
  A: error code or 0
  .C: set if error occurs
Defragments the writeable part of the efs. This process can take several
minutes depending on size of writable part and used files. While defragmenting
a progress function can be called to indicate the process.
```

```
EFS_format ($800c):
Parameter: 
  none
Returns:
  A: error code or 0
  .C: set if error occurs
Formats the writeable part of the efs.
```

```
EFS_validate ($800f):
Parameter: 
  none
Returns:
  .C: set if efs is corrupted
Call this to check of there are any corruptions in the writeable part of the
efs. The function returns .C set if any corruptions are found. The function
will delete corrupted files. Call EFS_defragment to repair the remaining files.
It will also check and erase all unused and unerased banks prior to usage. Some
hardware and older software implementations might not erase unused banks.
NOT YET IMPLEMENTED!
```

You can use the following code to bank in before calling an init function:
```
   lda #$37
   sta $01
   lda #$87     ; led, 16k mode
   sta $de02
   lda #$00     ; rom bank of efslib
   sta $de00
```


## MiniEapi

Minieapi provides the EAPI functions EAPIGetBank, EAPISetBank, EAPISetPtr, 
EAPISetLen and EAPIReadFlashInc. See the EasyFlash [Documentation for Developers](https://skoe.de/easyflash/develdocs/)
for more information.

Calling EAPIWriteFlash, EAPIEraseSector and EAPIGetSlot in minieapi will 
do nothing, they will immediately return. EAPIWriteFlashInc and EAPISetSlot 
jumps into the code of EAPISetBank and changes the current bank.


## libefs

```
EFS_setlfs ($df00):
Parameter:
  Y: secondary address (0: relocate, 1: load to loadaddress of file)
Return: 
  none
```

```
EFS_setnam ($df06):
Parameter:
  A: name length
  X: name address low
  Y: name address high
Peturn:
  none
The name must not be in memory areas where banking occurs: $8000 - $bfff, 
$e000 - $ffff as well as the memory below io area ($d000 - $dfff).
```

```
EFS_load ($df0c):
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
EFS_open ($df12):
Parameter:
  A: 0=read 1=write
Return:
  A: error code
  .C: set if error
Supported commands:
  "$0:[filename]" will load the directory
  "S0:[filename]" will delete a file
The parameter in the accumulator is not part of the original c64 kernal call.
```

```
EFS_close ($df18):
Parameter: 
  none
Return:
  A: error code
  .C: set if error
```

```
EFS_chrin ($df1e):
Parameter: 
  none
Return:
  A: character or error code
  .C: set if error
```

```
EFS_save ($df24):
Parameter:
  A: z-page variable to start address
  X: end address low
  Y: end address high
Peturn:
  A: error code
  .C: set if error
Supported commands:
  "@0:[filename]" will overwrite the file
```

```
EFS_chrout ($df2a):
Parameter:
  A: character to output
Return:
  .C: set if error
```

```
EFS_readst ($df30):
Parameter:
  none
Return:
  A: status code
Status codes:
  $10: verify mismatch
  $40: EOF
```


## Error Codes:
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
  $48: disk full
```


## Usage

### Interrupts:

libefs does not use ```sei``` for the most part. You have to take care of 
your interrupts beforehand. EAPI uses sei but restores the interrupt flag 
with ```plp```. You can block interrupts by calling ```sei``` and ```cli``` 
before resp. after calling efs functions.

libefs uses $37 (BASIC and KERNAL banked in) as memory configuration. If 
this collides with your interrupt usage you need to turn off interrupts 
before calling libefs functions.


### Allowed commands

The following commands willcan be used in the following functions:

```
S: scratch: EFS_open
$: directory: EFS_open, EFS_load
@: overwrite: EFS_save
```



# Other

## Example
See the testefs cartridge source code in ```src/ef``` as example. You can find 
the build test cartridge in the build directory: ```build/test-libefs.crt```

## Bugs

I did not test the library thoroughly. There are some tests to
validate the basic functions and a long running test thats reads, scratches
and saves files repeatadly. But there are many cases that the simple tests
do not cover. I consider the library "alpha" quality. The features 
are there but largely untested. Use at your own risk. Some features have not
been implemented yet.


## License and Copyright

The code is © 2023 Drunella, available under the Apache 2.0 license.
