#!/usr/bin/env python3
"""Boot a ROM in ares-mcp and report whether it runs cleanly.

Thin, dependency-free MCP driver for the one question an agent asks after building a
ROM: did it boot, does the CPU keep executing, and did anything blow up? It is
scriptable (one verdict line, meaningful exit code), unlike the e2e suite in
mcp_client.py, whose content assertions are written for the generated green.z64.

    boot_check.py --rom game.z64 [--frames 120] [--bin PATH] [--no-homebrew]
                  [--expansion] [--region auto|ntsc|pal] [--screenshot out.png]
                  [--expect-log REGEX] [--allow-errors] [--quiet]

Checks: the 10 n64_* tools exist, n64_load accepts the ROM, n64_run advances the
requested number of frames, n64_status agrees, and the core log contains no exception
/ assertion text. Prints the log tail on failure so the reason is visible.

Exit codes: 0 boot OK - 1 could not load/boot - 2 stalled (fewer frames than asked,
or the game exited) - 3 the log reports an exception (unless --allow-errors) -
4 protocol/binary problem.

`--screenshot` writes the frame PNG; without a Vulkan driver and an ares built with
paraLLEl-RDP, RDP-drawn content is blank there (emulation is unaffected). See
../BUILD.txt.
"""

import argparse
import base64
import json
import os
import re
import select
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
BAD = ('exception', 'assertion failed', 'panic', 'illegal instruction',
       'address error', 'unaligned', 'tlb refill', 'debugger trap')


class Client:
    def __init__(self, binary, verbose=False, timeout=120):
        self.timeout = timeout
        self.stderr_log = tempfile.NamedTemporaryFile(
            'w+', prefix='boot-check-ares-', suffix='.log', delete=False)
        self.proc = subprocess.Popen(
            [binary, 'mcp'] + (['--verbose'] if verbose else []),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.stderr_log,
            cwd=os.path.dirname(os.path.abspath(binary)) or None)
        self.next_id = 0

    def _send(self, msg):
        self.proc.stdin.write(json.dumps(msg).encode() + b'\n')
        self.proc.stdin.flush()

    def request(self, method, params=None):
        self.next_id += 1
        msg = {'jsonrpc': '2.0', 'id': self.next_id, 'method': method}
        if params is not None:
            msg['params'] = params
        self._send(msg)
        # Read with a deadline and tolerate stray/blank lines: a check that hangs
        # forever is worse for automation than one that fails, and the emulator can
        # legitimately spend a while inside n64_run.
        r, deadline = None, time.monotonic() + self.timeout
        while r is None:
            left = deadline - time.monotonic()
            if left <= 0:
                raise RuntimeError(f'timed out after {self.timeout}s waiting for '
                                   f'the answer to {method}')
            if not select.select([self.proc.stdout], [], [], min(2.0, left))[0]:
                if self.proc.poll() is not None:
                    raise RuntimeError(f'server exited without answering {method}')
                continue
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError('server closed stdout without answering ' + method)
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except ValueError:
                continue
        if 'error' in r:
            raise RuntimeError(f'{method}: {r["error"].get("message", r["error"])}')
        return r['result']

    def notify(self, method, params=None):
        msg = {'jsonrpc': '2.0', 'method': method}
        if params is not None:
            msg['params'] = params
        self._send(msg)

    def call(self, tool, **arguments):
        r = self.request('tools/call', {'name': tool, 'arguments': arguments})
        if r.get('isError'):
            text = next((i['text'] for i in r['content'] if i['type'] == 'text'), '?')
            raise RuntimeError(f'{tool}: {text}')
        return r

    @staticmethod
    def text(result):
        return next((i['text'] for i in result['content'] if i['type'] == 'text'), '')

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=10)
        except Exception:
            self.proc.kill()
        self.stderr_log.flush()
        self.stderr_log.seek(0)
        return self.stderr_log.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rom', required=True)
    ap.add_argument('--bin', default=os.environ.get('N64_MCP') or
                    os.path.abspath(os.path.join(HERE, os.pardir, 'bin', 'ares-mcp')))
    ap.add_argument('--frames', type=int, default=120)
    ap.add_argument('--homebrew', dest='homebrew', action='store_true', default=True,
                    help='emux extensions; on by default because libdragon ROMs expect it')
    ap.add_argument('--no-homebrew', dest='homebrew', action='store_false')
    ap.add_argument('--expansion', action='store_true', help='8 MB Expansion Pak')
    ap.add_argument('--region', default='auto')
    ap.add_argument('--screenshot', metavar='PATH', help='write the PNG here')
    ap.add_argument('--expect-log', metavar='REGEX', help='fail unless the log matches')
    ap.add_argument('--allow-errors', action='store_true',
                    help='do not fail on exception/assertion text in the log')
    ap.add_argument('--server-verbose', action='store_true')
    ap.add_argument('--timeout', type=int, default=120,
                    help='seconds to wait for one MCP answer (n64_run blocks while emulating)')
    ap.add_argument('--quiet', action='store_true')
    args = ap.parse_args()

    rom = os.path.abspath(args.rom)
    if not os.path.isfile(rom):
        print(f'FAIL: no such ROM: {rom}')
        return 1
    if not os.access(args.bin, os.X_OK):
        print(f'FAIL: ares-mcp not executable: {args.bin} (or export N64_MCP)')
        return 4

    def say(*a):
        if not args.quiet:
            print(*a)

    say(f'rom:      {rom}')
    say(f'binary:   {args.bin}')
    try:
        c = Client(args.bin, verbose=args.server_verbose, timeout=args.timeout)
    except OSError as e:
        print(f'FAIL: cannot run {args.bin}: {e}')
        return 4

    rc, note, log, status = 0, '', '', {}
    try:
        c.request('initialize', {'protocolVersion': '2025-03-26', 'capabilities': {},
                                'clientInfo': {'name': 'n64dev-boot-check', 'version': '1'}})
        c.notify('notifications/initialized')
        tools = {t['name'] for t in c.request('tools/list')['tools']}
        want = {'n64_status', 'n64_load', 'n64_run', 'n64_input', 'n64_screenshot',
                'n64_log', 'n64_record', 'n64_pause', 'n64_resume', 'n64_stop'}
        if not want <= tools:
            raise RuntimeError(f'server lacks tools: {sorted(want - tools)}')

        loaded = c.text(c.call('n64_load', rom=rom, homebrew=args.homebrew,
                              region=args.region, expansion_pak=args.expansion))
        say('load:     ' + loaded[:120])
        say('run:      ' + c.text(c.call('n64_run', frames=args.frames))[:120])

        status = json.loads(c.text(c.call('n64_status')))
        say(f'status:   {json.dumps(status)}')

        if args.screenshot:
            r = c.call('n64_screenshot')
            png = next((base64.b64decode(i['data']) for i in r['content']
                        if i['type'] == 'image'), b'')
            with open(args.screenshot, 'wb') as f:
                f.write(png)
            say(f'video:    {len(png)} byte PNG -> {args.screenshot}'
                ' (blank without a Vulkan RDP backend)')

        log = c.text(c.call('n64_log', limit=200))
        logl = log.lower()
        hits = [w for w in BAD if w in logl]
        if args.expect_log and not re.search(args.expect_log, log, re.I):
            rc, note = 3, f'--expect-log {args.expect_log!r} not found in the core log'
        if hits and not args.allow_errors and rc == 0:
            rc, note = 3, f'core log reports {" / ".join(hits)}'
        if rc == 0:
            if not status.get('loaded'):
                rc, note = 1, 'console reports no ROM loaded'
            elif status.get('frames', 0) < args.frames:
                rc, note = 2, f"only {status.get('frames')} of {args.frames} frames advanced"
            elif status.get('game_exited'):
                rc, note = 2, 'the game exited before the check finished'

        try:
            c.call('n64_stop')
        except Exception:
            pass
    except RuntimeError as e:
        rc, note = 1, str(e)
    except Exception as e:                      # protocol/JSON trouble: report, no traceback
        rc, note = 4, f'{type(e).__name__}: {e}'
    finally:
        server_log = c.close()

    if rc:
        print(f'BOOT FAIL ({rc}): {os.path.basename(rom)} - {note}')
        tail = [l for l in log.splitlines() if l][-8:]
        if tail:
            print('  core log tail:')
            for l in tail:
                print(f'    {l}')
        if server_log.strip():
            print('  server stderr tail:')
            for l in server_log.strip().splitlines()[-6:]:
                print(f'    {l}')
        return rc

    say(f"BOOT OK: '{status.get('name')}' ran {status.get('frames')} frames "
        f"({status.get('region')}), no exceptions in the log")
    return 0


if __name__ == '__main__':
    sys.exit(main())
