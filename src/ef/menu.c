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

#include "util.h"


#define MENU_START_Y 3
#define OUTPUT_START_Y 10
#define CONSOLE_START_Y 15
#define ADDRESS 0x3000


static void draw_startmenu(void) {
    clrscr();
    textcolor(COLOR_GRAY2);
    //     01234567890123456789001234567890123456789
    cputs("          libefs Test Cartridge\r\n"
          "       Copyright (c) 2023 Drunella\r\n"
          "\r\n");
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
    EFS_setlfs_wrapper(0, secondary);
    cprintf("start\n\r");
    TIMER_reset();
    retval = EFS_load_wrapper((char*)(ADDRESS), verify);
    timer = UINT32_MAX - TIMER_measure();
    address = EFS_get_endadress();
    if (verify == 0) cprintf("l: "); else cprintf("v: ");
    cprintf("sc=%d, rt=%d, sa=$%4x, ea=$%4x\n\r", secondary, retval, ADDRESS, address);
    status = EFS_readst_wrapper();
    seconds = timer / 1000000; timer = timer % 1000000;
    cprintf("st: $%02x, timer = %lu.%06lu sec\n\r", status, seconds, timer);
}

void openfile(char* filename, uint8_t secondary)
{
    uint8_t retval, status;

    menu_clear(CONSOLE_START_Y, 24);
    gotoxy(0, CONSOLE_START_Y);
    EFS_setnam_wrapper(filename, strlen(filename));
    EFS_setlfs_wrapper(0, secondary);
    retval = EFS_open_wrapper();
    status = EFS_readst_wrapper();
    cprintf("open: sc=%d, rt=%d, st=$%02x\n\r", secondary, retval, status);
  
}

void readfile(void)
{
    uint8_t retval, status, data;
    uint16_t checksum = 0;
    
    while (true) {
        retval = EFS_chrin_wrapper(&data);
        if (retval != 0) break;
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


void main(void)
{
    bool repaint;
    static char filename[17];
    uint8_t secondary;
    char* address;
    //uint16_t systimer;
    uint8_t sysident;
    
    repaint = true;
    bgcolor(COLOR_BLACK);
    bordercolor(COLOR_BLACK);
    draw_startmenu();
    sprintf(filename, "data3k");
    secondary = 0;
    memset((char*)ADDRESS, 0, 0x6000);
    
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
            menu_option(0, wherey(), 'Q', "Quit to basic");
            gotoxy(0, MENU_START_Y);
            menu_option(20, wherey(), 'S', "Toggle secondary");
            menu_option(20, wherey(), '0', "Fail tests");
            menu_option(20, wherey(), '3', "Open file");
            menu_option(20, wherey(), '4', "Close file");
            menu_option(20, wherey(), '5', "Read file");
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
            repaint = 1;
            break;

        case 'c':
            memset((char*)ADDRESS, 0, 0x6000);
            repaint = 1;
            break;

        case 's':
            if (secondary == 0) secondary = 1; else secondary = 0;
            repaint = 1;
            break;

        case '0':
            fail_tests_3();
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
