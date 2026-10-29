// ----------------------------------------------------------------------------
// Copyright 2025 Drunella
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// ----------------------------------------------------------------------------

#include <stdbool.h>
#include <conio.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "util.h"


#define MENU_START_Y 2
#define OUTPUT_START_Y 11
#define CONSOLE_START_Y 16
#define ADDRESS 0x4000


static uint16_t global_size = 384;


static void draw_startmenu(void) {
    clrscr();
    textcolor(COLOR_GRAY2);
    //     0123456789012345678901234567890123456789
    cputs("libefs Test Cartridge  (c) 2025 Drunella");
}

void draw_version(void)
{
    char text[8];
    uint8_t n;
    
    n = sprintf(text, "v%d.%d.%d", get_version_major(), get_version_minor(), get_version_patch());
    cputsxy(39-n, 24, text);
}

void draw_system(uint8_t system, uint8_t sid)
{
    cprintf("c64 type: ");
    switch(system) {
        case 0: cprintf("EU-PAL"); break;
        case 1: cprintf("NTSC-old"); break;
        case 2: cprintf("PAL-N"); break;
        case 3: cprintf("NTSC-new"); break;
        default: cprintf("unknown"); break;
    }
    switch(sid) {
        case 1: cprintf(", SID6581"); break;
        case 2: cprintf(", SID8085"); break;
        default: break;
    }
    cprintf("\n\r");
}

void fail_tests_3(void)
{
    uint8_t data;
    
    // close without open
    uint8_t retval, status;
    cprintf("close without open: ");
    retval = EFS_close_wrapper();
    status = EFS_readst_wrapper();
    cprintf("r=%d s=$%02x\n\r",retval, status);

    cprintf("chrin without open: ");
    retval = EFS_chrin_wrapper(&data);
    status = EFS_readst_wrapper();
    cprintf("r=%d s=$%02x\n\r",retval, status);

    
}

// highest address a test load may reach: the EAPI copy starts at $cd00
#define LOAD_LIMIT 0xcd00

// Determines the load address and the size (in 256 byte blocks) of a file:
// the address from its first two bytes (open/chrin), the blocks from a
// pattern directory listing "$:name". Returns false if the file does not
// exist.
bool file_bounds(char* filename, uint16_t* address, uint16_t* blocks)
{
    static char pattern[20];
    uint8_t lo, hi, retval;
    char* listing = (char*)(ADDRESS);
    char* p;

    EFS_setnam_wrapper(filename, strlen(filename));
    EFS_setlfs_wrapper(0);
    if (EFS_open_wrapper(0) != 0) return false;
    retval = EFS_chrin_wrapper(&lo);
    if (retval == 0) retval = EFS_chrin_wrapper(&hi);
    EFS_close_wrapper();
    if (retval != 0) return false;
    *address = lo | (hi << 8);

    strcpy(pattern, "$:");
    strncat(pattern, filename, 16);
    EFS_setnam_wrapper(pattern, strlen(pattern));
    EFS_setlfs_wrapper(0);
    if (EFS_load_wrapper(listing, 0) != 0) return false;
    p = listing;                 // header line: link, line number, text
    p += 2;
    p += 2;
    while (*p != 0) p++;
    p++;
    if (p[0] == 0 && p[1] == 0) return false;   // no file line
    *blocks = (uint8_t)p[2] | ((uint8_t)p[3] << 8);
    return true;
}

// Checks that a load of the file fits between the test data area and the
// EAPI copy; prints the reason if not.
bool load_fits(char* filename, uint8_t secondary)
{
    uint16_t address, blocks;
    uint32_t end;

    if (!file_bounds(filename, &address, &blocks)) {
        cprintf("file not found\n\r");
        return false;
    }
    if (secondary == 0) address = ADDRESS;
    end = (uint32_t)address + (uint32_t)blocks * 256;
    if (address < ADDRESS || end > LOAD_LIMIT) {
        cprintf("skipped: $%04x + %u blocks does not fit in $%04x-$%04x\n\r",
                address, blocks, ADDRESS, LOAD_LIMIT);
        return false;
    }
    return true;
}

void loadverify(char* filename, uint8_t verify, uint8_t secondary)
{
    uint8_t retval, status;
    uint32_t timer, seconds;
    char* startaddress;
    char* endaddress;

    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);
    if (!load_fits(filename, secondary)) return;
    EFS_setnam_wrapper(filename, strlen(filename));
    EFS_setlfs_wrapper(secondary);
    cprintf("start\n\r");
    TIMER_reset();
    retval = EFS_load_wrapper((char*)(ADDRESS), verify);
    timer = UINT32_MAX - TIMER_measure();
    startaddress = EFS_get_startaddress();
    endaddress = EFS_get_endadress();
    if (verify == 0) cprintf("l: "); else cprintf("v: ");
    cprintf("sc=%d, rt=%d, sa=$%04x, ea=$%04x\n\r", secondary, retval, startaddress, endaddress);
    global_size = endaddress - startaddress;
    status = EFS_readst_wrapper();
    seconds = timer / 1000000; timer = timer % 1000000;
    cprintf("st: $%02x, timer = %lu.%06lu sec\n\r", status, seconds, timer);
}

void savefile(char* filename, char* address, uint16_t size)
{
    uint8_t retval, status;
    uint32_t timer, seconds;
    char* endaddress;
//    uint8_t* startaddress = (uint8_t*)(0x0040);

//    startaddress[0] = (uint8_t)((uint16_t)address & 0xff);
//    startaddress[1] = (uint8_t)((uint16_t)address >> 8);
    endaddress = address + size + 1;
        
    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);
    EFS_setnam_wrapper(filename, strlen(filename));
    EFS_setlfs_wrapper(0);  // no secondary
    cprintf("start\n\r");
    TIMER_reset();
    retval = EFS_save_wrapper(address, endaddress);
    timer = UINT32_MAX - TIMER_measure();
    cprintf("rt=%d, sa=$%04x se=$%04x\n\r", retval, address, endaddress);
    status = EFS_readst_wrapper();
    seconds = timer / 1000000; timer = timer % 1000000;
    cprintf("st=$%02x, timer=%lu.%06lu s\n\r", status, seconds, timer);

}


void openfile(char* filename, uint8_t secondary, uint8_t mode)
{
    uint8_t retval, status;

    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);
    EFS_setnam_wrapper(filename, strlen(filename));
    EFS_setlfs_wrapper(secondary);
    retval = EFS_open_wrapper(mode);
    status = EFS_readst_wrapper();
    cprintf("open: sc=%d, rt=%d, st=$%02x\n\r", secondary, retval, status);
  
}

void readfile(void)
{
    uint8_t retval, status;
    uint8_t data;
    uint16_t checksum = 0;
    char* address = (char*)(ADDRESS);
    uint8_t header = 2;
    
    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);

    while (true) {
        retval = EFS_chrin_wrapper(&data);
        if (retval != 0) break;
        if (header > 0) { 
            header--;
            continue;
        }
        if ((uint16_t)address >= LOAD_LIMIT) {
            cprintf("stopped at $%04x\n\r", LOAD_LIMIT);
            break;
        }
        address[0] = data; address++;
        checksum += data;
        if (EFS_readst_wrapper() != 0) break;   // last byte delivered
    }

    status = EFS_readst_wrapper();
    cprintf("chrin: rt=%d, st=$%02x chksum=%u\n\r", retval, status, checksum);
    
}

void writefile(uint16_t size)
{
    uint8_t retval, status;
    uint16_t i = 0;
    char* address = (char*)(ADDRESS);

    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);

    EFS_chrout_wrapper((uint8_t)(address) & 0xff);
    EFS_chrout_wrapper((uint8_t)((uint16_t)address >> 8) & 0xff);

    i = 0;
    while (i < size) {
        retval = EFS_chrout_wrapper(address[i]);
        if (retval != 0) break;
        i++;
    }

    status = EFS_readst_wrapper();
    cprintf("chrout: rt=%d, st=$%02x size=%d\n\r", retval, status, i);

}


void closefile(void)
{
    uint8_t retval, status;

    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);

    retval = EFS_close_wrapper();
    status = EFS_readst_wrapper();
    cprintf("close: rt=%d, st=$%02x\n\r", retval, status);

}


void readdir()
{
    uint8_t retval, status;
    char* startaddress;
    char* endaddress;

    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);

    EFS_setnam_wrapper("$", 1);
    EFS_setlfs_wrapper(0); // do not relocate
    retval = EFS_load_wrapper((char*)(ADDRESS), 0);
    startaddress = EFS_get_startaddress();
    endaddress = EFS_get_endadress();
    status = EFS_readst_wrapper();
    cprintf("st=$%02x, rt=%d, sa=$%4x, ea=$%4x\n\r", status, retval, startaddress, endaddress);

    // ### print directory
}


void scratchfile(char* cmdname)
{
    uint8_t retval, status;
    
    cmdname[0] = 's';
    cmdname[1] = '0';
    cmdname[2] = ':';

    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);

    EFS_setnam_wrapper(cmdname, strlen(cmdname));
    EFS_setlfs_wrapper(0); // do not relocate
    retval = EFS_open_wrapper(0);
    status = EFS_readst_wrapper();
    EFS_close_wrapper();
    cprintf("scratch: st=$%02x, rt=%d\n\r", status, retval);
}

void format()
{
    uint8_t retval;

    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);

    retval = EFS_format_wrapper();
    cprintf("format: rt=%d\n\r", retval);
}

void defragment()
{
    uint8_t retval;
    uint32_t seconds, timer;

    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);

    cprintf("start\n\r");
    TIMER_reset();
    retval = EFS_defragment_wrapper();
    timer = UINT32_MAX - TIMER_measure();
    seconds = timer / 1000000; timer = timer % 1000000;
    cprintf("defragment: rt=%d, timer=%lu.%06lu s\n\r", retval, seconds, timer);

}

void createdata(uint16_t size, char* prefix, char* suffix)
{
    char* address = (char*)(ADDRESS);
    uint16_t i;
    uint16_t* seed = (uint16_t*)(0x00a1);  // some timer

    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);
    
    srand(*seed);
    
    for (i=0; i<size; i++) {
        address[i] = (uint8_t)rand();
    }
    
    sprintf(&address[0], "%s", prefix);
    sprintf(&address[size-strlen(suffix)], "%s", suffix);
}

void createpattern(char* address, uint16_t size, uint32_t number)
{
    uint16_t i;

    for (i=0; i<size; i++) {
        address[i] = (uint8_t)i;
    }

    sprintf(address, "%lu", number);
    address[size - 1] = 0xfe;
}


void longtest()
{
    // create test data (2687 bytes) at $9000 with the run counter as text,
    // save it as "myfile", load it to ADDRESS, verify it, compare it with
    // the pattern and the counter; repeat with a new pattern until a key
    // is pressed (the overwrites trigger defragmentations)
    uint8_t retval, status;
    char* address = (char*)(ADDRESS);
    uint16_t size = 2687; // 2816;
//    uint16_t size = 26;
//    uint16_t i;
    char c;
    uint32_t counter = 0;
    uint32_t errors = 0;
    uint32_t verify;
    char cmdname[] = "@0:myfile";
    char *filename = &cmdname[3];

    createpattern((char*)0x9000, size, counter);
    EFS_setnam_wrapper(cmdname, strlen(cmdname));  // "@0:": a file from an earlier run may exist
    EFS_setlfs_wrapper(0);  // no secondary
    retval = EFS_save_wrapper((char*)(0x9000), (char*)(0x9000) + size + 1);
    if (retval != 0) errors++;

    menu_clear(CONSOLE_START_Y, 24);

    while (true) {
        c = 0;
        if (kbhit()) c = cgetc();
        if (c) break;
        
        menu_clear(CONSOLE_START_Y, CONSOLE_START_Y+1);
        gotoxy(0, CONSOLE_START_Y);
        cprintf("test run: %lu (errors: %lu)\n\r", counter, errors);

        EFS_setnam_wrapper(filename, strlen(filename));
        EFS_setlfs_wrapper(0);
        retval = EFS_load_wrapper(address, 0); // load
        if (retval != 0) {
            cprintf("error: load retval=%d\n\r", retval);
            errors++;
        }
            
        EFS_setnam_wrapper(filename, strlen(filename));
        EFS_setlfs_wrapper(0);
        retval = EFS_load_wrapper(address, 1); // verify
        if (retval != 0)  {
            cprintf("error: verify retval=%d\n\r", retval);
            errors++;
        }

        status = EFS_readst_wrapper();
        if ((status & 0x40) != 0x40)  {
            cprintf("error: load readst status=%d\n\r", status);
            errors++;
        }
            
        verify = atol(address);
        if (verify != counter)  {
            cprintf("error: count verify=%lu\n\r", verify);
            errors++;
        }

        // the loaded file must match the pattern that was saved
        if (memcmp(address, (char*)0x9000, size) != 0) {
            cprintf("error: content mismatch\n\r");
            errors++;
        }


/*        EFS_setnam_wrapper(cmdname, strlen(cmdname));
        EFS_setlfs_wrapper(0); // do not relocate
        retval = EFS_open_wrapper(0);
        if (retval != 1) errors++;
        EFS_close_wrapper();*/
          
        counter++;
        createpattern((char*)0x9000, size, counter);  // new pattern, saved from $9000
        EFS_setnam_wrapper(cmdname, strlen(cmdname));
        EFS_setlfs_wrapper(0);
        retval = EFS_save_wrapper((char*)0x9000, (char*)0x9000 + size + 1);
        if (retval != 0)  {
            cprintf("error: save retval=%d\n\r", retval);
            errors++;
        }

        status = EFS_readst_wrapper();
        if (status != 0x80)  {
            cprintf("error: save readst status=%d\n\r", status);
            errors++;
        }

            
    }

    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);
    cprintf("result: %lu runs, %lu errors\n\r", counter, errors);

}


void main(void)
{
    bool repaint;
    static char filename_data[20];
    uint8_t secondary, mode;
    char* filename;
    char* commandname;
    char* address;
    uint8_t sysident;
    uint8_t sidident;
    uint8_t cleartoggle;
    
    filename = &filename_data[3];
    commandname = &filename_data[0];
    repaint = true;
    bgcolor(COLOR_BLACK);
    bordercolor(COLOR_BLACK);
    draw_startmenu();
    sprintf(filename, "delme384");
    secondary = 0;
    mode = 0;
    memset((char*)ADDRESS, 0, 0x6000);
    cleartoggle = 0;

    sysident = SYS_get_system();
    sidident = SYS_get_sid();
    
    while (kbhit()) {
        cgetc();
    }
    
    for (;;) {
        
        if (repaint) {
            menu_clear(MENU_START_Y, CONSOLE_START_Y);
            menu_option(0, wherey(), 'F', "Set filename");   
            menu_option(0, wherey(), 'C', "Clear memory");
            menu_option(0, wherey(), '1', "Load file");
            menu_option(0, wherey(), '2', "Verify file");
            menu_option(0, wherey(), '7', "Scratch file");
            menu_option(0, wherey(), 'Q', "Quit to basic");
            menu_option(0, wherey(), '9', "Format");
            menu_option(0, wherey(), 'T', "Long Test");
            gotoxy(0, MENU_START_Y);
            menu_option(20, wherey(), 'S', "Toggle sec.");
            menu_option(20, wherey(), '0', "Defragment");
            menu_option(20, wherey(), '3', "Open file");
            menu_option(20, wherey(), '4', "Close file");
            menu_option(20, wherey(), '5', "R/W file");
            menu_option(20, wherey(), '6', "Directory");
            menu_option(20, wherey(), '8', "Save file");
            gotoxy(0, OUTPUT_START_Y);
            //cprintf("%x (4a:60,9 a6:60,1 51:50,9 c0:50,1)\n\r", sysident);
            draw_system(sysident, sidident);
            cprintf("filename: '%s'\n\r", filename);
            cprintf("mode: %d\n\r", mode);
            cprintf("secondary: %d\n\r", secondary);
            draw_version();
            gotoxy(0, CONSOLE_START_Y);
        }
        
        repaint = false;
        
        switch (cgetc()) {
        case 'f':
            menu_clear(OUTPUT_START_Y,24);
            cprintf("new filename: ");
            address = gettextxy(wherex(), wherey(), 16);
            strcpy(filename, address);
            //init_loader();
            //startup_game(); // does not return
            repaint = true;
            break;

/*        case 'd':
            menu_clear(OUTPUT_START_Y,24);
            cprintf("device: ");
            device = atoi(gettextxy(wherex(), wherey(), 3));
            repaint = true;
            break;*/

        case 'c':
            if (cleartoggle == 0) {
                memset((char*)ADDRESS, 0, 0x6000);
                //memset((char*)0xc000, 0, 0x0d00);
                cleartoggle = 1;
            } else {
                memset((char*)ADDRESS, 0, 0x6000);
                createdata(1100, filename, "finish123456789");
                cleartoggle = 0;
            }
            repaint = true;
            break;

        case 's':
            if (secondary == 0) secondary = 1; else secondary = 0;
            repaint = 1;
            break;

        case 'm':
            if (mode == 0) mode = 1; else mode = 0;
            repaint = 1;
            break;

        case 't':
            longtest();
            repaint = 1;
            break;

        case '0':
            //fail_tests_3();
            defragment();
            repaint = true;
            break;

        case '1':
            loadverify(filename, 0, secondary);
            repaint = true;
            break;

        case '2':
            loadverify(filename, 1, secondary);
            repaint = true;
            break;

        case '3':
            openfile(filename, secondary, mode);
            repaint = true;
            break;

        case '4':
            closefile();
            repaint = true;
            break;

        case '5':
            if (mode == 0) {
                readfile();
            } else {
                writefile(512);
            }
            repaint = true;
            break;

        case '6':
            gotoxy(0, CONSOLE_START_Y);
            readdir();
            repaint = true;
            break;

        case '7':
            gotoxy(0, CONSOLE_START_Y);
            scratchfile(commandname);
            repaint = true;
            break;

        case '8':
            gotoxy(0, CONSOLE_START_Y);
            savefile(filename, (char*)(ADDRESS), global_size);
            repaint = true;
            break;

        case '9':
            gotoxy(0, CONSOLE_START_Y);
            format();
            repaint = true;
            break;

        case 'q':
            cart_kill();
            __asm__("lda #$37");
            __asm__("sta $01");
            __asm__("ldx #$ff");
            __asm__("txs");
            __asm__("jmp $fcfb");
            break;
        }
    }
}
