#!/usr/bin/env python3
"""EMF debug bridge client (docs/modding/debug_bridge.md), standard library only, one file.

Talks to a running Enshrouded with [debug] bridge=1 in emf\\emf_core.ini, through the named pipe that
emf\\bridge.txt names.

As a library:

    from emf_bridge import Bridge
    with Bridge(game=r"C:\\SteamLibrary\\steamapps\\common\\Enshrouded") as b:
        print(b.hello())
        b.wait("world", timeout_ms=120000)
        print(b.state()["player"])
        r = b.console("put Material_T1_Wood_Logs 1")      # waits for late lines (settle_ms, 300 by default)
        print(r["status"], r["output"])
        b.wait("log", match="1 added", since=r["log_seq"])  # no race: lines after the command
        b.mod_key("L")
        print(b.screenshot(max_width=1280)["path"])
        for event in b.follow_log():
            print(event["line"])

    with Bridge() as b:                                 # from the main menu, no clicks:
        print(b.load_world(1, 1, "<name>"))              # LOCAL world slot 1, LOCAL character slot 1 (LoadWorldError
                                                        # in plain words when nothing started)

From the command line:

    python emf_bridge.py hello
    python emf_bridge.py console "near 10" [--settle-ms 300]
    python emf_bridge.py state
    python emf_bridge.py wait world 120
    python emf_bridge.py wait log "[life_skills]" 60 [--since N]
    python emf_bridge.py log [--since N] [--follow]
    python emf_bridge.py events pickup,kill
    python emf_bridge.py shot [--no-overlay] [--max-width 1280]
    python emf_bridge.py key L [--down | --up] [--hold-ms 150]
    python emf_bridge.py quit
    python emf_bridge.py load_world 1 1 "<character name>" [--timeout-ms 180000]   (from the main menu, LOCAL saves only)
    python emf_bridge.py raw '{"cmd": "hello"}'

--json prints the game's reply as it came. It finds the game through --pid, --game <folder>, its own place (installed
as <game>\\emf\\tools\\), a running enshrouded.exe / enshrouded_server.exe, or Steam; only a pipe the game named in
emf\\bridge.txt, served by that game, is used. Exit codes: 0 done, 1 the bridge said no (or timed out), 2 no
connection.
"""

import argparse
import ctypes
import json
import msvcrt
import os
import re
import sys
import time
from ctypes import wintypes

PIPE_RE = re.compile(r"^\\\\\.\\pipe\\emf-bridge-(\d{1,10})$")

_k32 = ctypes.WinDLL("kernel32", use_last_error=True)
_k32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD,
                             wintypes.DWORD, wintypes.HANDLE]
_k32.CreateFileW.restype = wintypes.HANDLE
_k32.WaitNamedPipeW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD]
_k32.WaitNamedPipeW.restype = wintypes.BOOL
_k32.CloseHandle.argtypes = [wintypes.HANDLE]
_k32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
_k32.OpenProcess.restype = wintypes.HANDLE
_k32.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR,
                                             ctypes.POINTER(wintypes.DWORD)]
_k32.QueryFullProcessImageNameW.restype = wintypes.BOOL
_k32.GetNamedPipeServerProcessId.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.ULONG)]
_k32.GetNamedPipeServerProcessId.restype = wintypes.BOOL
_k32.K32EnumProcesses.argtypes = [ctypes.POINTER(wintypes.DWORD), wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
_k32.K32EnumProcesses.restype = wintypes.BOOL
_k32.PeekNamedPipe.argtypes = [wintypes.HANDLE, wintypes.LPVOID, wintypes.DWORD, wintypes.LPVOID,
                               ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
_k32.PeekNamedPipe.restype = wintypes.BOOL
_k32.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
_k32.GetProcessTimes.restype = wintypes.BOOL

# How long a reply may take: the command's own time (timeout_ms, settle, hold) plus this margin. A game that is stuck
# (crashed, paused in a debugger) would otherwise leave a client waiting for ever. EMF_BRIDGE_REPLY_MARGIN_MS changes
# the margin (tests).
DEFAULT_REPLY_MARGIN_MS = 15000
# load_world: the game answers when the local player is in the world (about 12 s on a fast PC, longer on a slow one),
# at the latest after its timeout_ms (default 180 s) plus a 10 s backstop of its own (kLoadWorldSlackMs).
LOAD_WORLD_SLACK_MS = 10000
_COMMAND_MS = {"console": 10000, "wait": 30000, "screenshot": 5000, "load_world": 180000}


def reply_timeout_s(cmd, fields):
    """Seconds to wait for the reply to `cmd` with these request fields."""
    ms = fields.get("timeout_ms") or _COMMAND_MS.get(cmd, 0)
    if cmd == "console":
        ms += min(max(int(fields.get("settle_ms", 300)), 0), 5000)
    if cmd == "mod_key" and fields.get("action", "press") == "press":
        ms += int(fields.get("hold_ms", 150))
    if cmd == "load_world":
        ms += LOAD_WORLD_SLACK_MS
    margin = os.environ.get("EMF_BRIDGE_REPLY_MARGIN_MS", "")
    return ms / 1000.0 + (int(margin) if margin.isdigit() else DEFAULT_REPLY_MARGIN_MS) / 1000.0

INVALID_HANDLE = wintypes.HANDLE(-1).value
GENERIC_READ, GENERIC_WRITE = 0x80000000, 0x40000000
OPEN_EXISTING = 3
SECURITY_SQOS_PRESENT, SECURITY_IDENTIFICATION = 0x00100000, 0x00010000
ERROR_FILE_NOT_FOUND, ERROR_PIPE_BUSY = 2, 231
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000


class BridgeError(Exception):
    """The bridge answered ok: false. .code is its machine-readable code, .reply the whole reply."""

    def __init__(self, reply):
        self.reply = reply
        self.code = reply.get("code", "")
        super().__init__("%s: %s" % (self.code, reply.get("error", "failed")))


def load_world_message(code, error):
    """Plain words for a load_world that did not start a world: what happened (the game's own words) and what to
    do. The codes are the bridge's (debug_bridge.md: refused, unavailable, busy, timeout, bad_request)."""
    error = (error or "").rstrip(".")
    if code == "refused":
        return ("the game refused the start, nothing started: %s. Check the LOCAL world and character slots and the "
                "character's name (load_world never starts a Steam Cloud save)." % error)
    if code == "unavailable":
        return ("load_world could not start the world: %s. It works from the main menu of a game with the bridge on "
                "(the game exe of build 1273043 or 1283531, not the dedicated server)." % error)
    if code == "busy":
        return "another load_world is already running: %s. Wait for its reply." % error
    if code == "timeout":
        return ("the world did not start in time: %s. The game may still start it: check the state's world.status "
                "before you try again." % error)
    if code == "bad_request":
        return "the load_world request is wrong: %s." % error
    if code == "unknown_command":
        return ("this game's EMF has no load_world (an older build): start the world in the game's menu, or install a "
                "newer EMF.")
    return "load_world failed (%s): %s." % (code or "error", error)


class LoadWorldError(BridgeError):
    """A load_world that did not start a world. str() is load_world_message(); .code and .reply as in BridgeError."""

    def __init__(self, reply):
        super().__init__(reply)
        self.args = (load_world_message(self.code, reply.get("error", "")),)


class ConnectError(Exception):
    """No connection to the game's bridge."""


def _process_path(pid):
    h = _k32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not h:
        return ""
    try:
        buf = ctypes.create_unicode_buffer(1024)
        size = wintypes.DWORD(len(buf))
        return buf.value if _k32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size)) else ""
    finally:
        _k32.CloseHandle(h)


def process_start_epoch(pid):
    """When the process started, in seconds since 1970 (UTC), or None when it does not run (or cannot be asked). With
    the pid it names one process: a pid can be reused, its start time not."""
    h = _k32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not h:
        return None
    try:
        times = [wintypes.FILETIME() for _ in range(4)]
        if not _k32.GetProcessTimes(h, *[ctypes.byref(t) for t in times]):
            return None
        ticks = (times[0].dwHighDateTime << 32) | times[0].dwLowDateTime  # 100 ns since 1601-01-01 UTC
        return ticks / 1e7 - 11644473600.0
    finally:
        _k32.CloseHandle(h)


def is_game_process(pid):
    """The pid runs and is enshrouded*.exe (EMF_BRIDGE_TEST_PROCESS names one more process, for tests only)."""
    name = os.path.splitext(os.path.basename(_process_path(pid)))[0].lower()
    if not name:
        return False
    return name.startswith("enshrouded") or name == os.environ.get("EMF_BRIDGE_TEST_PROCESS", "\0").lower()


def _running_games():
    """(pid, folder) of each running enshrouded.exe / enshrouded_server.exe."""
    pids = (wintypes.DWORD * 4096)()
    needed = wintypes.DWORD()
    if not _k32.K32EnumProcesses(pids, ctypes.sizeof(pids), ctypes.byref(needed)):
        return []
    out = []
    for pid in pids[: needed.value // ctypes.sizeof(wintypes.DWORD)]:
        path = _process_path(pid)
        if os.path.basename(path).lower() in ("enshrouded.exe", "enshrouded_server.exe"):
            out.append((pid, os.path.dirname(path)))
    return out


def _listed_pipes():
    """The names of the named pipes on this computer, lower case (listing them connects to none)."""
    try:
        return {n.lower() for n in os.listdir("\\\\.\\pipe\\")}
    except OSError:
        return set()


def serves_bridge(pid, folder, pipes=None):
    """The game process serves its bridge: \\\\.\\pipe\\emf-bridge-<pid> exists, or <folder>\\emf\\bridge.txt names
    that pipe and that pid."""
    name = "emf-bridge-%d" % pid
    if name in (_listed_pipes() if pipes is None else pipes):
        return True
    info = {}
    try:
        with open(os.path.join(folder, "emf", "bridge.txt"), "r", encoding="utf-8", errors="replace") as f:
            for line in f.read(4096).splitlines():
                if "=" in line:
                    k, v = line.split("=", 1)
                    info[k.strip()] = v.strip()
    except OSError:
        return False
    return info.get("pipe", "").lower() == "\\\\.\\pipe\\" + name and info.get("pid") == str(pid)


def read_bridge_file(game):
    """The pipe from <game>\\emf\\bridge.txt, checked (a local EMF pipe whose pid is pid= and a running game), or
    None when there is no file. Raises ConnectError for a file that is wrong or left over."""
    path = os.path.join(game, "emf", "bridge.txt")
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            info = {}
            for line in f.read(4096).splitlines():
                if "=" in line:
                    k, v = line.split("=", 1)
                    info[k.strip()] = v.strip()
    except OSError:
        return None
    m = PIPE_RE.match(info.get("pipe", ""))
    if not m:
        raise ConnectError("%s names no local EMF bridge pipe: not using it" % path)
    if not info.get("pid", "").isdigit():
        raise ConnectError("%s has no valid pid= line" % path)
    if int(info["pid"]) != int(m.group(1)):
        raise ConnectError("%s is inconsistent (the pipe's pid is not pid=): not using it" % path)
    if not is_game_process(int(info["pid"])):
        raise ConnectError("%s is left over: no game runs with pid %s" % (path, info["pid"]))
    return info["pipe"]


def _steam_game_folder():
    try:
        import winreg
    except ImportError:
        return None
    for hive, key in ((winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam"),
                      (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam")):
        try:
            with winreg.OpenKey(hive, key) as k:
                try:
                    root = winreg.QueryValueEx(k, "SteamPath")[0]
                except OSError:
                    root = winreg.QueryValueEx(k, "InstallPath")[0]
        except OSError:
            continue
        root = root.replace("/", "\\")
        libs = [root]
        try:
            with open(os.path.join(root, "steamapps", "libraryfolders.vdf"), encoding="utf-8") as f:
                libs += [m.replace("\\\\", "\\") for m in re.findall(r'"path"\s+"(.+?)"', f.read())]
        except OSError:
            pass
        for lib in libs:
            d = os.path.join(lib, "steamapps", "common", "Enshrouded")
            if os.path.isfile(os.path.join(d, "enshrouded.exe")):
                return d
    return None


def find_pipe(game=None, pid=None):
    """The game's pipe: from --pid, --game's bridge.txt, this file's place (<game>\\emf\\tools\\), a running game, or
    Steam."""
    if pid:
        if not is_game_process(pid):
            raise ConnectError("no game runs with pid %d" % pid)
        return "\\\\.\\pipe\\emf-bridge-%d" % pid
    if game:
        found = read_bridge_file(game)
        if not found:
            raise ConnectError("no %s: is the game running with [debug] bridge=1 in emf\\emf_core.ini?"
                               % os.path.join(game, "emf", "bridge.txt"))
        return found
    own = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # <game>\emf\tools\ -> <game>
    if any(os.path.isfile(os.path.join(own, exe)) for exe in ("enshrouded.exe", "enshrouded_server.exe")):
        found = read_bridge_file(own)
        if found:
            return found
    games = _running_games()
    if len(games) > 1:
        # a stand-in or a second game without the bridge (say a test's enshrouded_server.exe) does not count
        found = len(games)
        pipes = _listed_pipes()
        games = [g for g in games if serves_bridge(g[0], g[1], pipes)]
        if len(games) > 1:
            raise ConnectError("more than one game with the debug bridge is running (pids %s): pass --pid or --game"
                               % ", ".join(str(g[0]) for g in games))
        if not games:
            raise ConnectError("%d game processes run, none with the debug bridge on: is [debug] bridge=1 set in "
                               "emf\\emf_core.ini?" % found)
    if games:
        found = read_bridge_file(games[0][1])
        if found:
            return found
        raise ConnectError("the game runs (pid %d) but has no emf\\bridge.txt: is [debug] bridge=1 set?" % games[0][0])
    steam = _steam_game_folder()
    if steam:
        found = read_bridge_file(steam)
        if found:
            return found
    raise ConnectError("the game is not running (or [debug] bridge=1 is not set in emf\\emf_core.ini)")


def _open_pipe(path, wait_s):
    """Opens the pipe at identification level (the game can tell who connects, not act as this user)."""
    deadline = time.monotonic() + wait_s
    while True:
        h = _k32.CreateFileW(path, GENERIC_READ | GENERIC_WRITE, 0, None, OPEN_EXISTING,
                             SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, None)
        if h and h != INVALID_HANDLE:
            fd = msvcrt.open_osfhandle(h, os.O_RDWR | os.O_BINARY)
            return os.fdopen(fd, "r+b", buffering=0)
        err = ctypes.get_last_error()
        if err == ERROR_FILE_NOT_FOUND:
            raise ConnectError("no pipe %s: is the game running with [debug] bridge=1?" % path)
        if err != ERROR_PIPE_BUSY or time.monotonic() > deadline:
            raise ConnectError("could not connect to %s (error %d; 8 clients connected already?)" % (path, err))
        _k32.WaitNamedPipeW(path, 1000)  # all 8 places taken: wait for one


class Bridge:
    """One connection to the game's debug bridge. Requests are answered in order; pushed events (log lines, game
    events) that arrive meanwhile are kept in .events."""

    def __init__(self, game=None, pid=None, connect_timeout=30.0):
        self.pipe_path = find_pipe(game, pid)
        self._f = _open_pipe(self.pipe_path, connect_timeout)
        self._check_server()
        self._buf = b""
        self._next_id = 1
        self.events = []
        self.last_line = ""

    @classmethod
    def from_file(cls, f, pipe_path):
        """A Bridge on a pipe opened elsewhere (tests), without finding or checking the game."""
        b = cls.__new__(cls)
        b.pipe_path, b._f, b._buf, b._next_id, b.events, b.last_line = pipe_path, f, b"", 1, [], ""
        return b

    def _check_server(self):
        """The pipe must belong to the game it is named after (another program could have made it first)."""
        m = PIPE_RE.match(self.pipe_path)
        server = wintypes.ULONG(0)
        handle = wintypes.HANDLE(msvcrt.get_osfhandle(self._f.fileno()))
        if not m or not _k32.GetNamedPipeServerProcessId(handle, ctypes.byref(server)) or server.value != int(m.group(1)):
            self.close()
            raise ConnectError("%s is served by process %d, not by the game: not using it" % (self.pipe_path, server.value))

    def close(self):
        if self._f:
            self._f.close()
            self._f = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    # ---- the wire ----
    def _available(self):
        """Bytes waiting in the pipe (PeekNamedPipe never blocks)."""
        n = wintypes.DWORD(0)
        handle = wintypes.HANDLE(msvcrt.get_osfhandle(self._f.fileno()))
        if not _k32.PeekNamedPipe(handle, None, 0, None, ctypes.byref(n), None):
            raise ConnectError("the game closed the connection")
        return n.value

    def _read_line(self, deadline=None):
        """The next line. With a deadline (time.monotonic()): ConnectError when it has not come by then, and the
        connection is closed (a late reply could not be told from the next one)."""
        while b"\n" not in self._buf:
            if deadline is None:
                chunk = self._f.read(65536)
            else:
                waiting = self._available()
                if not waiting:
                    if time.monotonic() > deadline:
                        self.close()
                        raise ConnectError("no reply from the game in time: is it stuck (crashed, paused)?")
                    time.sleep(0.01)
                    continue
                chunk = self._f.read(min(waiting, 65536))
            if not chunk:
                raise ConnectError("the game closed the connection")
            self._buf += chunk
        line, self._buf = self._buf.split(b"\n", 1)
        self.last_line = line.decode("utf-8")
        return json.loads(self.last_line)

    def send(self, cmd, reply_timeout=None, **fields):
        """Sends {"id", "cmd", **fields} and returns the reply as it is (ok or not). It must come within reply_timeout
        seconds (default: the command's own time plus a margin, reply_timeout_s), else ConnectError."""
        if self._f is None:
            raise ConnectError("the connection is closed")
        rid = self._next_id
        self._next_id += 1
        msg = dict(fields, id=rid, cmd=cmd)
        deadline = time.monotonic() + (reply_timeout if reply_timeout is not None else reply_timeout_s(cmd, fields))
        self._f.write((json.dumps(msg) + "\n").encode("utf-8"))
        while True:
            reply = self._read_line(deadline)
            if "event" in reply:
                self.events.append(reply)
                continue
            if reply.get("id") == rid:
                return reply

    def request(self, cmd, **fields):
        """Like send(), but raises BridgeError when the reply says ok: false."""
        reply = self.send(cmd, **fields)
        if not reply.get("ok"):
            raise BridgeError(reply)
        return reply

    def next_event(self):
        """The next pushed event (log line or game event), waiting for it."""
        if self.events:
            return self.events.pop(0)
        while True:
            msg = self._read_line()
            if "event" in msg:
                return msg

    # ---- commands ----
    def hello(self):
        return self.request("hello")

    def console(self, text, timeout_ms=None, settle_ms=None):
        """Runs a console command: {"status": "ran" | "unknown" | ..., "output": [...], "log_seq": n}."""
        fields = {"text": text}
        if timeout_ms:
            fields["timeout_ms"] = timeout_ms
        if settle_ms is not None:
            fields["settle_ms"] = settle_ms
        return self.request("console", **fields)

    def state(self):
        return self.request("state")

    def mods(self):
        return self.request("mods")["mods"]

    def log(self, since=None, max_lines=None, follow=None):
        fields = {}
        if since is not None:
            fields["since"] = since
        if max_lines:
            fields["max"] = max_lines
        if follow is not None:
            fields["follow"] = follow
        return self.request("log", **fields)

    def follow_log(self, since=None):
        """Yields log events ({"event": "log", "seq", "line"}) as they come, starting after `since` (or now)."""
        reply = self.log(since=since, follow=True)
        for line in reply["lines"]:
            yield {"event": "log", "seq": line["seq"], "line": line["line"]}
        while True:
            e = self.next_event()
            if e.get("event") == "log":
                yield e

    def wait(self, what, timeout_ms=None, match=None, since=None):
        fields = {"for": what}
        if timeout_ms:
            fields["timeout_ms"] = timeout_ms
        if match is not None:
            fields["match"] = match
        if since is not None:
            fields["since"] = since
        return self.request("wait", **fields)

    def game_events(self, names):
        """Subscribes to game events and yields them ({"event": "game", "name", "fields"})."""
        self.request("events", names=list(names))
        while True:
            e = self.next_event()
            if e.get("event") == "game":
                yield e

    def screenshot(self, overlay=True, max_width=None):
        fields = {}
        if not overlay:
            fields["overlay"] = False
        if max_width:
            fields["max_width"] = max_width
        return self.request("screenshot", **fields)

    def mod_key(self, key, action="press", hold_ms=None):
        fields = {"key": key, "action": action}
        if hold_ms:
            fields["hold_ms"] = hold_ms
        return self.request("mod_key", **fields)

    def quit(self):
        """Asks the game to save and close."""
        return self.request("quit")

    def load_world(self, slot, character, expect_name=None, timeout_ms=None):
        """From the main menu, starts LOCAL world slot `slot` with LOCAL character slot `character` (both 1-based)
        offline, without clicks; with expect_name, only when the character has that name. Returns the reply once the
        world runs and the local player is in it ({"slot", "character", "world", "character_name", "ms"}); raises
        LoadWorldError (plain words, .code) when nothing started. While it runs the game refuses any Steam Cloud
        character or world. timeout_ms: for the whole start (default 180000)."""
        fields = {"slot": int(slot), "character": int(character)}
        if expect_name:
            fields["expect_name"] = expect_name
        if timeout_ms:
            fields["timeout_ms"] = int(timeout_ms)
        reply = self.send("load_world", **fields)
        if not reply.get("ok"):
            raise LoadWorldError(reply)
        return reply


def _main(argv):
    p = argparse.ArgumentParser(description="EMF debug bridge client")
    p.add_argument("command", help="hello, console, state, mods, wait, log, events, shot, key, quit, load_world, raw")
    p.add_argument("args", nargs="*")
    p.add_argument("--game", help="the game folder (reads emf\\bridge.txt)")
    p.add_argument("--pid", type=int, help="the game's process id")
    p.add_argument("--timeout-ms", type=int)
    p.add_argument("--settle-ms", type=int)
    p.add_argument("--since", type=int)
    p.add_argument("--max", type=int)
    p.add_argument("--follow", action="store_true")
    p.add_argument("--down", action="store_true")
    p.add_argument("--up", action="store_true")
    p.add_argument("--hold-ms", type=int)
    p.add_argument("--no-overlay", action="store_true")
    p.add_argument("--max-width", type=int)
    p.add_argument("--json", action="store_true", help="print the game's reply as it came")
    a = p.parse_args(argv)

    def need(n, usage):
        if len(a.args) < n:
            raise SystemExit("usage: emf_bridge.py " + usage)

    try:
        with Bridge(game=a.game, pid=a.pid) as b:
            c = a.command
            if c == "events":
                names = [n for n in (a.args[0].split(",") if a.args else []) if n]
                for e in b.game_events(names):
                    print(json.dumps(e), flush=True)
                return 0
            if c == "log" and a.follow:
                for e in b.follow_log(a.since):
                    print("%7d  %s" % (e["seq"], e["line"]), flush=True)
                return 0
            if c == "hello":
                r = b.send("hello")
            elif c == "console":
                need(1, 'console "<command line>"')
                fields = {"text": a.args[0]}
                if a.timeout_ms:
                    fields["timeout_ms"] = a.timeout_ms
                if a.settle_ms is not None:
                    fields["settle_ms"] = a.settle_ms
                r = b.send("console", **fields)
            elif c == "state":
                r = b.send("state")
            elif c == "mods":
                r = b.send("mods")
            elif c == "wait":
                need(1, "wait world|player [seconds] | wait log <text> [seconds]")
                fields = {"for": a.args[0]}
                rest = a.args[1:]
                if a.args[0] == "log":
                    need(2, "wait log <text> [seconds]")
                    fields["match"], rest = a.args[1], a.args[2:]
                    if a.since is not None:
                        fields["since"] = a.since
                timeout = int(float(rest[0]) * 1000) if rest else a.timeout_ms
                if timeout:
                    fields["timeout_ms"] = timeout
                r = b.send("wait", **fields)
            elif c == "log":
                fields = {}
                if a.since is not None:
                    fields["since"] = a.since
                if a.max:
                    fields["max"] = a.max
                r = b.send("log", **fields)
            elif c in ("shot", "screenshot"):
                fields = {}
                if a.no_overlay:
                    fields["overlay"] = False
                if a.max_width:
                    fields["max_width"] = a.max_width
                r = b.send("screenshot", **fields)
            elif c in ("key", "mod_key"):
                need(1, "key <name> [--down | --up] [--hold-ms n]")
                fields = {"key": a.args[0], "action": "down" if a.down else "up" if a.up else "press"}
                if a.hold_ms:
                    fields["hold_ms"] = a.hold_ms
                r = b.send("mod_key", **fields)
            elif c == "quit":
                r = b.send("quit")
            elif c == "load_world":
                need(2, "load_world <LOCAL world slot> <LOCAL character slot> [<character name>] [--timeout-ms n]")
                try:
                    fields = {"slot": int(a.args[0]), "character": int(a.args[1])}
                except ValueError:
                    raise SystemExit("usage: emf_bridge.py load_world <LOCAL world slot> <LOCAL character slot> "
                                     "[<character name>]: the slots are numbers (1-based)")
                if len(a.args) > 2 and a.args[2]:
                    fields["expect_name"] = a.args[2]
                if a.timeout_ms:
                    fields["timeout_ms"] = a.timeout_ms
                r = b.send("load_world", **fields)
            elif c == "raw":
                need(1, "raw '<json request>'")
                try:
                    req = json.loads(a.args[0])
                except ValueError as e:  # Windows PowerShell 5.1 drops the inner quotes: pass '{\"cmd\":\"hello\"}'
                    print("not JSON (%s): %s" % (e, a.args[0]), file=sys.stderr)
                    return 2
                cmd = req.pop("cmd", "")
                req.pop("id", None)
                r = b.send(cmd, **req)
                print(b.last_line)
                return 0 if r.get("ok") else 1
            else:
                print("unknown command '%s' (hello, console, state, mods, wait, log, shot, key, quit, load_world, "
                      "raw)" % c, file=sys.stderr)
                return 2

            if a.json:
                print(b.last_line)
                return 0 if r.get("ok") else 1
            if c == "console":
                for line in r.get("output", []):
                    print(line)
                if r.get("truncated"):
                    print("(more output was cut; the log has all of it)")
            if not r.get("ok"):
                if c == "load_world":
                    print(load_world_message(r.get("code"), r.get("error")), file=sys.stderr)
                else:
                    print("%s: %s" % (r.get("code"), r.get("error")), file=sys.stderr)
                return 1
            if c == "hello":
                print("EMF %s (API %s), game build %s, %s, pid %s, bridge protocol %s"
                      % (r["emf"], r["api"], r["game_build"], r["process"], r["pid"], r["protocol"]))
            elif c == "console":
                if r.get("status") != "ran":
                    print("(the command did not run: %s)" % r.get("status"), file=sys.stderr)
                    return 1
            elif c == "state":
                r.pop("id", None)
                r.pop("ok", None)
                print(json.dumps(r, indent=2))
            elif c == "mods":
                for m in r["mods"]:
                    print("%-20s %-10s %-10s %s" % (m["id"], m["version"], m["status"], m["reason"]))
            elif c == "wait":
                print({"world": "a world is running", "player": "the local player exists"}.get(
                    a.args[0], "log line %s: %s" % (r.get("seq"), r.get("line"))))
            elif c == "log":
                if r.get("missed"):
                    print("(missed %d lines: the game keeps the last 5000)" % r["missed"])
                for line in r["lines"]:
                    print("%7d  %s" % (line["seq"], line["line"]))
                if r.get("more"):
                    print("(more lines: --since %d)" % r["last"])
            elif c in ("shot", "screenshot"):
                print("screenshot: %s (%dx%d%s)" % (r["path"], r["width"], r["height"],
                                                     ", HDR tone-mapped" if r.get("hdr") else ""))
            elif c in ("key", "mod_key"):
                key, action = r["key"], r["action"]
                print({"press": "pressed %s for mods; they read it %d times" % (key, r["mod_reads"]),
                       "down": "%s is held down for mods (key %s --up releases it; at most 60 s)" % (key, key),
                       "up": "released %s; mods read it %d times" % (key, r["mod_reads"])}[action])
            elif c == "quit":
                print("the game saves and closes")
            elif c == "load_world":
                print("'%s' runs with '%s' (LOCAL world slot %s, character %s, %s ms)" % (
                    r.get("world"), r.get("character_name"), r.get("slot"), r.get("character"), r.get("ms")))
    except BridgeError as e:
        print(str(e), file=sys.stderr)
        return 1
    except ConnectError as e:
        print(str(e), file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
