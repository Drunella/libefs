#!/usr/bin/env python3
"""Regression tests for libefs, run on the test cartridge in VICE.

Each test is a small ca65 program (tests/vice/*.s) that is loaded into the
running test menu through VICE's remote monitor, started at $c000, and
records its results as byte pairs (A, .C) at $c900; $c9f0 is set to $42
when it is done. The expected result bytes are listed in TESTS below.
Some tests run on a patched copy of the cartridge image (a corrupt entry,
a pre-programmed flash byte, ...) and some compare the flash written back
by VICE with the original to make sure nothing outside the read/write
areas changed.

Requirements: a built cartridge (make), cc65 (ca65, ld65), VICE (x64sc,
cartconv), the C64 ROMs (VICE's own search path or $VICE_ROMS), and
xvfb-run when there is no display. Only the Python standard library is
used.

usage: tests/vice/run.py [-k substring] [-j jobs] [-v]
"""
import argparse, os, shutil, socket, struct, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
BIN = os.path.join(ROOT, 'build', 'ef', 'test-libefs.bin')
CRT = os.path.join(ROOT, 'build', 'test-libefs.crt')
ROML = lambda bank: bank * 16384          # offset of a bank's low half in the .bin
ROMH = lambda bank: bank * 16384 + 8192   # offset of a bank's high half

# ---------------------------------------------------------------- recipes
# functions that patch a bytearray of the cartridge image (64 x 16k)

def unclosed_entry(b):
    # directory entry 7 of area 1: a write file that was never closed
    e = bytearray(b'UNCL'.ljust(16, b'\0')) + bytes([0x61, 41, 0, 0xde, 0x06, 0xff, 0xff, 0xff])
    b[ROML(32) + 7 * 24:ROML(32) + 8 * 24] = e

def corrupt_flags(b):
    # entry 3 (DELME641): flags $7f, type bits $1f but not blank
    o = ROML(32) + 3 * 24 + 16
    assert b[o] == 0x61
    b[o] = 0x7f

def preprogrammed_data_byte(b):
    # the third byte the next save writes (after the 7 test files) is $00
    o = ROML(41) + 0x06da
    assert b[o] == 0xff
    b[o] = 0x00

def full_directory(b):
    # all 256 slots of area 1 used, no terminator
    base = ROML(32)
    ents = [bytes(b[base + i * 24:base + i * 24 + 24]) for i in range(7)]
    for i in range(7, 256):
        e = bytearray(ents[i % 7])
        if i == 255:
            e[:16] = b'X255'.ljust(16, b'\0')
        b[base + i * 24:base + i * 24 + 24] = e

def callback_clobbers_xy(b):
    # the defragment warning callback becomes ldx #$ff / ldy #$ff / inc $d020
    o = 0x2000 + 0x1b40
    assert b[o:o + 10] == bytes.fromhex('ad20d01869018d20d060'), b[o:o + 10].hex()
    b[o:o + 10] = bytes.fromhex('a2ffa0ffee20d060eaea')

def copy_area(b, full=True):
    for bank in range(32, 64):
        if not full and bank > 32:
            break
        b[ROMH(bank):ROMH(bank) + 8192] = b[ROML(bank):ROML(bank) + 8192]

S_MARK = 0x17e8  # slot 255 byte 0: "copy started"
D_MARK = 0x17e9  # slot 255 byte 1: "copy complete"

def defrag_incomplete(b):
    copy_area(b, full=False); b[ROML(32) + S_MARK] = 0

def defrag_complete(b):
    copy_area(b); b[ROML(32) + S_MARK] = 0; b[ROMH(32) + D_MARK] = 0

def defrag_nomark(b):
    copy_area(b)

# ------------------------------------------------------------------ tests
# name: (program, expected result bytes (prefix), timeout, options)
# options: patch=recipe, flash=True: banks 0-31 must be unchanged
TESTS = {
    'c5_chrout_overflow':  ('c5_chrout_overflow', '00 00 27 d9 02 48 40 00 00 00 28 d9 02 00 00 42 19 19 19 01 01 01', 300, dict(flash=True)),
    'c6_save_sizes':       ('c6_save_sizes', '00 00 00 00 fe 50 00 00 00 00 00 00 fd 50 00 00 00 00 00 00 fe 51 00 00 00 00 00 00 ff 50 00 00 00 00 00 00 00 50 00 00 00 00 00 00 fe 52 00 00', 120, {}),
    'c7_save_ranges':      ('c7_save_ranges', '1e 01 04 01 00 00 1e 01 04 01 00 00 1e 01 04 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00', 120, {}),
    'c8_scratch_close':    ('c8_scratch_close', '01 00 00 01 07 01 00 00 04 01 03 01 01 00 00 00', 120, dict(flash=True)),
    'm1_verify_flag':      ('m1_verify_flag', '10 01 00 00 40 00 6c 00 00 00 40 00', 120, {}),
    'm1_long_names':       ('m1_long_names', '00 00 04 01 00 00', 120, {}),
    'm2_scratch_errors':   ('m2_scratch_errors', '1a 01 03 01 03 01 01 00 00 00 04 01 1a 01', 120, {}),
    'm2_dir_bounds':       ('m2_dir_bounds', '00 00 d7 00 82 00 00 00', 300, dict(patch=full_directory)),
    'm3_prefix_page':      ('m3_prefix_page', '01 00 04 01 00 00 00 00', 120, {}),
    'm4_drive_number':     ('m4_drive_number', '00 00 1e 01 1e 01 01 00 00 00', 120, {}),
    'm5_zeropage':         ('m5_zeropage', '00 00 00 00 00 00 00 00 00 00 00 00 77 00 00 00 00 00 04 01', 300, {}),
    'm6_minieapi':         ('m6_minieapi', '00 00 1a 01 1a 01 1a 01 1a 01 1a 01 00 00 04 01 cd 00 00 00', 120, {}),
    'm7_chrout_regs':      ('m7_chrout_regs', '00 00 5a 00 a5 00 48 01 40 00 00 00', 300, {}),
    'm8_open_channels':    ('m8_open_channels', '00 00 02 01 02 01 00 00 00 00 07 00 50 00 00 01 02 01 61 00 4b 00 4b 00', 120, {}),
    'm10_validate_incomplete': ('m10_validate', '01 00 00 00 00 00 00 00 00 00 40 00 00 00 00 00', 400, dict(patch=defrag_incomplete)),
    'm10_validate_complete':   ('m10_validate', '01 00 00 00 00 00 00 00 00 00 40 00 00 00 00 00', 400, dict(patch=defrag_complete)),
    'm10_validate_nomark':     ('m10_validate', '47 01 47 01 00 00 00 00 00 00 40 00 00 00 00 00', 400, dict(patch=defrag_nomark)),
    'm10_validate_unclosed':   ('m10_validate', '01 00 00 00 00 00 00 00 00 00 40 00 00 00 00 00', 400, dict(patch=unclosed_entry)),
    'm10_validate_clean':      ('m10_validate', '00 00 00 00 00 00 00 00 00 00 40 00 00 00 00 00', 400, {}),
    'm11_callback_regs':   ('m11_callback_regs', '00 00 00 00 00 00 40 00', 300, dict(patch=callback_clobbers_xy)),
    's1_defrag_contiguous':('s1_defrag_contiguous', '00 00 00 00 01 00 00 00 00 00 00 00 2b 00 51 00', 300, {}),
    's2_unclosed_defrag':  ('s2_unclosed_defrag', '00 00 01 00 00 00 00 00', 300, dict(flash=True)),
    's3_format_open':      ('s3_format_open', '00 00 02 01 00 00 00 00 02 01 00 00 00 00 00 00 11 00 00 00 00 00 00 00', 120, dict(flash=True)),
    's4_open_full_channel':('s4_open_full_channel', '00 00 48 01 40 00 02 01 40 00 19 01 00 00', 300, dict(flash=True)),
    's5_save_64k':         ('s5_save_64k', '00 00 00 00 00 00 48 01', 300, dict(flash=True)),
    's6_failed_save':      ('s6_failed_save', '19 01 04 01 00 00 00 00 00 00', 120, dict(patch=preprogrammed_data_byte)),
    's8_eof':              ('s8_eof', '03 00 64 00 00 01 2a 00 03 00 00 00 26 01 02 01', 120, {}),
    's8_eof_verify':       ('s8_eof_verify', '00 00 00 00 40 00 00 00 64 00 40 00 00 01 40 00 00 00 00 00 ff 00 4f 00 00 00 ff 00 4f 00', 120, {}),
    's9_corrupt_entry':    ('s9_corrupt_entry', '00 00 00 00 00 00 01 00 00 00 00 00', 300, dict(patch=corrupt_flags)),
    's10_exact_fit':       ('s10_exact_fit', '00 00 00 00 00 00 00 00 48 01 00 00 61 00', 300, {}),
    's11_dir_chrin_regs':  ('s11_dir_chrin_regs', '01 00 5a 00 a5 00 00 01 5a 00 a5 00', 120, {}),
    's13_name_kept':       ('s13_name_kept', '00 00 3f 01 00 00 00 00', 120, {}),
    's14_parser_bounds':   ('s14_parser_bounds', '04 01 00 00 08 01 00 00 08 01', 120, {}),
    's15_at_scratch':      ('s15_at_scratch', '1a 01 00 00 00 00 04 00', 120, {}),
    's16_dir_capacity':    ('s16_dir_capacity', '47 01 f8 00', 400, {}),
    's20_api_nits':        ('s20_api_nits', '04 01 00 00 00 00 00 00 00 00', 120, {}),
}

# ---------------------------------------------------------------- helpers

def roms():
    d = os.environ.get('VICE_ROMS')
    if not d:
        d = os.path.expanduser('~/.local/share/vice/C64')
        if not os.path.isdir(d):
            return []
    out = []
    for opt, names in (('-kernal', ('kernal', 'kernal-901227-03.bin')), ('-basic', ('basic', 'basic-901226-01.bin')), ('-chargen', ('chargen', 'chargen-901225-01.bin'))):
        for n in names:
            p = os.path.join(d, n)
            if os.path.exists(p):
                out += [opt, p]; break
    return out

def chips(fn):
    d = open(fn, 'rb').read()
    p = struct.unpack('>I', d[0x10:0x14])[0]
    out = {}
    while p < len(d):
        plen, ctype, bank, addr, size = struct.unpack('>IHHHH', d[p + 4:p + 16])
        out[(bank, addr)] = d[p + 16:p + 16 + size]; p += plen
    return out

def flash_changes_outside_rw(a, b):
    ca, cb = chips(a), chips(b)
    n = 0
    for k in sorted(set(ca) | set(cb)):
        if k[0] >= 32:
            continue
        da = ca.get(k, b'\xff' * 0x2000); db = cb.get(k, b'\xff' * 0x2000)
        n += sum(1 for i in range(0x2000) if (da[i] if i < len(da) else 0xff) != (db[i] if i < len(db) else 0xff))
    return n

class Vice:
    def __init__(self, crt, port, writeback):
        self.port = port
        cmd = ['x64sc', '-default'] + roms() + ['-sounddev', 'dummy', '-warp',
               '-easyflashcrtwrite' if writeback else '+easyflashcrtwrite',
               '-cartcrt', crt, '-remotemonitor', '-remotemonitoraddress', 'ip4://127.0.0.1:%d' % port]
        if not os.environ.get('DISPLAY') and shutil.which('xvfb-run'):
            cmd = ['xvfb-run', '-a'] + cmd
        self.p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for i in range(60):
            try:
                socket.create_connection(('127.0.0.1', port)).close(); break
            except OSError:
                time.sleep(1)
        time.sleep(8)  # boot into the menu

    def cmd(self, c, wait=0.5, cont=True):
        s = socket.create_connection(('127.0.0.1', self.port)); s.settimeout(3)
        s.sendall((c + '\n').encode()); time.sleep(wait)
        data = b''
        try:
            while True:
                d = s.recv(65536)
                if not d: break
                data += d
        except Exception:
            pass
        if cont:
            s.sendall(b'x\n')
        s.close()
        return data.decode('latin1')

    def mem(self, a, n):
        out = self.cmd('m %04x %04x' % (a, a + n - 1), 1.0)
        vals = []
        for line in out.splitlines():
            if '>C:' in line:
                for t in line[line.index('>C:') + 3:].split()[1:]:
                    if len(t) == 2 and all(ch in '0123456789abcdefABCDEF' for ch in t):
                        vals.append(int(t, 16))
                    else:
                        break
        return vals[:n]

    def quit(self):
        try:
            self.cmd('quit', 1)
        except Exception:
            pass
        for i in range(20):
            if self.p.poll() is not None:
                return
            time.sleep(0.5)
        self.p.terminate()

def run_test(name, index, verbose):
    prog, expected, timeout, opt = TESTS[name]
    exp = bytes.fromhex(expected)
    tmp = tempfile.mkdtemp(prefix='libefs-' + name + '-', dir=HERE)
    try:
        # program
        src = os.path.join(HERE, prog + '.s')
        obj = os.path.join(tmp, prog + '.o'); prg = os.path.join(tmp, prog + '.prg')
        subprocess.check_call(['ca65', '-I', HERE, '-o', obj, src])
        subprocess.check_call(['ld65', '-C', os.path.join(HERE, 'test.cfg'), '-o', prg, obj])
        # cartridge (patched if needed; always a copy, VICE may write it back)
        crt = os.path.join(tmp, 'run.crt')
        if opt.get('patch'):
            b = bytearray(open(BIN, 'rb').read()); opt['patch'](b)
            binp = os.path.join(tmp, 'run.bin'); open(binp, 'wb').write(b)
            subprocess.check_call(['cartconv', '-b', '-t', 'easy', '-o', crt, '-i', binp, '-n', 'libefs test', '-p'], stdout=subprocess.DEVNULL)
        else:
            shutil.copy(CRT, crt)
        orig = crt + '.orig'; shutil.copy(crt, orig)
        v = Vice(crt, 6510 + index, opt.get('flash', False))
        try:
            v.cmd('l "%s" 0' % prg, 1.0)
            v.cmd('g c000', 1.0, cont=False)
            t0 = time.time(); done = False
            while time.time() - t0 < timeout:
                time.sleep(3)
                try:
                    if v.mem(0xc9f0, 1) == [0x42]:
                        done = True; break
                except Exception:
                    pass
            got = bytes(v.mem(0xc900, len(exp))) if done else b''
        finally:
            v.quit()
        if not done:
            return False, 'timeout (program did not finish)'
        if got != exp:
            return False, 'results differ\n    expected %s\n    got      %s' % (exp.hex(' '), got.hex(' '))
        if opt.get('flash'):
            n = flash_changes_outside_rw(orig, crt)
            if n:
                return False, '%d flash bytes changed outside the read/write areas' % n
        return True, ''
    finally:
        if not verbose:
            shutil.rmtree(tmp, ignore_errors=True)

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-k', dest='select', default='', help='run only tests whose name contains this')
    ap.add_argument('-j', dest='jobs', type=int, default=4, help='parallel VICE instances')
    ap.add_argument('-v', dest='verbose', action='store_true', help='keep the temporary files')
    args = ap.parse_args()
    for f, what in ((BIN, 'cartridge image'), (CRT, 'cartridge')):
        if not os.path.exists(f):
            sys.exit('missing %s %s: run make first' % (what, f))
    for tool in ('x64sc', 'cartconv', 'ca65', 'ld65'):
        if not shutil.which(tool):
            sys.exit('missing tool: ' + tool)
    names = [n for n in TESTS if args.select in n]
    results = {}
    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futs = {ex.submit(run_test, n, i, args.verbose): n for i, n in enumerate(names)}
        for f in futs:
            n = futs[f]
            try:
                results[n] = f.result()
            except Exception as e:
                results[n] = (False, 'error: %s' % e)
            ok, msg = results[n]
            print('%-28s %s%s' % (n, 'PASS' if ok else 'FAIL', ('  ' + msg) if msg else ''), flush=True)
    failed = [n for n in names if not results[n][0]]
    print('%d tests, %d failed' % (len(names), len(failed)))
    sys.exit(1 if failed else 0)

if __name__ == '__main__':
    main()
