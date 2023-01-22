// ----------------------------------------------------------------------------
// Copyright 2023 Drunella
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
#define CONSOLE_START_Y 15
#define ADDRESS 0x3000


static void draw_startmenu(void) {
    clrscr();
    textcolor(COLOR_GRAY2);
    //     0123456789012345678901234567890123456789
    cputs("libefs Test Cartridge  (c) 2023 Drunella");
}

void draw_version(void)
{
    char text[8];
    uint8_t n;
    
    n = sprintf(text, "v%d.%d.%d", get_version_major(), get_version_minor(), get_version_patch());
    cputsxy(39-n, 24, text);
}

void draw_system(uint8_t s)
{
    cprintf("c64 type: ");
    switch(s) {
        case 0: cprintf("EU-PAL"); break;
        case 1: cprintf("NTSC-old"); break;
        case 2: cprintf("PAL-N"); break;
        case 3: cprintf("NTSC-new"); break;
        default: cprintf("unknown"); break;
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

void loadverify(char* filename, uint8_t verify, uint8_t secondary)
{
    uint8_t retval, status;
    uint32_t timer, seconds;
    char* address;

    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);
    EFS_setnam_wrapper(filename, strlen(filename));
    EFS_setlfs_wrapper(1, secondary);
    cprintf("start\n\r");
    TIMER_reset();
    retval = EFS_load_wrapper((char*)(ADDRESS), verify);
    timer = UINT32_MAX - TIMER_measure();
    address = EFS_get_endadress();
    if (verify == 0) cprintf("l: "); else cprintf("v: ");
    cprintf("sc=%d, rt=%d, sa=$%04x, ea=$%04x\n\r", secondary, retval, ADDRESS, address);
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
    endaddress = address + size;
        
    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);
    EFS_setnam_wrapper(filename, strlen(filename));
    EFS_setlfs_wrapper(1, 0);  // no secondary
    cprintf("start\n\r");
    TIMER_reset();
    retval = EFS_save_wrapper(address, endaddress);
    timer = UINT32_MAX - TIMER_measure();
    cprintf("rt=%d, sa=$%04x se=$%04x\n\r", retval, address, endaddress);
    status = EFS_readst_wrapper();
    seconds = timer / 1000000; timer = timer % 1000000;
    cprintf("st=$%02x, timer=%lu.%06lu s\n\r", status, seconds, timer);

}


void openfile(char* filename, uint8_t secondary)
{
    uint8_t retval, status;

    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);
    EFS_setnam_wrapper(filename, strlen(filename));
    EFS_setlfs_wrapper(1, secondary);
    retval = EFS_open_wrapper();
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
        address[0] = data; address++;
        checksum += data;
    }

    status = EFS_readst_wrapper();
    cprintf("chrin: rt=%d, st=$%02x chksum=%u\n\r", retval, status, checksum);
    
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
    char* address;

    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);

    EFS_setnam_wrapper("$", 1);
    EFS_setlfs_wrapper(1, 0); // do not relocate
    retval = EFS_load_wrapper((char*)(ADDRESS), 0);
    address = EFS_get_endadress();
    status = EFS_readst_wrapper();
    cprintf("st=$%02x, rt=%d, sa=$%4x, ea=$%4x\n\r", status, retval, ADDRESS, address);

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
    EFS_setlfs_wrapper(15, 0); // command channel, do not relocate
    retval = EFS_open_wrapper();
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
    // create test data at C000 to CAFF (2816 bytes)
    // load and save this filem with a recognizable pattern
    // also save, load and delete many other files
    // after a run, the file must still be correct
    uint8_t retval, status;
    char* address = (char*)(ADDRESS);
    uint16_t size = 2687; // 2816;
    uint16_t i;
    char c;
    uint32_t counter = 0;
    uint32_t errors = 0;
    uint32_t verify;
    char filename[] = "myfile";

    createpattern((char*)0xc000, size, counter);
    EFS_setnam_wrapper(filename, strlen(filename));
    EFS_setlfs_wrapper(1, 0);  // no secondary
    retval = EFS_save_wrapper((char*)(0xc000), (char*)(0xc000) + size);
    if (retval != 0) errors++;

    while (true) {
        c = 0;
        if (kbhit()) c = cgetc();
        if (c) break;
        
        menu_clear(CONSOLE_START_Y, 24);
        gotoxy(0, CONSOLE_START_Y);
        cprintf("test run: %lu (errors: %lu)\n\r", counter, errors);

        EFS_setnam_wrapper(filename, strlen(filename));
        EFS_setlfs_wrapper(1, 0);
        retval = EFS_load_wrapper(address, 0); // load
        if (retval != 0) errors++;
            
        EFS_setnam_wrapper(filename, strlen(filename));
        EFS_setlfs_wrapper(1, 0);
        retval = EFS_load_wrapper(address, 1); // verify
        if (retval != 0) errors++;
        status = EFS_readst_wrapper();
        if (status != 0x40) errors++;
            
        verify = atol(address);
        if (verify != counter) errors++;
          
        counter++;
        sprintf(address, "%lu", counter);
        EFS_setnam_wrapper(filename, strlen(filename));
        EFS_setlfs_wrapper(1, 0);
        retval = EFS_save_wrapper(address, address + size);
        if (retval != 0) errors++;
        status = EFS_readst_wrapper();
        if (status != 0x00) errors++;
            
    }

    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);
    cprintf("result: %lu runs, %lu errors\n\r", counter, errors);

    
    
}


void main(void)
{
    bool repaint;
    static char filename_data[20];
    uint8_t secondary;
    char* filename;
    char* commandname;
    char* address;
    uint8_t sysident;
    uint8_t cleartoggle;
    
    filename = &filename_data[3];
    commandname = &filename_data[0];
    repaint = true;
    bgcolor(COLOR_BLACK);
    bordercolor(COLOR_BLACK);
    draw_startmenu();
    sprintf(filename, "delme384");
    secondary = 0;
    memset((char*)ADDRESS, 0, 0x6000);
    cleartoggle = 0;
    
    //sysident = TIMER_get_system();
    sysident = SYS_get_system();
    
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
            menu_option(20, wherey(), '5', "Read file");
            menu_option(20, wherey(), '6', "Directory");
            menu_option(20, wherey(), '8', "Save file");
            gotoxy(0, OUTPUT_START_Y);
            //cprintf("%x (4a:60,9 a6:60,1 51:50,9 c0:50,1)\n\r", sysident);
            draw_system(sysident);
            cprintf("filename: '%s'\n\r", filename);
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
                memset((char*)0xc000, 0, 0x0d00);
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
            openfile(filename, secondary);
            repaint = true;
            break;

        case '4':
            closefile();
            repaint = true;
            break;

        case '5':
            readfile();
            repaint = true;
            break;

        case '6':
            gotoxy(0, CONSOLE_START_Y);
            readdir();
            repaint == true;
            break;

        case '7':
            gotoxy(0, CONSOLE_START_Y);
            scratchfile(commandname);
            repaint == true;
            break;

        case '8':
            gotoxy(0, CONSOLE_START_Y);
            savefile(filename, (char*)(ADDRESS), 1100);
            repaint == true;
            break;

        case '9':
            gotoxy(0, CONSOLE_START_Y);
            format();
            repaint == true;
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
