#!/usr/bin/env python3
"""EMF MCP server: the debug bridge (docs/modding/debug_bridge.md) as Model Context Protocol tools, so an AI coding
assistant in an MCP client can drive the running game: run console commands, read the state and the log,
wait for a world, take screenshots, press mods' keys and run test scenarios. docs/modding/ai_agents.md explains it.

Standard library only. It speaks JSON-RPC 2.0 over stdio, one message per line (the MCP stdio transport), and
implements initialize, ping, tools/list and tools/call itself.

    python -I tools/mcp/emf_mcp.py [--game <game folder>] [--pid <game pid>] [--session-file <path>]
                                   [--any-game] [--allow-cloud-world]

The game folder can also come from the environment variable EMF_GAME; without it the server finds the running game
(the way emf_bridge.py does). Every tool call opens its own connection to the game and closes it again, so the game
can be restarted between calls. Errors (no game, a command that did not run, a timeout) come back as tool results
with isError true and plain words, never as a crash.

Reading (hello, state, mods, log, wait, screenshot) works on any game with the bridge on. The tools that change the
game (emf_console, emf_mod_key, emf_run_scenario, emf_load_world) act only:
- on the game scripts\\game_session.ps1 started, as its session file records it (pid and start time; default
  %LOCALAPPDATA%\\EMF\\game_session\\session.json, or EMF_GAME_SESSION); --any-game lifts this for a game you started
  yourself;
- at the main menu or in a LOCAL save (the state's world slot); --allow-cloud-world lifts this.
emf_load_world also checks that the world it started is the LOCAL save it asked for, and ends another one of the
recorded game at once (without saving).
"""

import argparse
import base64
import json
import os
import queue
import sys
import threading
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_DEFAULT = os.path.dirname(os.path.dirname(HERE))  # tools/mcp/ -> the repository
for _p in (HERE, os.path.join(os.path.dirname(HERE), "bridge")):  # next to it (<game>\emf\tools\) or tools/bridge/
    if os.path.isfile(os.path.join(_p, "emf_bridge.py")) and _p not in sys.path:
        sys.path.insert(0, _p)

import emf_bridge  # noqa: E402
import emf_scenario  # noqa: E402
from emf_bridge import BridgeError, ConnectError  # noqa: E402

SERVER_VERSION = "1.1.0"
# newest first; not 2025-03-26, whose JSON-RPC batches this server does not take
PROTOCOL_VERSIONS = ["2025-06-18", "2024-11-05"]
DEFAULT_SHOT_WIDTH = 1280
MAX_SHOT_WIDTH = 1920                 # wider pictures cost a model more than they show
MAX_IMAGE_BYTES = int(3.7 * 1024 * 1024)  # the PNG as read (base64 makes it a third larger)


def default_session_file():
    """The session file scripts/game_session.ps1 writes (the same rule as there)."""
    return os.environ.get("EMF_GAME_SESSION") or os.path.join(
        os.environ.get("LOCALAPPDATA", os.path.expanduser("~")), "EMF", "game_session", "session.json")

INSTRUCTIONS = (
    "Tools for the running Enshrouded game with EMF's debug bridge on ([debug] bridge=1; scripts\\game_session.ps1 "
    "start sets it up). emf_hello first: it says whether the game answers. emf_load_world starts the LOCAL test world "
    "from the main menu without clicks. Console commands run exactly as typed in "
    "the in-game console (emf_console 'help' lists them). Rules: test only with a LOCAL test character and a LOCAL "
    "test world, never the Steam Cloud character or world; "
    "never send keyboard or mouse input to the game while a person uses the PC; these tools never do. Read AGENTS.md "
    "in the repository for the rest.")

# ---------------------------------------------------------------------------------------------------- the tools
S = lambda d: {"type": "string", "description": d}  # noqa: E731
I = lambda d, lo=None, hi=None: dict({"type": "integer", "description": d},  # noqa: E731, E741
                                     **({"minimum": lo} if lo is not None else {}),
                                     **({"maximum": hi} if hi is not None else {}))
N = lambda d, lo=None, hi=None: dict({"type": "number", "description": d},  # noqa: E731
                                     **({"minimum": lo} if lo is not None else {}),
                                     **({"maximum": hi} if hi is not None else {}))
B = lambda d: {"type": "boolean", "description": d}  # noqa: E731


def _schema(props=None, required=()):
    s = {"type": "object", "properties": props or {}, "additionalProperties": False}
    if required:
        s["required"] = list(required)
    return s


TOOLS = [
    {"name": "emf_hello", "title": "EMF: is the game there?",
     "description": "Asks the running game's debug bridge who it is: EMF's version, the API version, the game build, "
                    "client or dedicated server, the process id and the bridge commands. Use it first; an error "
                    "means the game is not running or the bridge is off.",
     "inputSchema": _schema(), "annotations": {"readOnlyHint": True}},
    {"name": "emf_console", "title": "EMF: run a console command",
     "description": "Runs one line in EMF's in-game console, exactly as if typed, and returns its status (ran, "
                    "unknown, refused, needs_world, too_old, crashed) and output lines. 'help' lists the commands, "
                    "'mods' the mods, 'pos' the player's position, 'near 10' what is around. Most commands need a "
                    "world you host; help, mods, settings, set, hooks and pattern also work at the main menu. Lines a "
                    "command prints later go to the log: pass the returned log_seq to emf_wait or emf_log. Commands "
                    "can change the world (give, spawn, destroy): it acts only on the game game_session.ps1 started and "
                    "only at the main menu or in a LOCAL save.",
     "inputSchema": _schema({"text": S("the command line, e.g. 'pos' or 'put Material_T1_Wood_Logs 5'"),
                             "timeout_s": N("give up after this many seconds (default 10)", 0.001, 120),
                             "settle_ms": I("wait this long for late output lines (default 300)", 0, 5000)},
                            ["text"]),
     "annotations": {"readOnlyHint": False, "destructiveHint": True}},
    {"name": "emf_state", "title": "EMF: the game's state",
     "description": "One snapshot of the game as JSON: world (status none/loading/running, kind, tick, time of day, "
                    "save slot), player (entity id, position x/y/z in metres, health), overlay (console open, HUD "
                    "lines), mods (id, version, status, reason), hooks, ticks, frame, log_seq. Unknown values are "
                    "null. Pass path to get one part, e.g. 'player.position', 'world.status', "
                    "'overlay.hud[id=clock.time].text', 'mods[id=lua].status'.",
     "inputSchema": _schema({"path": S("dotted path into the state; [n] picks a list element, [key=value] the "
                                       "element whose key has that value")}),
     "annotations": {"readOnlyHint": True}},
    {"name": "emf_mods", "title": "EMF: the mods",
     "description": "Every mod EMF found with its version and status (loaded, failed, disabled, not loaded, script, "
                    "loading) and, when it does not run, why. The same list as the console's Mods tab.",
     "inputSchema": _schema(), "annotations": {"readOnlyHint": True}},
    {"name": "emf_log", "title": "EMF: log lines",
     "description": "Lines from EMF's log (emf_core.log; the game keeps the last 5000 in memory, numbered from 1). "
                    "Without since: the newest lines. With since: the lines after that number (a console reply's "
                    "log_seq is a good start). contains keeps only lines with that text. The reply ends with the "
                    "last line number to pass as since next time.",
     "inputSchema": _schema({"since": I("only lines after this line number (0: from the oldest kept line)", 0),
                             "limit": I("at most this many lines (default 100)", 1, 5000),
                             "contains": S("only lines that contain this text (case matters)")}),
     "annotations": {"readOnlyHint": True}},
    {"name": "emf_wait", "title": "EMF: wait for something",
     "description": "Waits until a world runs ('world'), the local player exists ('player'), or a log line contains "
                    "match ('log'), or the time runs out (an error). For 'log', only lines after the call count "
                    "unless since is given. Loading a world from the main menu takes 30-120 s.",
     "inputSchema": _schema({"for": {"type": "string", "enum": ["world", "player", "log"],
                                     "description": "what to wait for"},
                             "match": S("for 'log': the text the line must contain (case matters)"),
                             "since": I("for 'log': also lines after this line number", 0),
                             "timeout_s": N("give up after this many seconds (default 60)", 0.001, 600)},
                            ["for"]),
     "annotations": {"readOnlyHint": True}},
    {"name": "emf_screenshot", "title": "EMF: screenshot",
     "description": "The next frame the game shows, as a PNG image (it works while the window is behind others and "
                    "at the main menu; HDR is tone-mapped). The file is also kept in the game's emf\\screens folder. "
                    "overlay false leaves out EMF's overlay (console, HUD lines).",
     "inputSchema": _schema({"max_width": I("scale down to this width in pixels (default %d, at most %d)" % (
                                                DEFAULT_SHOT_WIDTH, MAX_SHOT_WIDTH), 16, MAX_SHOT_WIDTH),
                             "overlay": B("false: the frame before EMF's overlay draws on it")}),
     "annotations": {"readOnlyHint": True}},
    {"name": "emf_mod_key", "title": "EMF: press a key for mods",
     "description": "Presses a key for mods only (keys mods read with emf::keys, GetAsyncKeyState or Lua "
                    "emf.on_key), without window focus. The game itself, the console and wheels do not see it, so "
                    "it is no input to the game. The reply says how often mods read the key (0: no mod looks at it).",
     "inputSchema": _schema({"key": S("a letter, a digit, F1-F24, a name like Space or PageUp, or 0x4C"),
                             "action": {"type": "string", "enum": ["press", "down", "up"],
                                        "description": "press (default), or hold down / release"},
                             "hold_ms": I("press only: how long it is held (default 150)", 20, 5000)},
                            ["key"]),
     "annotations": {"readOnlyHint": False}},
    {"name": "emf_run_scenario", "title": "EMF: run a test scenario",
     "description": "Runs a JSON test scenario (tools/bridge/emf_scenario.py: wait, console with expected output, "
                    "state checks, mods, mod_key, screenshot, edit_file, log marks) and returns a pass/fail line per "
                    "step. path: a .json file under the repository's tests/game/ (or just its name, e.g. 'smoke') or "
                    "under the game's emf\\ folder. Files a scenario edits are put back at the end.",
     "inputSchema": _schema({"path": S("tests/game/<name>.json, a bare name like 'smoke', or a file in the game's "
                                       "emf folder"),
                             "keep_going": B("run the remaining steps after a failure")},
                            ["path"]),
     "annotations": {"readOnlyHint": False}},
    {"name": "emf_load_world", "title": "EMF: start a LOCAL world",
     "description": "From the main menu, starts a LOCAL save offline without clicks (the bridge's load_world) and "
                    "answers once the world runs and the local player is in it (about 10-60 s). While it runs, the "
                    "game refuses any Steam Cloud character or world. Defaults: LOCAL world slot 1 with LOCAL "
                    "character slot 1, which must be named 'Character 2' (the test character; expect_name '' accepts "
                    "any name). When the world it asked for runs already, it starts nothing and says so. It acts only "
                    "on the game game_session.ps1 started, and checks afterwards that the running world is the LOCAL "
                    "save it asked for; another one is ended at once, without saving.",
     "inputSchema": _schema({"slot": I("LOCAL world slot (default 1)", 1, 10),
                             "character": I("LOCAL character slot (default 1)", 1, 16),
                             "expect_name": S("the character's name (default 'Character 2'; '' = any name)"),
                             "timeout_s": N("give up after this many seconds, menu to world (default 180)", 1, 600)}),
     "annotations": {"readOnlyHint": False, "destructiveHint": True}},
]


def check_args(schema, args):
    """A plain-words error for arguments that do not fit the tool's schema, or None."""
    if not isinstance(args, dict):
        return "arguments must be an object"
    props = schema.get("properties", {})
    for k in schema.get("required", []):
        if k not in args:
            return "missing argument '%s' (%s)" % (k, props[k]["description"])
    for k, v in args.items():
        if k not in props:
            return "unknown argument '%s' (this tool takes: %s)" % (k, ", ".join(props) or "nothing")
        p = props[k]
        t = p["type"]
        ok = {"string": isinstance(v, str), "boolean": isinstance(v, bool),
              "integer": isinstance(v, int) and not isinstance(v, bool),
              "number": isinstance(v, (int, float)) and not isinstance(v, bool)}[t]
        if not ok:
            return "argument '%s' must be %s" % (k, {"string": "text", "boolean": "true or false",
                                                     "integer": "a whole number", "number": "a number"}[t])
        if "enum" in p and v not in p["enum"]:
            return "argument '%s' must be one of: %s" % (k, ", ".join(p["enum"]))
        if "minimum" in p and v < p["minimum"]:
            return "argument '%s' must be at least %s" % (k, p["minimum"])
        if "maximum" in p and v > p["maximum"]:
            return "argument '%s' must be at most %s" % (k, p["maximum"])
    return None


def _text(t):
    return {"type": "text", "text": t}


class ToolError(Exception):
    """A tool call that failed in a way the caller should read (plain words)."""


def _inside(path, root):
    path, root = os.path.normcase(path), os.path.normcase(root)
    try:
        return os.path.commonpath([path, root]) == root
    except ValueError:
        return False


def end_process(pid):
    """Ends a process at once (it saves nothing). True when Windows ended it."""
    import ctypes
    from ctypes import wintypes
    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    k32.OpenProcess.restype = wintypes.HANDLE
    k32.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
    k32.TerminateProcess.restype = wintypes.BOOL
    k32.CloseHandle.argtypes = [wintypes.HANDLE]
    h = k32.OpenProcess(0x0001, False, int(pid))  # PROCESS_TERMINATE
    if not h:
        return False
    try:
        return bool(k32.TerminateProcess(h, 1))
    finally:
        k32.CloseHandle(h)


class Server:
    def __init__(self, bridge_factory=None, game=None, pid=None, repo=None, session_file=None, any_game=False,
                 allow_cloud_world=False, process_start=None, kill_game=None):
        self.factory = bridge_factory or (lambda game, pid: emf_bridge.Bridge(game=game, pid=pid))
        self.game = game
        self.pid = pid
        self.repo = repo or REPO_DEFAULT
        self.session_file = session_file or default_session_file()
        self.any_game = any_game
        self.allow_cloud_world = allow_cloud_world
        self.process_start = process_start or emf_bridge.process_start_epoch
        self.kill_game = kill_game or end_process  # emf_load_world ends a wrong world of the recorded game with it
        self.tools = {t["name"]: t for t in TOOLS}
        self.cancelled = set()  # request ids the client cancelled (notifications/cancelled)
        self._out_lock = threading.Lock()

    # ---- which game may be changed ----
    def _session(self):
        """The game game_session.ps1 recorded ({game_pid, game_start_epoch, game, ...}), or None."""
        try:
            with open(self.session_file, encoding="utf-8-sig") as f:
                data = json.load(f)
            return data if isinstance(data, dict) else None
        except (OSError, ValueError):
            return None

    def _check_may_change(self, b):
        """Raises ToolError unless this game may be changed: the one game_session.ps1 recorded (its pid, and its start
        time, so a reused pid does not count; --any-game skips this), at the main menu or in a LOCAL save
        (--allow-cloud-world skips that)."""
        if not self.any_game:
            s = self._session()
            if not s or not s.get("game_pid"):
                raise ToolError(
                    "this tool changes the game, and acts only on the game scripts\\game_session.ps1 started; no such "
                    "game is recorded (%s). Start one with game_session.ps1 start, or run the server with --any-game "
                    "for a game you started yourself." % self.session_file)
            pid = b.request("hello").get("pid")
            if pid != s.get("game_pid"):
                raise ToolError("the running game (pid %s) is not the one game_session.ps1 started (pid %s): someone "
                                "else's game is not changed (--any-game overrides)" % (pid, s.get("game_pid")))
            started, recorded = self.process_start(pid), s.get("game_start_epoch")
            if started is None or not isinstance(recorded, (int, float)) or abs(started - recorded) > 2:
                raise ToolError("the running game (pid %s) started at another time than the game game_session.ps1 "
                                "recorded (the pid was reused): not changing it (--any-game overrides)" % pid)
        if not self.allow_cloud_world:
            why = emf_scenario.world_change_refusal(b.request("state"))
            if why:
                raise ToolError(why)

    def _scenario_games(self):
        """Game folders whose emf\\ may hold scenarios: --game (or EMF_GAME), else the recorded session's game."""
        if self.game:
            return [self.game]
        s = self._session()
        return [s["game"]] if s and isinstance(s.get("game"), str) and s["game"] else []

    # ---- JSON-RPC ----
    @staticmethod
    def _error(rid, code, message):
        return {"jsonrpc": "2.0", "id": rid, "error": {"code": code, "message": message}}

    @staticmethod
    def _result(rid, result):
        return {"jsonrpc": "2.0", "id": rid, "result": result}

    def handle(self, msg):
        """The reply to one message (a dict), or None for a notification."""
        if isinstance(msg, list):
            return self._error(None, -32600, "batches are not supported: send one message per line")
        if not isinstance(msg, dict) or msg.get("jsonrpc") != "2.0":
            return self._error(msg.get("id") if isinstance(msg, dict) else None, -32600, "not a JSON-RPC 2.0 message")
        method = msg.get("method")
        if not isinstance(method, str):
            if "id" in msg and ("result" in msg or "error" in msg):
                return None  # a reply to a request of ours: this server sends none
            return self._error(msg.get("id"), -32600, "a request needs a method")
        if "id" not in msg:
            return None  # notifications (initialized, cancelled, ...) need no answer
        rid = msg["id"]
        params = msg.get("params", {})
        if params is None:
            params = {}
        if not isinstance(params, dict):
            return self._error(rid, -32602, "params must be an object")
        try:
            if method == "initialize":
                asked = params.get("protocolVersion")
                return self._result(rid, {
                    "protocolVersion": asked if asked in PROTOCOL_VERSIONS else PROTOCOL_VERSIONS[0],
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {"name": "emf", "title": "EMF debug bridge", "version": SERVER_VERSION},
                    "instructions": INSTRUCTIONS})
            if method == "ping":
                return self._result(rid, {})
            if method == "tools/list":
                return self._result(rid, {"tools": [{k: v for k, v in t.items()} for t in TOOLS]})
            if method == "tools/call":
                name = params.get("name")
                if name not in self.tools:
                    return self._error(rid, -32602, "unknown tool: %s (tools: %s)" % (name, ", ".join(self.tools)))
                return self._result(rid, self.call_tool(name, params.get("arguments") or {}))
            return self._error(rid, -32601, "method not found: %s" % method)
        except Exception as e:  # never die on a request
            traceback.print_exc(file=sys.stderr)
            return self._error(rid, -32603, "internal error: %s" % e)

    def serve(self, stdin=None, stdout=None):
        """Reads one JSON-RPC message per line from stdin until it closes; writes replies one per line. Requests run
        one at a time on a worker thread, so this thread keeps reading: a notifications/cancelled for the request
        that runs means its reply is not sent (the call itself cannot be stopped; the bridge client's own time
        limit ends a stuck one)."""
        stdin = stdin or sys.stdin.buffer
        stdout = stdout or sys.stdout.buffer
        work = queue.Queue()

        def write(reply):
            with self._out_lock:
                # ASCII with \u escapes: a lone surrogate from the game's text cannot fail the encoding
                stdout.write((json.dumps(reply) + "\n").encode("ascii"))
                stdout.flush()

        def worker():
            while True:
                item = work.get()
                if item is None:
                    return
                kind, payload = item
                reply = payload if kind == "reply" else self.handle(payload)
                if reply is None:
                    continue
                rid = reply.get("id")
                if isinstance(rid, (int, str)) and rid in self.cancelled:
                    continue  # the client cancelled it: no reply
                write(reply)

        t = threading.Thread(target=worker, daemon=True)
        t.start()
        for raw in stdin:
            line = raw.decode("utf-8", errors="replace").strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except ValueError as e:
                work.put(("reply", self._error(None, -32700, "parse error: %s" % e)))
                continue
            if isinstance(msg, dict) and msg.get("method") == "notifications/cancelled" and "id" not in msg:
                rid = msg.get("params", {}).get("requestId") if isinstance(msg.get("params"), dict) else None
                if isinstance(rid, (int, str)):
                    self.cancelled.add(rid)
                continue
            work.put(("msg", msg))
        work.put(None)
        t.join()

    # ---- tools ----
    def call_tool(self, name, args):
        err = check_args(self.tools[name]["inputSchema"], args)
        if err:
            return {"content": [_text("invalid arguments: " + err)], "isError": True}
        try:
            content = getattr(self, "_tool_" + name)(args)
            return {"content": content, "isError": False}
        except ToolError as e:
            return {"content": [_text(str(e))], "isError": True}
        except ConnectError as e:
            return {"content": [_text(
                "no connection to the game: %s. Start it with scripts\\game_session.ps1 start (it installs EMF with "
                "the debug bridge on), or check scripts\\game_session.ps1 status." % e)], "isError": True}
        except BridgeError as e:
            return {"content": [_text("the game said no: %s: %s" % (e.code or "error", e.reply.get("error", "")))],
                    "isError": True}
        except Exception as e:
            traceback.print_exc(file=sys.stderr)
            return {"content": [_text("internal error in %s: %s: %s" % (name, e.__class__.__name__, e))],
                    "isError": True}

    def _request(self, cmd, changes=False, **fields):
        """One request on its own connection. changes=True: a command that changes the game, after
        _check_may_change on the same connection."""
        b = self.factory(self.game, self.pid)
        try:
            if changes:
                self._check_may_change(b)
            return b.request(cmd, **fields)
        finally:
            b.close()

    def _tool_emf_hello(self, a):
        r = self._request("hello")
        return [_text("EMF %s (API %s), game build %s, %s, pid %s, bridge protocol %s\ncommands: %s" % (
            r.get("emf"), r.get("api"), r.get("game_build"), r.get("process"), r.get("pid"), r.get("protocol"),
            ", ".join(r.get("commands", []))))]

    def _tool_emf_console(self, a):
        fields = {"text": a["text"]}
        if "timeout_s" in a:
            fields["timeout_ms"] = max(1, int(round(a["timeout_s"] * 1000)))
        if "settle_ms" in a:
            fields["settle_ms"] = a["settle_ms"]
        try:
            r = self._request("console", changes=True, **fields)
        except BridgeError as e:
            if e.code == "timeout":
                raise ToolError("timed out after %s s; output so far:\n%s" % (
                    a.get("timeout_s", 10), "\n".join(e.reply.get("output", [])) or "(none)"))
            raise
        out = r.get("output", [])
        text = "status: %s, log_seq: %s%s\n%s" % (r.get("status"), r.get("log_seq"),
                                                  " (output cut: the log has all of it)" if r.get("truncated") else "",
                                                  "\n".join(out) if out else "(no output)")
        if r.get("status") != "ran":
            raise ToolError(text)
        return [_text(text)]

    def _tool_emf_state(self, a):
        if "path" in a:
            try:
                emf_scenario.parse_path(a["path"])
            except ValueError as e:
                raise ToolError("bad path: %s" % e)
        state = self._request("state")
        state.pop("id", None)
        state.pop("ok", None)
        if "path" not in a:
            return [_text(json.dumps(state, ensure_ascii=False))]
        found, value, why = emf_scenario.resolve(state, a["path"])
        if not found:
            raise ToolError(why)
        return [_text(json.dumps(value, ensure_ascii=False))]

    def _tool_emf_mods(self, a):
        mods = self._request("mods").get("mods", [])
        lines = ["%-22s %-10s %-11s %s" % (m.get("id"), m.get("version"), m.get("status"), m.get("reason", ""))
                 for m in mods]
        return [_text("\n".join(lines) if lines else "(no mods)")]

    def _tool_emf_log(self, a):
        limit = a.get("limit", 100)
        b = self.factory(self.game, self.pid)
        try:
            if "contains" not in a:
                fields = {"max": limit}
                if "since" in a:
                    fields["since"] = a["since"]
                r = b.request("log", **fields)
                lines = [(x["seq"], x["line"]) for x in r.get("lines", [])]
                last, more, missed = r.get("last", 0), r.get("more", False), r.get("missed", 0)
            else:
                lines, missed, more = [], 0, False
                fields = {"max": 5000}
                if "since" in a:
                    fields["since"] = a["since"]
                for page in range(50):
                    r = b.request("log", **fields)
                    if page == 0:
                        missed = r.get("missed", 0)
                    lines += [(x["seq"], x["line"]) for x in r.get("lines", []) if a["contains"] in x["line"]]
                    last = r.get("last", 0)
                    if len(lines) >= limit:
                        lines, more = lines[:limit], True
                        last = lines[-1][0]
                        break
                    if not r.get("more"):
                        break
                    fields = {"max": 5000, "since": last}
        finally:
            b.close()
        out = ["%7d  %s" % (s, l) for s, l in lines] or ["(no lines)"]
        if missed:
            out.insert(0, "(%d lines after since are gone already: the game keeps the last 5000)" % missed)
        out.append("(last line number: %d%s)" % (last, "; more lines: call again with since=%d" % last if more else ""))
        return [_text("\n".join(out))]

    def _tool_emf_wait(self, a):
        what = a["for"]
        if what == "log" and not a.get("match"):
            raise ToolError("waiting for 'log' needs match: the text to look for")
        if what != "log" and ("match" in a or "since" in a):
            raise ToolError("match and since are for waiting for 'log'")
        timeout = a.get("timeout_s", 60)
        fields = {"for": what, "timeout_ms": max(1, int(round(timeout * 1000)))}
        if "match" in a:
            fields["match"] = a["match"]
        if "since" in a:
            fields["since"] = a["since"]
        try:
            r = self._request("wait", **fields)
        except BridgeError as e:
            if e.code == "timeout":
                raise ToolError("timed out after %g s: %s" % (timeout, {
                    "world": "no world runs (is the game at the main menu?)",
                    "player": "no local player",
                    "log": "no new log line contains %r" % a.get("match")}[what]))
            raise
        if what == "log":
            return [_text("line %s: %s" % (r.get("seq"), r.get("line")))]
        return [_text({"world": "a world is running", "player": "the local player exists"}[what])]

    def _tool_emf_screenshot(self, a):
        fields = {"max_width": a.get("max_width", DEFAULT_SHOT_WIDTH)}
        if "overlay" in a:
            fields["overlay"] = a["overlay"]
        r = self._request("screenshot", **fields)
        path = r.get("path", "")
        about = "%sx%s%s, saved as %s" % (r.get("width"), r.get("height"), ", HDR tone-mapped" if r.get("hdr") else "",
                                          path)
        try:
            size = os.path.getsize(path)
            if size > MAX_IMAGE_BYTES:
                raise ToolError("the PNG is %.1f MB, too big to send (at most %.1f MB): %s; ask with a smaller "
                                "max_width" % (size / 1048576.0, MAX_IMAGE_BYTES / 1048576.0, about))
            with open(path, "rb") as f:
                data = f.read()
        except OSError as e:
            raise ToolError("the game wrote %s, but it cannot be read: %s" % (path, e.strerror or e))
        return [{"type": "image", "data": base64.b64encode(data).decode("ascii"), "mimeType": "image/png"},
                _text("screenshot " + about)]

    def _tool_emf_mod_key(self, a):
        fields = {"key": a["key"]}
        for k in ("action", "hold_ms"):
            if k in a:
                fields[k] = a[k]
        r = self._request("mod_key", changes=True, **fields)
        reads = r.get("mod_reads", 0)
        action = r.get("action", a.get("action", "press"))
        return [_text({"press": "pressed %s for mods; they read it %d times%s" % (
                           r.get("key"), reads, " (no mod looks at that key)" if not reads else ""),
                       "down": "%s is held down for mods (action up releases it; at most 60 s)" % r.get("key"),
                       "up": "released %s; mods read it %d times" % (r.get("key"), reads)}.get(action, action))]

    def _scenario_path(self, path):
        """A scenario file under the repository's tests\\game\\ or the emf\\ folder of the game named with --game or
        recorded by game_session.ps1 (not of any process that happens to run: a stand-in could live anywhere)."""
        roots = [os.path.realpath(os.path.join(self.repo, "tests", "game"))]
        games = self._scenario_games()
        roots += [os.path.realpath(os.path.join(g, "emf")) for g in games]
        candidates = []
        if os.path.isabs(path):
            candidates.append(path)
        else:
            if not any(c in path for c in "/\\") and not path.lower().endswith(".json"):
                candidates.append(os.path.join(self.repo, "tests", "game", path + ".json"))
            candidates.append(os.path.join(self.repo, path))
            candidates += [os.path.join(g, path) for g in games]
        for c in candidates:
            full = os.path.realpath(c)
            if full.lower().endswith(".json") and os.path.isfile(full) and any(_inside(full, r) for r in roots):
                return full
        raise ToolError("no scenario %s: it must be a .json file under %s or the game's emf\\ folder" % (
            path, roots[0]))

    def _tool_emf_run_scenario(self, a):
        full = self._scenario_path(a["path"])
        try:
            scenario = emf_scenario.load_scenario(full)
        except emf_scenario.ScenarioError as e:
            raise ToolError("the scenario is not valid: %s" % e)
        lines = []
        b = self.factory(self.game, self.pid)
        try:
            self._check_may_change(b)
            game = self.game or emf_scenario.game_from_bridge(b)
            report = emf_scenario.run_scenario(scenario, b, game=game, echo=lines.append,
                                               keep_going=a.get("keep_going", False),
                                               allow_cloud_world=self.allow_cloud_world)
        finally:
            b.close()
        text = "\n".join(lines)
        if not report["ok"]:
            raise ToolError(text)
        return [_text(text)]

    def _end_recorded_game(self):
        """Ends the game game_session.ps1 recorded, at once and without saving, when it is still that very process
        (its pid and start time). True when it was ended."""
        s = self._session() or {}
        pid, recorded = s.get("game_pid"), s.get("game_start_epoch")
        started = self.process_start(pid) if isinstance(pid, int) else None
        if started is None or not isinstance(recorded, (int, float)) or abs(started - recorded) > 2:
            return False
        return self.kill_game(pid) is not False

    def _tool_emf_load_world(self, a):
        slot = a.get("slot", emf_scenario.LOAD_WORLD_DEFAULTS["slot"])
        character = a.get("character", emf_scenario.LOAD_WORLD_DEFAULTS["character"])
        name = a.get("expect_name", emf_scenario.LOAD_WORLD_DEFAULTS["expect_name"])
        fields = {"slot": slot, "character": character,
                  "timeout_ms": int(round(a.get("timeout_s", emf_scenario.LOAD_WORLD_TIMEOUT_S) * 1000))}
        if name:
            fields["expect_name"] = name
        b = self.factory(self.game, self.pid)
        try:
            self._check_may_change(b)
            state = b.request("state")
            world = state.get("world") or {}
            if world.get("status") not in (None, "none"):
                if world.get("status") == "running" and world.get("kind") == "server" and world.get("slot") == slot:
                    why = emf_scenario.character_refusal(state, name or None)  # never a Steam character's world
                    if why:
                        raise ToolError(why)
                    return [_text("LOCAL world slot %d%s runs already with %s: nothing started" % (
                        slot, " '%s'" % world["name"] if world.get("name") else "",
                        emf_scenario.character_text(state["character"])))]
                raise ToolError("a world is %s already (%s): emf_load_world starts a world from the main menu only" % (
                    world.get("status"), emf_scenario.world_text(world)))
            try:
                r = b.request("load_world", **fields)
            except BridgeError as e:
                raise ToolError(emf_bridge.load_world_message(e.code, e.reply.get("error", "")))
            problem = emf_scenario.loaded_world_problem(r, b.request("state"), slot, character, name or None)
        finally:
            b.close()
        if problem:
            why, end_game = problem
            if not end_game:
                raise ToolError("the world started, but %s. Nothing was ended." % why)
            if not self.any_game and self._end_recorded_game():
                raise ToolError("WRONG WORLD: %s. The game was ended at once, without saving. Run "
                                "scripts\\game_session.ps1 stop -LockOwner <you> to remove EMF and check the saves, and "
                                "tell the user." % why)
            raise ToolError("WRONG WORLD: %s. Close the game at once without saving (end its process), then check the "
                            "saves." % why)
        return [_text("'%s' runs with '%s' (LOCAL world slot %d, character %d, %.1f s in the game)" % (
            r.get("world"), r.get("character_name"), slot, character, (r.get("ms") or 0) / 1000.0))]


def main(argv=None):
    p = argparse.ArgumentParser(description="EMF MCP server (stdio)")
    p.add_argument("--game", default=os.environ.get("EMF_GAME") or None, help="the game folder (or EMF_GAME)")
    p.add_argument("--pid", type=int, help="the game's process id")
    p.add_argument("--repo", help="the EMF repository (default: two folders up from this file)")
    p.add_argument("--session-file", help="game_session.ps1's session file (default: EMF_GAME_SESSION or "
                                          "%%LOCALAPPDATA%%\\EMF\\game_session\\session.json)")
    p.add_argument("--any-game", action="store_true", help="let the tools that change the game act on a game "
                                                           "game_session.ps1 did not start (one you started yourself)")
    p.add_argument("--allow-cloud-world", action="store_true", help="let them act in a world that is not a LOCAL "
                                                                    "save (never on a PC someone plays on)")
    a = p.parse_args(argv)
    Server(game=a.game, pid=a.pid, repo=a.repo, session_file=a.session_file, any_game=a.any_game,
           allow_cloud_world=a.allow_cloud_world).serve()
    return 0


if __name__ == "__main__":
    sys.exit(main())
