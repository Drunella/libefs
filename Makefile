# ----------------------------------------------------------------------------
# Copyright 2023 Drunella
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------------------------------------------------------

# Settings
TARGET=c64
LD65=cl65
CA65=ca65
CC65=cc65
DA65=da65
#LD65=ld65
LD65FLAGS=-t $(TARGET)
CA65FLAGS=-t $(TARGET) -I . -I build/obj --debug-info
CC65FLAGS=-t $(TARGET) -O
#LD65FLAGS=

.SUFFIXES: .prg .s .c
.PHONY: clean all testef testprg libefs mrproper

EF_LOADER_FILES=build/ef/loader.o
EF_MENU_FILES=build/ef/menu.o build/ef/util.o build/ef/efs-wrapper.o build/ef/version.o
#EF_DIREFS_FILES=build/prg/direfs.o build/lib/lib-efs.o build/lib/lib-efs-ram.o build/lib/lib-efs-minieapi.o build/lib/lib-efs-dirlist.o build/lib/lib-efs-space.o
EF_DIREFS_FILES=build/prg/direfs.o

# all
all: testef testprg libefs

libefs: build/lib-efs.prg

# easyflash
testef: build/test-libefs.crt

# test porogram
testprg: build/test-efs.d64


# assemble
build/%.o: src/%.s
	@mkdir -p ./build/lib ./build/ef ./build/prg
	$(CA65) $(CA65FLAGS) -g -o $@ $<

# compile
build/%.s: src/%.c
	@mkdir -p ./build/lib ./build/ef
	$(CC65) $(CC65FLAGS) -g -o $@ $<

# assemble2
build/%.o: build/%.s
	@mkdir -p ./build/lib ./build/ef
	$(CA65) $(CA65FLAGS) -g -o $@ $<

clean:
	rm -rf build/lib
	rm -rf build/ef
	rm -rf build/files
	rm -f build/lib-efs.prg
	rm -f build/test-libefs.crt
	rm -f build/test-efs.d64

mrproper:
	rm -rf build


# ------------------------------------------------------------------------
# lib-efs.prg
LIB_EFS_FILES=build/lib/lib-efs.o build/lib/lib-efs-ram.o build/lib/lib-efs-minieapi.o build/lib/lib-efs-dirlist.o build/lib/lib-efs-rw.o build/lib/lib-efs-space.o

# lib-efs.prg
build/lib-efs.prg: src/lib/lib-efs.cfg $(LIB_EFS_FILES)
	$(LD65) $(LD65FLAGS) -vm -m ./build/lib/lib-efs.map -Ln ./build/lib/lib-efs.lst -o $@ -C src/lib/lib-efs.cfg c64.lib $(LIB_EFS_FILES)


# ------------------------------------------------------------------------
# test-efs.d64

build/test-efs.d64: build/prg/direfs.prg
	SDL_VIDEODRIVER=dummy c1541 -format efs-tools,0 d64 ./build/test-efs.d64
	SDL_VIDEODRIVER=dummy c1541 -attach ./build/test-efs.d64 -write ./build/prg/direfs.prg direfs

build/prg/direfs.prg: $(EF_DIREFS_FILES)
	$(LD65) $(LD65FLAGS) -vm -m ./build/prg/direfs.map -Ln ./build/prg/direfs.lst -o $@ -C src/prg/direfs.cfg c64.lib $(EF_DIREFS_FILES)


# ------------------------------------------------------------------------
# easyflash

# cartdridge crt
build/test-libefs.crt: build/ef/test-libefs.bin
	cartconv -b -t easy -o build/test-libefs.crt -i build/ef/test-libefs.bin -n "libefs test" -p

# cartridge binary
build/ef/test-libefs.bin: build/ef/init.bin src/ef/eapi-am29f040.prg build/lib-efs.prg build/ef/loader.prg build/ef/efs.dir.prg build/ef/efs.files.prg build/ef/efs-config.bin build/ef/efs-rw.dir.prg build/ef/efs-rw.files.prg
	cp ./src/ef/eapi-am29f040.prg ./build/ef/eapi-am29f040.prg
	cp ./build/lib-efs.prg ./build/ef/lib-efs.prg
	tools/mkbin.py -v -b ./build/ef -m ./src/ef/crt.map -o ./build/ef/test-libefs.bin

# easyflash init.bin
build/ef/init.bin: build/ef/init.o
	$(LD65) $(LD65FLAGS) -o $@ -C src/ef/init.cfg $^

# easyflash loader.bin
build/ef/loader.prg: $(EF_LOADER_FILES)
	$(LD65) $(LD65FLAGS) -vm -m ./build/ef/loader.map -Ln ./build/ef/loader.lst -o $@ -C src/ef/loader.cfg c64.lib $(EF_LOADER_FILES)

# easyflash menu.prg
build/ef/menu.prg: $(EF_MENU_FILES)
	$(LD65) $(LD65FLAGS) -vm -m ./build/ef/menu.map -Ln ./build/ef/menu.lst -o $@ -C src/ef/menu.cfg c64.lib $(EF_MENU_FILES)
	echo "./build/ef/menu.prg, 1, 1" >> ./build/ef/files.list

# easyflash config.bin
build/ef/efs-config.bin: build/ef/efs-config.o src/ef/efs-config.cfg
	$(LD65) $(LD65FLAGS) -vm -m ./build/ef/efs-config.map -Ln ./build/ef/efs-config.lst -o $@ -C src/ef/efs-config.cfg c64.lib build/ef/efs-config.o


# build efs
build/ef/efs.dir.prg build/ef/efs.files.prg: build/ef/files.list build/ef/menu.prg
	tools/mkefs.py -v -u -s 507904 -l ./build/ef/files.list -f . -d ./build/ef

# test files
build/ef/files.list:
	@mkdir -p ./build/files
	rm -f ./build/ef/files.list
	./tools/mkdata.py -f build/files/data1.prg -a 0x3000 -s 1 >> build/ef/files.list
	./tools/mkdata.py -f build/files/data256.prg -a 0x3000 -s 256 >> build/ef/files.list
	./tools/mkdata.py -f build/files/data1023.prg -a 0x3000 -s 1023 >> build/ef/files.list
	./tools/mkdata.py -f build/files/data1024.prg -a 0x3000 -s 1024 >> build/ef/files.list
	./tools/mkdata.py -f build/files/data1025.prg -a 0x3000 -s 1025 >> build/ef/files.list
	./tools/mkdata.py -f build/files/data24k.prg -a 0x3000 -s 24575 >> build/ef/files.list
	./tools/mkdata.py -f build/files/data3k.prg -a 0xc000 -s 3328 >> build/ef/files.list
	./tools/mkdata.py -f build/files/data567890123456.prg -a 0x3000 -s 257 >> build/ef/files.list
	./tools/mkdata.py -f build/files/data56789012345.prg -a 0x3000 -s 1025 >> build/ef/files.list
	./tools/mkdata.py -f build/files/data8k.prg -a 0xa000 -s 8192 >> build/ef/files.list
	./tools/mkdata.py -f build/files/data7k.prg -a 0xe000 -s 7936 >> build/ef/files.list
	./tools/mkdata.py -f build/files/data9k.prg -a 0x3000 -s 2302 >> build/ef/files.list
	./tools/mkdata.py -f build/files/data10k.prg -a 0x3000 -s 2303 >> build/ef/files.list
	./tools/mkdata.py -f build/files/data99k.prg -a 0x3000 -s 25342 >> build/ef/files.list
	./tools/mkdata.py -f build/files/data100k.prg -a 0x3000 -s 25343 >> build/ef/files.list
	./tools/mkdata.py -f build/files/data1000k.prg -a 0x3000 -s 255998 >> build/ef/files.list


# build efs rw
build/ef/efs-rw.dir.prg build/ef/efs-rw.files.prg: build/ef/files-rw.list
	tools/mkefs.py -v -u -s 256000 -o 6144 -m lh -b 32 -n efs-rw -l ./build/ef/files-rw.list -f . -d ./build/ef

# test files rw
build/ef/files-rw.list:
	@mkdir -p ./build/files
	rm -f ./build/ef/files-rw.list
	./tools/mkdata.py -f build/files/delme15.prg -a 0x3000 -s 15 >> build/ef/files-rw.list
	./tools/mkdata.py -f build/files/delme384.prg -a 0x3000 -s 384 >> build/ef/files-rw.list
	./tools/mkdata.py -f build/files/delme640.prg -a 0x3000 -s 640 >> build/ef/files-rw.list
	./tools/mkdata.py -f build/files/delme641.prg -a 0x3000 -s 641 >> build/ef/files-rw.list
	./tools/mkdata.py -f build/files/delme642.prg -a 0x3000 -s 642 >> build/ef/files-rw.list
	./tools/mkdata.py -f build/files/delme50k.prg -a 0x3000 -s 50000 >> build/ef/files-rw.list
	
