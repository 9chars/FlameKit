#!/usr/bin/env python3
"""EMF scenario runner: runs a JSON test scenario against the running game through the debug bridge
(docs/modding/debug_bridge.md, docs/modding/ai_agents.md). Standard library only, one file next to emf_bridge.py.

    python emf_scenario.py tests/game/smoke.json [--game <folder>] [--out <folder>] [--json report.json|-]
    python emf_scenario.py --check tests/game/*.json        (checks the files only; no game needed)
    python emf_scenario.py --steps                          (lists the step kinds)
    python emf_scenario.py --recover [--out <run folder>]   (puts back what a run that was cut off left changed)

A scenario:

    {"name": "smoke", "description": "...", "steps": [
      {"do": "hello"},
      {"do": "wait", "for": "world", "timeout_s": 300},
      {"do": "state", "path": "player.position", "op": "exists"},
      {"do": "console", "text": "pos", "expect_re": "player \\\\d+ at"},
      {"do": "mods", "id": "clock", "status": "loaded"}]}

Each step prints "ok" or "FAIL" with the reason; the first failure skips the rest (--keep-going runs them anyway).
Files that edit_file changed are put back at the end, also after a failure or Ctrl+C; a journal in the output folder
lets the next run (or --recover) put them back after a run that was killed. It never sends input to the game window
and never touches saves: everything goes through the bridge, and edit_file only writes inside the game's
emf\\mods\\<id>\\ folders. console, mod_key and edit_file steps run only at the main menu or in a LOCAL save
(--allow-cloud-world lifts that; never on a PC someone plays on). A load_world step starts a LOCAL save from the main menu
through the bridge (no clicks; the game refuses Steam Cloud saves meanwhile) and checks in the state that the LOCAL
slot it asked for runs; the scenario's own "load_world": {"slot", "character", "expect_name"} sets its defaults
(else 1, 1, "Character 2").

Exit codes: 0 every step passed, 1 a step failed (or a file could not be put back), 2 no connection to the game,
3 the scenario file is not valid (or a wrong command line).
"""

import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import time
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)  # emf_bridge.py sits next to this file (also in <game>\emf\tools\)

import emf_bridge  # noqa: E402
from emf_bridge import BridgeError, ConnectError  # noqa: E402

NUM = (int, float)
ANY = object()
OPS = ("exists", "missing", "==", "!=", "<", ">", "<=", ">=", "contains", "matches")
CONSOLE_STATUSES = ("ran", "unknown", "refused", "needs_world", "too_old", "crashed")
POLL_S = 0.25

# kind -> (what it does, {field: (types, required, what it is)}). Every step also takes "do" and an optional "label".
STEPS = {
    "hello": ("the game answers: EMF, API and game build", {
        "expect": (dict, False, "fields of the hello reply that must have these values, e.g. {\"process\": \"client\"}"),
    }),
    "wait": ("wait for a world, the local player, or a log line", {
        "for": (str, True, "world | player | log"),
        "match": (str, False, "for log: the text a new line must contain (case matters)"),
        "since": (int, False, "for log: also lines after this line number (0 = every kept line)"),
        "timeout_s": (NUM, False, "seconds (default 30, at most 600)"),
    }),
    "console": ("run a console command and check its output", {
        "text": (str, True, "the command line, exactly as typed"),
        "expect": ((str, list), False, "text (or a list of texts) the output must contain"),
        "expect_re": (str, False, "a regular expression the output must match (Python re, multiline)"),
        "status": (str, False, "the status it must end with (default ran): " + ", ".join(CONSOLE_STATUSES)),
        "timeout_s": (NUM, False, "seconds (default 10, at most 120)"),
        "settle_ms": (int, False, "wait this long for late lines (default 300, 0-5000)"),
    }),
    "state": ("check a value in the game's state", {
        "path": (str, True, "dotted path: player.position.x, overlay.hud[id=clock.time].text, mods[0].id"),
        "op": (str, True, " | ".join(OPS)),
        "value": (ANY, False, "what to compare with (not for exists / missing)"),
        "timeout_s": (NUM, False, "keep asking until it holds, up to this many seconds (default 0: once)"),
    }),
    "mods": ("a mod is listed (and has a status)", {
        "id": (str, True, "the mod's id"),
        "status": (str, False, "loaded, failed, disabled, not loaded, script, loading"),
    }),
    "mod_key": ("press a key for mods (not the game)", {
        "key": (str, True, "a letter, digit, F1-F24, a name like Space, or 0x4C"),
        "action": (str, False, "press (default), down or up"),
        "hold_ms": (int, False, "press only: 20-5000 (default 150)"),
        "min_reads": (int, False, "mods must read the key at least this often (1: some mod looks at it)"),
    }),
    "screenshot": ("take a screenshot and copy it into the output folder", {
        "name": (str, False, "file name (default shot); saved as <step>_<name>.png"),
        "overlay": (bool, False, "false: the frame without EMF's overlay"),
        "max_width": (int, False, "scale down to this width (16-16384)"),
    }),
    "sleep": ("wait a fixed time", {
        "s": (NUM, True, "seconds (0-600)"),
    }),
    "edit_file": ("change a mod's file (put back at the end)", {
        "path": (str, True, "relative to the game folder, inside emf/mods/<id>/, e.g. emf/mods/my_first_mod/main.lua"),
        "find": (str, False, "text to replace (must be there exactly once unless all is true)"),
        "replace": (str, False, "the new text for find"),
        "all": (bool, False, "replace every occurrence of find"),
        "write": (str, False, "the whole new content instead of find/replace (a new file is deleted at the end)"),
    }),
    "restore_file": ("put an edited file back now", {
        "path": (str, True, "the path given to edit_file"),
    }),
    "log_mark": ("remember the newest log line", {
        "name": (str, True, "the mark's name"),
    }),
    "log_since_mark": ("check the log lines after a mark", {
        "mark": (str, True, "a log_mark's name"),
        "match": (str, False, "text a line must contain"),
        "match_re": (str, False, "a regular expression a line must match"),
        "absent": (bool, False, "true: no line may match (after timeout_s, if given)"),
        "timeout_s": (NUM, False, "wait up to this long for the line (default 0: check once)"),
    }),
    "load_world": ("start a LOCAL save from the main menu, without clicks (passes at once when it runs already)", {
        "slot": (int, False, "LOCAL world slot 1-10 (default: the scenario's load_world.slot, else 1)"),
        "character": (int, False, "LOCAL character slot 1-16 (default: the scenario's load_world.character, else 1)"),
        "expect_name": (str, False, "the character's name (default: the scenario's load_world.expect_name, else "
                                    "\"Character 2\"; \"\" = any name)"),
        "timeout_s": (NUM, False, "seconds for the whole start, menu to world (default 180, at most 600)"),
    }),
}

# The load_world step's defaults when neither the step nor the scenario's "load_world" object names them: LOCAL world
# slot 1 with LOCAL character slot 1, named "Character 2" (a scenario names another test character with
# expect_name).
LOAD_WORLD_DEFAULTS = {"slot": 1, "character": 1, "expect_name": "Character 2"}
LOAD_WORLD_TIMEOUT_S = 180
_LOAD_WORLD_RANGES = {"slot": (1, 10), "character": (1, 16)}


class ScenarioError(Exception):
    """The scenario file is not valid."""


# ---------------------------------------------------------------------------------------------------- paths
def parse_path(path):
    """'overlay.hud[id=clock.time].text' -> ['overlay', 'hud', ('sel', 'id', 'clock.time'), 'text']; [n] -> ('idx', n).
    Raises ValueError for a malformed path."""
    if not isinstance(path, str) or not path:
        raise ValueError("an empty path")
    tokens = []
    i, n = 0, len(path)
    need_name = True  # at the start and after a dot a name must come
    while i < n:
        c = path[i]
        if c == "[":
            if need_name:
                raise ValueError("'[' must follow a name: %s" % path)
            j = path.find("]", i)
            if j < 0:
                raise ValueError("'[' without ']': %s" % path)
            inner = path[i + 1:j]
            if re.fullmatch(r"-?\d+", inner):
                tokens.append(("idx", int(inner)))
            elif "=" in inner and inner.split("=", 1)[0]:
                key, value = inner.split("=", 1)
                tokens.append(("sel", key, value))
            else:
                raise ValueError("[%s] in %s: use [n] or [key=value]" % (inner, path))
            i = j + 1
            if i < n and path[i] not in ".[":
                raise ValueError("'.' or '[' must follow ']': %s" % path)
        elif c == ".":
            if need_name:
                raise ValueError("an empty name in %s" % path)
            need_name = True
            i += 1
        elif c == "]":
            raise ValueError("']' without '[': %s" % path)
        else:
            name = re.match(r"[^.\[\]]+", path[i:]).group(0)
            tokens.append(name)
            i += len(name)
            need_name = False
    if need_name:
        raise ValueError("the path ends with a dot: %s" % path)
    return tokens


def _sel_text(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v)


def _short(v, limit=120):
    text = json.dumps(v, ensure_ascii=False) if not isinstance(v, str) else repr(v)
    return text if len(text) <= limit else text[:limit - 3] + "..."


def resolve(data, path):
    """(found, value, why not) for a dotted path into a JSON reply."""
    cur = data
    where = ""
    for seg in parse_path(path):
        label = where or "the state"
        if isinstance(seg, str):
            if cur is None:
                return False, None, "%s is null" % label
            if not isinstance(cur, dict):
                return False, None, "%s is not an object (it is %s)" % (label, _short(cur, 60))
            if seg not in cur:
                return False, None, "%s has no '%s' (it has: %s)" % (label, seg, ", ".join(list(cur)[:12]))
            cur = cur[seg]
            where = where + "." + seg if where else seg
        elif seg[0] == "idx":
            if not isinstance(cur, list):
                return False, None, "%s is not a list" % label
            if not -len(cur) <= seg[1] < len(cur):
                return False, None, "%s has %d elements, no [%d]" % (label, len(cur), seg[1])
            cur = cur[seg[1]]
            where += "[%d]" % seg[1]
        else:
            _, key, want = seg
            if not isinstance(cur, list):
                return False, None, "%s is not a list" % label
            hits = [e for e in cur if isinstance(e, dict) and key in e and _sel_text(e[key]) == want]
            if not hits:
                have = [_sel_text(e.get(key)) for e in cur if isinstance(e, dict)]
                return False, None, "no element with %s=%s in %s (%d elements: %s)" % (
                    key, want, label, len(cur), ", ".join(have[:12]) or "none")
            cur = hits[0]
            where += "[%s=%s]" % (key, want)
    return True, cur, ""


def _is_num(v):
    return isinstance(v, NUM) and not isinstance(v, bool)


def _equal(a, b):
    if _is_num(a) and _is_num(b):
        return float(a) == float(b)
    return a == b


def _element_matches(element, want):
    if _equal(element, want):
        return True
    if isinstance(want, dict) and isinstance(element, dict):
        return all(k in element and _equal(element[k], v) for k, v in want.items())
    return False


def check_value(data, path, op, value=None):
    """(holds, explanation) for one state check."""
    found, actual, why = resolve(data, path)
    if op == "missing":
        ok = not found or actual is None
        return ok, ("%s is not there" % path) if ok else ("%s is %s" % (path, _short(actual)))
    if op == "exists":
        if found and actual is not None:
            return True, "%s = %s" % (path, _short(actual))
        return False, why or "%s is null" % path
    if not found:
        return False, why
    shown = "%s is %s" % (path, _short(actual))
    if op in ("==", "!="):
        ok = _equal(actual, value) == (op == "==")
    elif op in ("<", ">", "<=", ">="):
        if not _is_num(actual):
            return False, "%s, not a number" % shown
        a, b = float(actual), float(value)
        ok = {"<": a < b, ">": a > b, "<=": a <= b, ">=": a >= b}[op]
    elif op == "contains":
        if isinstance(actual, str):
            ok = isinstance(value, str) and value in actual
        elif isinstance(actual, list):
            ok = any(_element_matches(e, value) for e in actual)
        elif isinstance(actual, dict):
            ok = isinstance(value, str) and value in actual
        else:
            ok = False
    elif op == "matches":
        ok = isinstance(actual, str) and re.search(value, actual) is not None
    else:
        return False, "unknown op %s" % op
    if ok:
        return True, shown
    return False, "%s, expected %s %s" % (shown, op, _short(value))


# ---------------------------------------------------------------------------------------------------- validation
def _type_ok(v, types):
    if types is ANY:
        return True
    if isinstance(v, bool) and bool not in (types if isinstance(types, tuple) else (types,)):
        return False
    return isinstance(v, types)


def _type_name(types):
    names = {str: "text", int: "a whole number", float: "a number", bool: "true or false", dict: "an object",
             list: "a list"}
    if types is NUM:
        return "a number"
    if isinstance(types, tuple):
        return " or ".join(names.get(t, t.__name__) for t in types)
    return names.get(types, types.__name__)


def _step_errors(i, step, marks):
    where = "step %d" % i
    if not isinstance(step, dict):
        return ["%s is not an object" % where]
    kind = step.get("do")
    if kind is None:
        return ["%s has no \"do\" (one of: %s)" % (where, ", ".join(STEPS))]
    if kind not in STEPS:
        return ["%s: unknown \"do\": %s (one of: %s)" % (where, _short(kind), ", ".join(STEPS))]
    where = "step %d (%s)" % (i, kind)
    fields = STEPS[kind][1]
    errors = []
    for k, v in step.items():
        if k in ("do", "label"):
            if k == "label" and not isinstance(v, str):
                errors.append("%s: label must be text" % where)
            continue
        if k not in fields:
            errors.append("%s: unknown field \"%s\" (it takes: %s)" % (where, k, ", ".join(fields) or "nothing"))
            continue
        types = fields[k][0]
        if not _type_ok(v, types):
            errors.append("%s: \"%s\" must be %s" % (where, k, _type_name(types)))
    for k, (types, required, _) in fields.items():
        if required and k not in step:
            errors.append("%s needs \"%s\" (%s)" % (where, k, fields[k][2]))
    if errors:
        return errors

    def timeout(lo_exclusive, hi):
        t = step.get("timeout_s")
        if t is not None and not ((t > 0 if lo_exclusive else t >= 0) and t <= hi):
            errors.append("%s: timeout_s must be %s 0 and at most %d" % (where, "more than" if lo_exclusive else
                                                                         "at least", hi))

    def regex(field):
        try:
            re.compile(step[field])
        except re.error as e:
            errors.append("%s: %s is not a valid regular expression: %s" % (where, field, e))

    if kind == "wait":
        what = step["for"]
        if what not in ("world", "player", "log"):
            errors.append("%s: \"for\" must be world, player or log" % where)
        if what == "log" and not step.get("match"):
            errors.append("%s: wait for log needs \"match\"" % where)
        if what != "log" and ("match" in step or "since" in step):
            errors.append("%s: match and since are for \"for\": \"log\"" % where)
        timeout(True, 600)
    elif kind == "console":
        if "expect_re" in step:
            regex("expect_re")
        if isinstance(step.get("expect"), list) and not all(isinstance(e, str) for e in step["expect"]):
            errors.append("%s: expect must be text or a list of texts" % where)
        if step.get("status", "ran") not in CONSOLE_STATUSES:
            errors.append("%s: status must be one of %s" % (where, ", ".join(CONSOLE_STATUSES)))
        if not 0 <= step.get("settle_ms", 0) <= 5000:
            errors.append("%s: settle_ms must be 0-5000" % where)
        timeout(True, 120)
    elif kind == "state":
        try:
            parse_path(step["path"])
        except ValueError as e:
            errors.append("%s: bad path: %s" % (where, e))
        op = step["op"]
        if op not in OPS:
            errors.append("%s: op must be one of %s" % (where, " ".join(OPS)))
        elif op in ("exists", "missing"):
            if "value" in step:
                errors.append("%s: op %s takes no value" % (where, op))
        elif "value" not in step:
            errors.append("%s: op %s needs a value" % (where, op))
        elif op in ("<", ">", "<=", ">=") and not _is_num(step["value"]):
            errors.append("%s: op %s needs a number as value" % (where, op))
        elif op == "matches":
            if not isinstance(step["value"], str):
                errors.append("%s: op matches needs a regular expression as value" % where)
            else:
                try:
                    re.compile(step["value"])
                except re.error as e:
                    errors.append("%s: value is not a valid regular expression: %s" % (where, e))
        timeout(False, 600)
    elif kind == "mod_key":
        if step.get("action", "press") not in ("press", "down", "up"):
            errors.append("%s: action must be press, down or up" % where)
    elif kind == "screenshot":
        if "max_width" in step and not 16 <= step["max_width"] <= 16384:
            errors.append("%s: max_width must be 16-16384" % where)
    elif kind == "sleep":
        if not 0 <= step["s"] <= 600:
            errors.append("%s: s must be 0-600" % where)
    elif kind == "edit_file":
        has_find, has_write = "find" in step, "write" in step
        if has_find == has_write:
            errors.append("%s needs either find + replace or write" % where)
        elif has_find and "replace" not in step:
            errors.append("%s: find needs replace" % where)
        elif has_find and not step["find"]:
            errors.append("%s: find is empty" % where)
        if ("replace" in step or "all" in step) and not has_find:
            errors.append("%s: replace and all go with find" % where)
    elif kind == "load_world":
        errors += _load_world_field_errors(where, step)
        timeout(True, 600)
    elif kind == "log_mark":
        marks.add(step["name"])
    elif kind == "log_since_mark":
        if step["mark"] not in marks:
            errors.append("%s: mark \"%s\" is not set by an earlier log_mark" % (where, step["mark"]))
        if ("match" in step) == ("match_re" in step):
            errors.append("%s needs either match or match_re" % where)
        elif "match_re" in step:
            regex("match_re")
        timeout(False, 600)
    return errors


def _load_world_field_errors(where, fields):
    """The range checks of load_world's slot and character (in a step or the scenario's load_world object)."""
    errors = []
    for k, (lo, hi) in _LOAD_WORLD_RANGES.items():
        if k in fields and not lo <= fields[k] <= hi:
            errors.append("%s: %s must be %d-%d (a LOCAL %s slot)" % (where, k, lo, hi,
                                                                      "world" if k == "slot" else "character"))
    return errors


def _load_world_defaults_errors(value):
    """The scenario's own "load_world" object: {"slot", "character", "expect_name"}, the load_world steps' defaults."""
    where = "the scenario's load_world"
    if not isinstance(value, dict):
        return ["%s must be an object with slot, character and expect_name" % where]
    fields = STEPS["load_world"][1]
    errors = []
    for k, v in value.items():
        if k not in ("slot", "character", "expect_name"):
            errors.append("%s: unknown field \"%s\" (it takes: slot, character, expect_name)" % (where, k))
        elif not _type_ok(v, fields[k][0]):
            errors.append("%s: \"%s\" must be %s" % (where, k, _type_name(fields[k][0])))
    return errors or _load_world_field_errors(where, value)


def validate(scenario):
    """Returns the scenario when it is valid; raises ScenarioError listing every problem."""
    if not isinstance(scenario, dict):
        raise ScenarioError("a scenario is a JSON object with \"name\" and \"steps\"")
    errors = []
    if not isinstance(scenario.get("name"), str) or not scenario.get("name"):
        errors.append("the scenario needs a \"name\" (text)")
    for k in scenario:
        if k not in ("name", "description", "steps", "load_world"):
            errors.append("unknown top-level field \"%s\" (name, description, steps, load_world)" % k)
    if "load_world" in scenario:
        errors += _load_world_defaults_errors(scenario["load_world"])
    steps = scenario.get("steps")
    if not isinstance(steps, list) or not steps:
        errors.append("the scenario needs \"steps\": a list with at least one step")
    else:
        marks = set()
        for i, step in enumerate(steps, 1):
            errors += _step_errors(i, step, marks)
    if errors:
        raise ScenarioError("\n".join(errors))
    return scenario


def load_scenario(path):
    try:
        with open(path, "r", encoding="utf-8-sig") as f:
            data = json.load(f)
    except OSError as e:
        raise ScenarioError("cannot read %s: %s" % (path, e.strerror or e))
    except ValueError as e:
        raise ScenarioError("%s is not valid JSON: %s" % (path, e))
    try:
        return validate(data)
    except ScenarioError as e:
        raise ScenarioError("%s:\n%s" % (path, e))


# ---------------------------------------------------------------------------------------------------- running
def _safe_name(name):
    return re.sub(r"[^A-Za-z0-9_.-]", "_", name)[:80] or "shot"


def _show_lines(lines, limit=8):
    if not lines:
        return "(no output)"
    shown = " | ".join(lines[:limit])
    if len(lines) > limit:
        shown += " | ... (%d lines)" % len(lines)
    return shown if len(shown) <= 600 else shown[:597] + "..."


def _crlf(text):
    return text.replace("\r\n", "\n").replace("\n", "\r\n")


def _sha256(data):
    return hashlib.sha256(data).hexdigest() if data is not None else None


def _read_or_none(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except FileNotFoundError:
        return None


def _pid_alive(pid):
    return pid == os.getpid() or bool(emf_bridge._process_path(int(pid))) if pid else False


def scenario_root():
    """Where runs keep their output folders by default, and the only place recover() looks on its own."""
    return os.environ.get("EMF_SCENARIO_ROOT") or os.path.join(tempfile.gettempdir(), "emf_scenario")


def _inside(path, root):
    path, root = os.path.normcase(path), os.path.normcase(root)
    try:
        return os.path.commonpath([path, root]) == root
    except ValueError:
        return False


_RESERVED_NAME = re.compile(r"^(con|prn|aux|nul|com[0-9]|lpt[0-9]|conin\$|conout\$)(\..*)?$", re.I)
_SHA256 = re.compile(r"^[0-9a-f]{64}$")


def mod_file(game, path):
    """(full path, 'emf/mods/<id>/...') of a file inside one of the game's mod folders. Raises ValueError (in words)
    for anything else: outside emf\\mods\\<id>\\ (also through a junction), a folder, a stream (':'), a device name
    (CON, NUL, COM1...), a name ending in a dot or a space."""
    refuse = ValueError("%s is not a file inside the game's emf\\mods\\<id>\\ folder: edit_file only changes mods' "
                        "files" % path)
    if not game:
        raise ValueError("the game folder is not known: pass --game <folder>")
    if not isinstance(path, str) or not path:
        raise refuse
    p = path.replace("/", os.sep).replace("\\", os.sep)
    if os.path.isabs(p) or os.path.splitdrive(p)[0] or ":" in p:
        raise refuse
    for part in p.split(os.sep):
        if part in ("", ".", ".."):
            continue
        if part != part.rstrip(". ") or _RESERVED_NAME.match(part):
            raise refuse
    full = os.path.realpath(os.path.join(game, p))
    root = os.path.realpath(os.path.join(game, "emf", "mods"))
    try:
        rel = os.path.relpath(full, root)
    except ValueError:
        raise refuse
    parts = rel.split(os.sep)
    if parts[0] == ".." or os.path.isabs(rel) or len(parts) < 2 or os.path.isdir(full):
        raise refuse
    return full, "emf/mods/" + "/".join(parts)


def recover(root=None, echo=print, alive=_pid_alive, journals=None):
    """Puts back the files a run that was cut off (killed, closed) changed with edit_file. Each run keeps a journal
    (<out>\\restore.json) while files are changed; a journal whose process no longer runs is undone here. Nothing in a
    journal is trusted: each file must be a mod file of the journal's game (mod_file), each backup must lie in that
    run's own backups folder, and a file is put back only when it still holds what the run wrote (its SHA-256).
    Looks only at <root>\\*\\restore.json (default scenario_root()), or at the given journal files. Returns how many
    files it did not put back (0: all fine)."""
    paths = journals if journals is not None else sorted(glob.glob(os.path.join(root or scenario_root(), "*",
                                                                                "restore.json")))
    failures = 0
    for journal in paths:
        if not os.path.isfile(journal):
            continue
        try:
            with open(journal, encoding="utf-8") as f:
                data = json.load(f)
            if alive(int(data.get("pid", 0))):
                continue
            entries, game = list(data.get("files", [])), data.get("game")
        except (OSError, ValueError, TypeError, AttributeError) as e:
            echo("could not read %s: %s" % (journal, e))
            failures += 1
            continue
        backups = os.path.realpath(os.path.join(os.path.dirname(journal), "backups"))
        for entry in entries:
            rel = str(entry.get("rel", "?")) if isinstance(entry, dict) else "?"
            try:
                full, _ = mod_file(game, rel)
                if os.path.normcase(os.path.realpath(str(entry.get("full", "")))) != os.path.normcase(full):
                    raise ValueError(rel)
            except (ValueError, AttributeError):
                echo("left %s alone: it is not a mod file of the game in %s" % (rel, journal))
                failures += 1
                continue
            written, backup = entry.get("written"), entry.get("backup")
            if not isinstance(written, str) or not _SHA256.match(written):
                echo("left %s alone: the journal %s holds no valid hash for it" % (rel, journal))
                failures += 1
                continue
            if backup is not None and not (isinstance(backup, str) and _inside(os.path.realpath(backup), backups)):
                echo("left %s alone: its backup is not in that run's own backups folder (%s)" % (rel, backups))
                failures += 1
                continue
            try:
                current = _read_or_none(full)
                if _sha256(current) != written:
                    echo("left %s alone: it was changed since a run that was cut off changed it%s" % (
                        rel, "; its original is in " + backup if backup else ""))
                    failures += 1
                    continue
                if backup:
                    with open(backup, "rb") as f:
                        Runner._write(full, f.read())
                    echo("put back %s (a run that was cut off had changed it)" % rel)
                elif current is not None:
                    os.remove(full)
                    echo("removed %s (a run that was cut off had made it)" % rel)
            except OSError as e:
                echo("could not put back %s: %s" % (rel, e.strerror or e))
                failures += 1
        try:
            os.replace(journal, journal[:-len(".json")] + ".done.json")
        except OSError:
            pass
    return failures


def character_text(character):
    """The state's character in a few words: "LOCAL character slot 1 'Character 2'"."""
    c = character or {}
    return "%s character slot %s%s" % ("LOCAL" if c.get("storage") == "local" else "Steam", c.get("slot"),
                                       " '%s'" % c["name"] if c.get("name") else "")


def character_refusal(state, expect_name=None):
    """Why the running world's character does not allow world-changing work, or None. A world runs only with a LOCAL
    character (state.character.storage "local", and expect_name when given); a Steam character, or one the bridge
    cannot tell (storage "unknown", or no character field: an older EMF), refuses it. No world (the main menu) and
    the dedicated server (it has no character of its own) need none."""
    world = (state or {}).get("world") or {}
    if world.get("status") in (None, "none") or world.get("kind") == "dedicated":
        return None
    c = (state or {}).get("character")
    storage = c.get("storage") if isinstance(c, dict) else None
    if storage == "steam":
        return ("the running world uses a Steam character (%s): world-changing work only runs with a LOCAL character; "
                "go back to the main menu and use load_world" % character_text(c))
    if storage != "local":
        return "can't tell which character runs: go back to the main menu and use load_world"
    if expect_name and c.get("name") != expect_name:
        return ("the running world uses %s, not '%s': go back to the main menu and use load_world" % (
            character_text(c), expect_name))
    return None


def world_change_refusal(state, allow_cloud=False, expect_name=None):
    """Why world-changing steps (console, mod_key, edit_file) must not run in this state, or None. They run at the
    main menu (no world) and in a LOCAL save (state.world.slot's high byte 0) played with a LOCAL character
    (character_refusal; with expect_name, that one); not in a Steam Cloud save or with a Steam character, and not
    when the bridge cannot say which save or character runs. allow_cloud (--allow-cloud-world) skips the check."""
    if allow_cloud:
        return None
    world = (state or {}).get("world") or {}
    if world.get("status") in (None, "none"):
        return None
    slot = world.get("slot")
    if slot is None:
        return ("cannot tell which save the running world is (the bridge gives no slot): world-changing steps only run "
                "in a LOCAL world (--allow-cloud-world overrides)")
    if int(slot) & 0xFF00:
        return ("the running world is a Steam Cloud save (slot 0x%04x): world-changing steps only run in a LOCAL world "
                "(--allow-cloud-world overrides)" % int(slot))
    return character_refusal(state, expect_name)


def world_text(world):
    """A running world in a few words: "LOCAL slot 1 'My World 1'", "Steam Cloud slot 0x0101", "someone else's game"."""
    world = world or {}
    slot, name = world.get("slot"), world.get("name")
    if world.get("kind") == "client":
        what = "someone else's game"
    elif slot is None:
        what = "its save slot is unknown"
    elif int(slot) & 0xFF00:
        what = "Steam Cloud slot 0x%04x" % int(slot)
    else:
        what = "LOCAL slot %d" % int(slot)
    return what + (" '%s'" % name if name else "")


def loaded_world_problem(reply, state, slot, character, expect_name=None):
    """What is wrong with the world a load_world started, or None when the game's reply and the state agree that the
    LOCAL save asked for runs with the LOCAL character asked for: (why, end_game). end_game is True when another save
    or character runs (a Steam Cloud world, another LOCAL slot, another world than the reply named, a Steam or another
    character): it is to be ended at once, without saving. A state that cannot tell the slot or the character is a
    problem without end_game (nothing is known to be wrong)."""
    if reply.get("slot") != slot or reply.get("character") != character:
        return ("the game's reply names LOCAL world slot %s and character %s, not world slot %d and character %d" % (
            reply.get("slot"), reply.get("character"), slot, character), True)
    if expect_name and reply.get("character_name") != expect_name:
        return ("the game's reply names the character '%s', not '%s'" % (reply.get("character_name"), expect_name),
                True)
    world = (state or {}).get("world") or {}
    if world.get("status") != "running":
        return ("after the start the state says the world is %s, not running" % (world.get("status") or "unknown"),
                False)
    s = world.get("slot")
    if s is None:
        return ("the state gives no save slot, so the LOCAL save is not confirmed: check the screen", False)
    if int(s) & 0xFF00:
        return ("a Steam Cloud world runs (slot 0x%04x), not LOCAL world slot %d" % (int(s), slot), True)
    if int(s) != slot:
        return ("another LOCAL world runs (slot %d), not world slot %d" % (int(s), slot), True)
    name, said = world.get("name"), reply.get("world")
    if name is not None and said and name != said:
        return ("the running world is '%s', but the game's reply named '%s'" % (name, said), True)
    c = (state or {}).get("character")
    storage = c.get("storage") if isinstance(c, dict) else None
    if storage not in ("local", "steam"):
        return ("can't tell which character runs (the state gives none), so the LOCAL character is not confirmed", False)
    if storage == "steam":
        return ("the running world uses a Steam character (%s), not LOCAL character slot %d" % (character_text(c),
                                                                                              character), True)
    if c.get("slot") != character or (expect_name and c.get("name") != expect_name):
        return ("the running world uses %s, not LOCAL character slot %d%s" % (
            character_text(c), character, " '%s'" % expect_name if expect_name else ""), True)
    return None


class _Failed(Exception):
    """A step failed with this reason."""


class Runner:
    """Runs one validated scenario on a bridge connection (anything with request(cmd, **fields), like
    emf_bridge.Bridge). game is the game folder (for edit_file); out_dir receives screenshots and file backups."""

    def __init__(self, bridge, game=None, out_dir=None, echo=print, keep_going=False, sleep=time.sleep,
                 monotonic=time.monotonic, allow_cloud_world=False):
        self.bridge = bridge
        self.game = game
        self.allow_cloud_world = allow_cloud_world
        self.out_dir = out_dir or default_out_dir("run")
        self.echo = echo
        self.keep_going = keep_going
        self.sleep = sleep
        self.monotonic = monotonic
        self.marks = {}
        self.originals = {}  # rel path -> (full path, original bytes or None when it did not exist)
        self.journal_info = {}  # rel path -> {"backup": path or None, "written": sha256 of what this run wrote}
        self.order = []
        self.restored = []
        self.index = 0
        self.load_world_defaults = dict(LOAD_WORLD_DEFAULTS)
        self.expect_character = None  # the scenario's own load_world.expect_name: world-changing steps need it

    def _write_journal(self):
        """<out>\\restore.json while files are changed, so recover() can undo a run that was cut off."""
        path = os.path.join(self.out_dir, "restore.json")
        if not self.order:
            if os.path.exists(path):
                os.remove(path)
            return
        files = [dict(self.journal_info[rel], rel=rel, full=self.originals[rel][0]) for rel in self.order]
        self._out()
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"pid": os.getpid(), "game": self.game, "files": files}, f, indent=1)
        os.replace(tmp, path)

    # ---- helpers ----
    def _req(self, cmd, **fields):
        try:
            return self.bridge.request(cmd, **fields)
        except (ConnectError, BridgeError):
            raise
        except (OSError, ValueError) as e:  # a broken pipe, a reply cut off
            raise ConnectError(str(e) or e.__class__.__name__)

    def _out(self, *sub):
        path = os.path.join(self.out_dir, *sub)
        os.makedirs(path, exist_ok=True)
        return path

    @staticmethod
    def title(step):
        if step.get("label"):
            return step["label"]
        kind = step["do"]
        if kind == "wait":
            return "wait " + step["for"] + (" '%s'" % step["match"] if step.get("match") else "")
        if kind == "console":
            return "console '%s'" % step["text"]
        if kind == "state":
            return "state %s %s%s" % (step["path"], step["op"], " " + _short(step["value"], 60) if "value" in step
                                      else "")
        if kind == "mods":
            return "mods %s%s" % (step["id"], " " + step["status"] if step.get("status") else "")
        if kind == "mod_key":
            return "mod_key %s%s" % (step["key"], " " + step["action"] if step.get("action") else "")
        if kind == "screenshot":
            return "screenshot " + step.get("name", "shot")
        if kind == "sleep":
            return "sleep %g s" % step["s"]
        if kind in ("edit_file", "restore_file"):
            return "%s %s" % (kind, step["path"])
        if kind == "log_mark":
            return "log_mark " + step["name"]
        if kind == "log_since_mark":
            what = step.get("match") or step.get("match_re")
            return "log_since_mark %s %s'%s'" % (step["mark"], "no " if step.get("absent") else "", what)
        if kind == "load_world":
            shown = ["%s %s" % (k, step[k]) for k in ("slot", "character") if k in step]
            return "load_world" + (" " + ", ".join(shown) if shown else "")
        return kind

    # ---- the run ----
    def run(self, scenario):
        steps = scenario["steps"]
        self.load_world_defaults = dict(LOAD_WORLD_DEFAULTS, **scenario.get("load_world", {}))
        self.expect_character = scenario.get("load_world", {}).get("expect_name") or None
        report = {"scenario": scenario["name"], "description": scenario.get("description", ""), "ok": False,
                  "passed": 0, "failed": 0, "skipped": 0, "elapsed_s": 0.0, "out_dir": self.out_dir,
                  "steps": [{"index": i, "do": s["do"], "title": self.title(s), "status": "skipped", "detail": "",
                             "elapsed_s": 0.0, "data": {}} for i, s in enumerate(steps, 1)],
                  "restored": self.restored, "restore_failed": []}
        start = self.monotonic()
        stop = False
        try:
            for i, step in enumerate(steps, 1):
                if stop:
                    break
                entry = report["steps"][i - 1]
                self.index = i
                t0 = self.monotonic()
                lost = False
                data = {}
                try:
                    ok, detail, data = True, *self._run_step(step)
                except _Failed as e:
                    ok, detail = False, str(e)
                except BridgeError as e:
                    ok, detail = False, "%s: %s" % (e.code or "error", e.reply.get("error", "failed"))
                except ConnectError as e:
                    ok, detail, lost = False, "lost the connection to the game: %s" % e, True
                except Exception as e:  # a reply the runner did not expect: a failure, not a crash
                    ok, detail = False, "internal error: %s: %s" % (e.__class__.__name__, e)
                entry.update(status="ok" if ok else "fail", detail=detail, data=data or {},
                             elapsed_s=round(self.monotonic() - t0, 3))
                took = entry["elapsed_s"]
                self.echo("%-4s %2d %s%s%s" % ("ok" if ok else "FAIL", i, entry["title"],
                                               ": " + detail if detail else "",
                                               " (%.1f s)" % took if took >= 1 else ""))
                if not ok and (lost or not self.keep_going):
                    stop = True
        finally:
            self._restore_all(report)
            for entry in report["steps"]:
                report[{"ok": "passed", "fail": "failed", "skipped": "skipped"}[entry["status"]]] += 1
            report["elapsed_s"] = round(self.monotonic() - start, 3)
            report["ok"] = report["failed"] == 0 and report["skipped"] == 0 and not report["restore_failed"]
            self.echo("%s: %d passed, %d failed, %d skipped (%.1f s)%s" % (
                scenario["name"], report["passed"], report["failed"], report["skipped"], report["elapsed_s"],
                "; files in " + self.out_dir if os.path.isdir(self.out_dir) and os.listdir(self.out_dir) else ""))
        return report

    def _run_step(self, step):
        """(detail, data) when the step passes; raises _Failed (or a bridge error) when not."""
        return getattr(self, "_do_" + step["do"])(step)

    # ---- the steps ----
    def _do_hello(self, step):
        r = self._req("hello")
        detail = "EMF %s (API %s), game build %s, %s, pid %s" % (r.get("emf"), r.get("api"), r.get("game_build"),
                                                                 r.get("process"), r.get("pid"))
        for k, v in step.get("expect", {}).items():
            if not _equal(r.get(k), v):
                raise _Failed("%s is %s, expected %s (%s)" % (k, _short(r.get(k)), _short(v), detail))
        return detail, {"hello": {k: v for k, v in r.items() if k not in ("id", "ok")}}

    def _do_wait(self, step):
        fields = {"for": step["for"]}
        if "timeout_s" in step:
            fields["timeout_ms"] = max(1, int(round(step["timeout_s"] * 1000)))
        if "match" in step:
            fields["match"] = step["match"]
        if "since" in step:
            fields["since"] = step["since"]
        try:
            r = self._req("wait", **fields)
        except BridgeError as e:
            if e.code == "timeout":
                raise _Failed("timed out after %s s" % (step.get("timeout_s", 30)))
            raise
        if step["for"] == "log":
            return "line %s: %s" % (r.get("seq"), r.get("line")), {"seq": r.get("seq"), "line": r.get("line")}
        return {"world": "a world is running", "player": "the local player exists"}[step["for"]], {}

    def _check_world(self):
        """World-changing steps run only at the main menu, or in a LOCAL save with a LOCAL character (the one the
        scenario's load_world names, when it names one): world_change_refusal."""
        if self.allow_cloud_world:
            return
        why = world_change_refusal(self._req("state"), expect_name=self.expect_character)
        if why:
            raise _Failed(why)

    def _do_console(self, step):
        self._check_world()
        fields = {"text": step["text"]}
        if "timeout_s" in step:
            fields["timeout_ms"] = max(1, int(round(step["timeout_s"] * 1000)))
        if "settle_ms" in step:
            fields["settle_ms"] = step["settle_ms"]
        try:
            r = self._req("console", **fields)
        except BridgeError as e:
            if e.code == "timeout":
                raise _Failed("timed out after %s s; output so far: %s" % (
                    step.get("timeout_s", 10), _show_lines(e.reply.get("output", []))))
            raise
        out = r.get("output", [])
        joined = "\n".join(out)
        data = {"status": r.get("status"), "output": out, "log_seq": r.get("log_seq")}
        want = step.get("status", "ran")
        if r.get("status") != want:
            raise _Failed("status %s, expected %s; output: %s" % (r.get("status"), want, _show_lines(out)))
        expects = step.get("expect", [])
        for e in [expects] if isinstance(expects, str) else expects:
            if e not in joined:
                raise _Failed("the output has no %s; output: %s" % (_short(e), _show_lines(out)))
        if "expect_re" in step and not re.search(step["expect_re"], joined, re.M):
            raise _Failed("the output does not match %s; output: %s" % (_short(step["expect_re"]), _show_lines(out)))
        first = out[0] if out else "(no output)"
        if len(first) > 160:
            first = first[:157] + "..."
        more = len(out) - 1
        return first + (" (+%d line%s)" % (more, "" if more == 1 else "s") if more else ""), data

    def _do_state(self, step):
        timeout = step.get("timeout_s", 0)
        deadline = self.monotonic() + timeout
        while True:
            state = self._req("state")
            ok, why = check_value(state, step["path"], step["op"], step.get("value"))
            if ok:
                found, value, _ = resolve(state, step["path"])
                return why, {"value": value if found else None}
            if self.monotonic() >= deadline:
                raise _Failed(why + (" (still after %g s)" % timeout if timeout else ""))
            self.sleep(POLL_S)

    def _do_mods(self, step):
        mods = self._req("mods").get("mods", [])
        m = next((x for x in mods if x.get("id") == step["id"]), None)
        if m is None:
            raise _Failed("no mod '%s' (the game lists: %s)" % (step["id"], ", ".join(x.get("id", "?") for x in mods)))
        detail = "%s %s %s%s" % (m.get("id"), m.get("version"), m.get("status"),
                                 " (%s)" % m["reason"] if m.get("reason") else "")
        if step.get("status") and m.get("status") != step["status"]:
            raise _Failed("%s, expected %s" % (detail, step["status"]))
        return detail, {"mod": m}

    def _do_mod_key(self, step):
        self._check_world()
        fields = {"key": step["key"]}
        if "action" in step:
            fields["action"] = step["action"]
        if "hold_ms" in step:
            fields["hold_ms"] = step["hold_ms"]
        r = self._req("mod_key", **fields)
        reads = r.get("mod_reads", 0)
        action = r.get("action", step.get("action", "press"))
        detail = {"press": "pressed %s; mods read it %d times" % (r.get("key"), reads),
                  "down": "%s held down for mods" % r.get("key"),
                  "up": "released %s; mods read it %d times" % (r.get("key"), reads)}.get(action, action)
        if "min_reads" in step and reads < step["min_reads"]:
            raise _Failed("mods read %s %d times, expected at least %d (does a mod look at that key?)" % (
                r.get("key"), reads, step["min_reads"]))
        return detail, {"mod_reads": reads}

    def _do_screenshot(self, step):
        fields = {}
        if "max_width" in step:
            fields["max_width"] = step["max_width"]
        if "overlay" in step:
            fields["overlay"] = bool(step["overlay"])
        r = self._req("screenshot", **fields)
        src = r.get("path", "")
        dst = os.path.join(self._out(), "%02d_%s.png" % (self.index, _safe_name(step.get("name", "shot"))))
        try:
            shutil.copyfile(src, dst)
        except OSError as e:
            raise _Failed("the game wrote %s, but it could not be copied: %s" % (src, e.strerror or e))
        return "%s (%sx%s%s)" % (dst, r.get("width"), r.get("height"), ", HDR tone-mapped" if r.get("hdr") else ""), {
            "path": src, "copy": dst, "width": r.get("width"), "height": r.get("height")}

    def _do_sleep(self, step):
        self.sleep(step["s"])
        return "", {}

    def _do_load_world(self, step):
        d = self.load_world_defaults
        slot = step.get("slot", d["slot"])
        character = step.get("character", d["character"])
        name = step.get("expect_name", d["expect_name"])
        state = self._req("state")
        world = state.get("world") or {}
        if world.get("status") not in (None, "none"):
            if world.get("status") == "running" and world.get("kind") == "server" and world.get("slot") == slot:
                why = character_refusal(state, name or None)  # (never a world played with a Steam character)
                if why:
                    raise _Failed(why)
                return ("LOCAL world slot %d%s runs already with %s: not started again" % (
                    slot, " '%s'" % world["name"] if world.get("name") else "", character_text(state["character"])),
                    {"world": world.get("name"), "slot": slot, "already": True})
            raise _Failed("a world is %s already (%s): load_world starts a world from the main menu only" % (
                world.get("status"), world_text(world)))
        fields = {"slot": slot, "character": character,
                  "timeout_ms": int(round(step.get("timeout_s", LOAD_WORLD_TIMEOUT_S) * 1000))}
        if name:
            fields["expect_name"] = name
        try:
            r = self._req("load_world", **fields)
        except BridgeError as e:
            raise _Failed(emf_bridge.load_world_message(e.code, e.reply.get("error", "")))
        problem = loaded_world_problem(r, self._req("state"), slot, character, name or None)
        if problem:
            why, end_game = problem
            if end_game:
                raise _Failed("WRONG WORLD: %s. End the game at once without saving (end its process), then check "
                              "the saves" % why)
            raise _Failed(why)
        data = {k: r.get(k) for k in ("slot", "character", "world", "character_name", "ms")}
        return "'%s' runs with '%s' (LOCAL world slot %d, character %d, %.1f s in the game)" % (
            r.get("world"), r.get("character_name"), slot, character, (r.get("ms") or 0) / 1000.0), data

    def _mod_file(self, path):
        """mod_file() for this run's game; raises _Failed."""
        try:
            return mod_file(self.game, path)
        except ValueError as e:
            raise _Failed(str(e))

    @staticmethod
    def _write(full, data):
        tmp = full + ".emf_scenario_tmp"
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, full)

    def _do_edit_file(self, step):
        full, rel = self._mod_file(step["path"])
        self._check_world()
        try:
            with open(full, "rb") as f:
                before = f.read()
        except FileNotFoundError:
            before = None
        except OSError as e:
            raise _Failed("cannot read %s: %s" % (rel, e.strerror or e))
        if "write" in step:
            new = step["write"].encode("utf-8")
            detail = "wrote %s (%d bytes)" % (rel, len(new))
        else:
            if before is None:
                raise _Failed("%s does not exist" % rel)
            try:
                text = before.decode("utf-8")
            except UnicodeDecodeError:
                raise _Failed("%s is not UTF-8 text: use write instead of find/replace" % rel)
            find, replace = step["find"], step["replace"]
            if "\r\n" in text:  # the scenario writes \n; the file has Windows line ends
                find, replace = _crlf(find), _crlf(replace)
            count = text.count(find)
            if count == 0:
                raise _Failed("%s not found in %s" % (_short(step["find"]), rel))
            if count > 1 and not step.get("all"):
                raise _Failed("%s is in %s %d times: make find unique, or set \"all\": true" % (
                    _short(step["find"]), rel, count))
            new = text.replace(find, replace).encode("utf-8")
            detail = "changed %s (%d place%s)" % (rel, count, "" if count == 1 else "s")
        try:
            if rel not in self.originals:
                backup = None
                if before is not None:
                    backup = os.path.join(self._out("backups"), "%02d_%s" % (self.index, os.path.basename(full)))
                    with open(backup, "wb") as f:
                        f.write(before)
                self.originals[rel] = (full, before)
                self.journal_info[rel] = {"backup": backup}
                self.order.append(rel)
            self.journal_info[rel]["written"] = _sha256(new)
            self._write_journal()  # before the change: a run cut off from here on is undone by the next one
            self._write(full, new)
        except OSError as e:
            raise _Failed("cannot write %s: %s" % (rel, e.strerror or e))
        return detail + "; put back at the end", {"path": rel}

    def _forget(self, rel):
        del self.originals[rel]
        del self.journal_info[rel]
        self.order.remove(rel)
        self._write_journal()

    def _restore_one(self, rel):
        """Puts one file back. A file that no longer holds what this run wrote was changed by someone else meanwhile
        (a modder saving it): it is kept, and _Failed says so (the original stays in backups\\)."""
        full, before = self.originals[rel]
        info = self.journal_info[rel]
        if _sha256(_read_or_none(full)) != info.get("written"):
            self._forget(rel)
            raise _Failed("%s was changed during the run by someone else: kept as it is%s" % (
                rel, "; this run's original is in " + info["backup"] if info.get("backup") else ""))
        if before is None:
            if os.path.exists(full):
                os.remove(full)
        else:
            self._write(full, before)
        self._forget(rel)
        self.restored.append(rel)

    def _do_restore_file(self, step):
        full, rel = self._mod_file(step["path"])
        if rel not in self.originals:
            raise _Failed("%s was not changed by this run" % rel)
        try:
            self._restore_one(rel)
        except OSError as e:
            raise _Failed("cannot put %s back: %s" % (rel, e.strerror or e))
        return "put %s back" % rel, {"path": rel}

    def _restore_all(self, report):
        for rel in list(reversed(self.order)):
            try:
                self._restore_one(rel)
                self.echo("restored %s" % rel)
            except _Failed as e:
                report["restore_failed"].append(rel)
                self.echo("FAIL %s" % e)
            except OSError as e:
                report["restore_failed"].append(rel)
                self.echo("FAIL could not put %s back: %s; the original is in %s" % (
                    rel, e.strerror or e, os.path.join(self.out_dir, "backups")))

    def _do_log_mark(self, step):
        last = self._req("log", max=1).get("last", 0)
        self.marks[step["name"]] = last
        return "at line %d" % last, {"seq": last}

    def _lines_since(self, since):
        lines, missed, cur = [], 0, since
        for page in range(50):
            r = self._req("log", since=cur, max=5000)
            if page == 0:
                missed = r.get("missed", 0)
            lines += [(x["seq"], x["line"]) for x in r.get("lines", [])]
            if not r.get("more") or r.get("last", cur) <= cur:
                break
            cur = r["last"]
        return lines, missed

    def _do_log_since_mark(self, step):
        if step["mark"] not in self.marks:
            raise _Failed("mark '%s' was not set (its log_mark step did not run)" % step["mark"])
        since = self.marks[step["mark"]]
        timeout = step.get("timeout_s", 0)
        if "match" in step:
            text = step["match"]
            what = "containing %s" % _short(text)
            hit = lambda line: text in line  # noqa: E731
        else:
            rx = re.compile(step["match_re"])
            what = "matching %s" % _short(step["match_re"])
            hit = lambda line: rx.search(line) is not None  # noqa: E731
        if step.get("absent"):
            if timeout:
                self.sleep(timeout)
            lines, missed = self._lines_since(since)
            hits = [(s, l) for s, l in lines if hit(l)]
            if hits:
                raise _Failed("%d line%s %s after mark %s: line %d: %s" % (
                    len(hits), "" if len(hits) == 1 else "s", what, step["mark"], hits[0][0], hits[0][1]))
            if missed:
                raise _Failed("%d lines after the mark are gone already (the game keeps 5000): cannot tell" % missed)
            return "no line %s (%d lines after the mark)" % (what, len(lines)), {"checked": len(lines)}
        if "match" in step and timeout > 0:
            try:
                r = self._req("wait", **{"for": "log", "match": step["match"], "since": since,
                                         "timeout_ms": max(1, int(round(timeout * 1000)))})
            except BridgeError as e:
                if e.code == "timeout":
                    raise _Failed("no line %s after mark %s within %g s" % (what, step["mark"], timeout))
                raise
            return "line %s: %s" % (r.get("seq"), r.get("line")), {"seq": r.get("seq"), "line": r.get("line")}
        deadline = self.monotonic() + timeout
        while True:
            lines, _ = self._lines_since(since)
            for s, l in lines:
                if hit(l):
                    return "line %d: %s" % (s, l), {"seq": s, "line": l}
            if self.monotonic() >= deadline:
                raise _Failed("no line %s after mark %s%s (%d lines after it)" % (
                    what, step["mark"], " within %g s" % timeout if timeout else "", len(lines)))
            self.sleep(POLL_S)


# ---------------------------------------------------------------------------------------------------- command line
def game_from_exe(exe_path):
    return os.path.dirname(exe_path) if exe_path else None


def game_from_bridge(bridge):
    """The game folder of the process that serves the bridge's pipe, or None."""
    m = emf_bridge.PIPE_RE.match(getattr(bridge, "pipe_path", "") or "")
    if not m:
        return None
    return game_from_exe(emf_bridge._process_path(int(m.group(1))))


def steps_help():
    lines = []
    for kind, (what, fields) in STEPS.items():
        lines.append("%s: %s" % (kind, what))
        for k, (types, required, about) in fields.items():
            lines.append("    %-10s %s%s" % (k, "(required) " if required else "", about))
    lines.append("every step: \"do\" (the kind), optional \"label\" (printed instead of the step's own title)")
    return "\n".join(lines)


class _UsageError(Exception):
    pass


class _Parser(argparse.ArgumentParser):
    def error(self, message):
        raise _UsageError(message)


def default_out_dir(name):
    """<scenario_root()>\\<name>_<time>_<random>: every run its own folder (two runs in one second too)."""
    return os.path.join(scenario_root(), "%s_%s_%s" % (_safe_name(name), time.strftime("%Y%m%d-%H%M%S"),
                                                       uuid.uuid4().hex[:6]))


def run_scenario(scenario, bridge, game=None, out_dir=None, echo=print, keep_going=False, allow_cloud_world=False):
    """Runs a validated scenario on an open bridge; returns the report (report["ok"] says whether it passed). First
    puts back files that an earlier run, cut off before its end, left changed (recover() on scenario_root())."""
    out_dir = out_dir or default_out_dir(scenario["name"])
    recover(echo=echo)
    runner = Runner(bridge, game=game, out_dir=out_dir, echo=echo, keep_going=keep_going,
                    allow_cloud_world=allow_cloud_world)
    return runner.run(scenario)


def main(argv=None, bridge_factory=None, stdout=None, stderr=None):
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    p = _Parser(prog="emf_scenario.py", description="Runs an EMF test scenario through the debug bridge.")
    p.add_argument("scenario", nargs="*", help="the scenario file (with --check: any number)")
    p.add_argument("--game", help="the game folder (default: the running game's)")
    p.add_argument("--pid", type=int, help="the game's process id")
    p.add_argument("--out", help="folder for screenshots and backups (default: %%TEMP%%\\emf_scenario\\<name>_<time>)")
    p.add_argument("--json", metavar="FILE", help="write a machine-readable report to FILE ('-': to stdout; the "
                                                   "step lines then go to stderr)")
    p.add_argument("--keep-going", action="store_true", help="run the remaining steps after a failure")
    p.add_argument("--check", action="store_true", help="only check the scenario files")
    p.add_argument("--steps", action="store_true", help="list the step kinds and their fields")
    p.add_argument("--recover", action="store_true", help="only put back files that a run cut off (killed, "
                                                          "closed) left changed (every run does this first; with "
                                                          "--out, that run folder's too); exit 1 when one could not "
                                                          "be put back")
    p.add_argument("--allow-cloud-world", action="store_true", help="let console, mod_key and edit_file steps run "
                                                                    "in a world that is not a LOCAL save")
    try:
        a = p.parse_args(argv)
        if not a.steps and not a.recover and not a.scenario:
            raise _UsageError("give a scenario file (or --steps)")
        if not a.steps and not a.recover and not a.check and len(a.scenario) != 1:
            raise _UsageError("give one scenario file (--check takes several)")
    except _UsageError as e:
        print("emf_scenario.py: %s\n%s" % (e, p.format_usage().strip()), file=stderr)
        return 3

    if a.recover:
        def say(line):
            print(line, file=stdout)
        failures = recover(echo=say)
        if a.out:
            failures += recover(echo=say, journals=[os.path.join(os.path.abspath(a.out), "restore.json")])
        return 1 if failures else 0
    if a.steps:
        print(steps_help(), file=stdout)
        return 0
    if a.check:
        code = 0
        for path in a.scenario:
            try:
                s = load_scenario(path)
                print("valid: %s (%s, %d steps)" % (path, s["name"], len(s["steps"])), file=stdout)
            except ScenarioError as e:
                print("not valid: %s" % e, file=stderr)
                code = 3
        return code

    path = a.scenario[0]
    try:
        scenario = load_scenario(path)
    except ScenarioError as e:
        print("not valid: %s" % e, file=stderr)
        return 3
    out_dir = os.path.abspath(a.out) if a.out else default_out_dir(scenario["name"])
    text_out = stderr if a.json == "-" else stdout

    def echo(line):
        print(line, file=text_out, flush=True)

    def write_report(report):
        if not a.json:
            return
        text = json.dumps(report, indent=2, ensure_ascii=False)
        if a.json == "-":
            print(text, file=stdout)
        else:
            with open(a.json, "w", encoding="utf-8") as f:
                f.write(text + "\n")

    factory = bridge_factory or (lambda game, pid: emf_bridge.Bridge(game=game, pid=pid))
    try:
        bridge = factory(a.game, a.pid)
    except ConnectError as e:
        print("no connection to the game: %s" % e, file=stderr)
        write_report({"scenario": scenario["name"], "file": path, "ok": False, "exit_code": 2,
                      "error": "no connection to the game: %s" % e, "steps": []})
        return 2
    try:
        game = os.path.abspath(a.game) if a.game else game_from_bridge(bridge)
        report = run_scenario(scenario, bridge, game=game, out_dir=out_dir, echo=echo, keep_going=a.keep_going,
                              allow_cloud_world=a.allow_cloud_world)
    except KeyboardInterrupt:
        print("interrupted (changed files were put back)", file=stderr)
        return 1
    finally:
        bridge.close()
    report["file"] = path
    report["game"] = game
    report["exit_code"] = 0 if report["ok"] else 1
    write_report(report)
    return report["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
