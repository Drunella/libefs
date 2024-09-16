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

Read more in [docs/manual.md](./docs/manual.md)



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
