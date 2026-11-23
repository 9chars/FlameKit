# EMF debug bridge client (docs/modding/debug_bridge.md): talks to a running game that has [debug] bridge=1 in
# emf\emf_core.ini. One command per call:
#   emf_bridge.ps1 hello
#   emf_bridge.ps1 console "near 10" [-TimeoutMs 10000] [-SettleMs 300]
#   emf_bridge.ps1 state
#   emf_bridge.ps1 mods
#   emf_bridge.ps1 wait world|player [seconds]          wait log "<text>" [seconds] [-Since <n>]
#   emf_bridge.ps1 log [-Since <n>] [-Max <n>] [-Follow]
#   emf_bridge.ps1 events pickup,kill,damage,save,load      (prints events until Ctrl+C)
#   emf_bridge.ps1 shot [-NoOverlay] [-MaxWidth <px>]
#   emf_bridge.ps1 key <name> [-Down | -Up] [-HoldMs 150]
#   emf_bridge.ps1 quit                                   (the game saves and closes)
#   emf_bridge.ps1 load_world 1 1 ["<character name>"] [-TimeoutMs 180000]   (from the main menu: LOCAL world slot 1, LOCAL character 1, offline)
#   emf_bridge.ps1 join 1 ["<character name>"] [-TimeoutMs 180000]   (the main menu's "About to join" prompt of +connect: Join Session with LOCAL character 1;
#                  the server's password from EMF_JOIN_PASSWORD, so it is on no command line)
#   emf_bridge.ps1 raw '{"cmd":"hello"}'
# -Json prints the game's reply as it came. It finds the game through -GamePid, -Game <folder>, its own place (installed
# as <game>\emf\tools\), a running enshrouded.exe / enshrouded_server.exe, or Steam; only a pipe the game named in
# emf\bridge.txt, served by that game, is used. Exit codes: 0 done, 1 the bridge said no (or a wait timed out),
# 2 no connection.
param(
    [Parameter(Position = 0, Mandatory = $true)] [string]$Command,
    [Parameter(Position = 1)] [string]$Arg1 = "",
    [Parameter(Position = 2)] [string]$Arg2 = "",
    [Parameter(Position = 3)] [string]$Arg3 = "",
    [string]$Game = "",
    [int]$GamePid = 0,
    [int]$TimeoutMs = 0,
    [int]$SettleMs = -1,
    [long]$Since = -1,
    [int]$Max = 0,
    [int]$HoldMs = 0,
    [int]$MaxWidth = 0,
    [switch]$NoOverlay,
    [switch]$Follow,
    [switch]$Down,
    [switch]$Up,
    [switch]$Json
)
$ErrorActionPreference = "Stop"

function Fail([string]$text, [int]$code) {
    [Console]::Error.WriteLine($text)
    exit $code
}

# ---- find the game and its pipe ----
# A game process: the pid runs and is enshrouded*.exe (EMF_BRIDGE_TEST_PROCESS names one more, for tests only).
function Test-GameProcess([int]$id) {
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    if ($p.ProcessName -like "enshrouded*") { return $true }
    return ($env:EMF_BRIDGE_TEST_PROCESS -and $p.ProcessName -ieq $env:EMF_BRIDGE_TEST_PROCESS)
}

# The pipe from <folder>\emf\bridge.txt, checked: \\.\pipe\emf-bridge-<pid>, the same pid as pid=, a running game.
function Read-BridgeFile([string]$folder) {
    $file = Join-Path $folder "emf\bridge.txt"
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $info = @{}
    foreach ($line in Get-Content -LiteralPath $file -TotalCount 20) {
        $eq = $line.IndexOf("=")
        if ($eq -gt 0) { $info[$line.Substring(0, $eq).Trim()] = $line.Substring($eq + 1).Trim() }
    }
    $pipe = [string]$info["pipe"]
    if ($pipe -notmatch '^\\\\\.\\pipe\\emf-bridge-(\d{1,10})$') { Fail "$file names no local EMF bridge pipe: not using it" 2 }
    $pipePid = [long]$Matches[1]
    $filePid = 0L
    if (-not [long]::TryParse([string]$info["pid"], [ref]$filePid)) { Fail "$file has no valid pid= line" 2 }
    if ($filePid -ne $pipePid) { Fail "$file is inconsistent (the pipe's pid is not pid=): not using it" 2 }
    if (-not (Test-GameProcess ([int]$filePid))) { Fail "$file is left over: no game runs with pid $filePid" 2 }
    return $pipe
}

# A game process serves its bridge: \\.\pipe\emf-bridge-<pid> exists (listing pipes connects to none), or its folder's
# emf\bridge.txt names that pipe and that pid.
function Test-ServesBridge($proc, [string[]]$pipes) {
    if ($pipes -contains "\\.\pipe\emf-bridge-$($proc.Id)") { return $true }
    $dir = if ($proc.Path) { Split-Path -Parent $proc.Path } else { "" }
    $file = if ($dir) { Join-Path $dir "emf\bridge.txt" } else { "" }
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { return $false }
    $info = @{}
    foreach ($line in Get-Content -LiteralPath $file -TotalCount 20) {
        $eq = $line.IndexOf("=")
        if ($eq -gt 0) { $info[$line.Substring(0, $eq).Trim()] = $line.Substring($eq + 1).Trim() }
    }
    return ([string]$info["pipe"] -ieq "\\.\pipe\emf-bridge-$($proc.Id)") -and ([string]$info["pid"] -eq "$($proc.Id)")
}

function Get-SteamGameFolder {
    foreach ($key in @("HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam")) {
        $root = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).SteamPath
        if (-not $root) { $root = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).InstallPath }
        if (-not $root) { continue }
        $root = $root.Replace("/", "\")
        $libs = @($root)
        $vdf = Join-Path $root "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $vdf) {
            foreach ($l in Get-Content -LiteralPath $vdf -Encoding UTF8) {
                if ($l -match '"path"\s+"(.+)"') { $libs += $Matches[1].Replace("\\", "\") }
            }
        }
        foreach ($lib in $libs) {
            $dir = Join-Path $lib "steamapps\common\Enshrouded"
            if (Test-Path -LiteralPath (Join-Path $dir "enshrouded.exe")) { return $dir }
        }
    }
    return $null
}

function Find-Pipe {
    if ($GamePid -gt 0) {
        if (-not (Test-GameProcess $GamePid)) { Fail "no game runs with pid $GamePid" 2 }
        return "\\.\pipe\emf-bridge-$GamePid"
    }
    if ($Game) {
        $p = Read-BridgeFile $Game
        if ($p) { return $p }
        Fail "no $Game\emf\bridge.txt: is the game running with [debug] bridge=1 in emf\emf_core.ini?" 2
    }
    # installed with EMF as <game>\emf\tools\emf_bridge.ps1
    $own = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    if ($own -and ((Test-Path -LiteralPath (Join-Path $own "enshrouded.exe")) -or (Test-Path -LiteralPath (Join-Path $own "enshrouded_server.exe")))) {
        $p = Read-BridgeFile $own
        if ($p) { return $p }
    }
    $procs = @(Get-Process enshrouded, enshrouded_server -ErrorAction SilentlyContinue)
    if ($procs.Count -gt 1) {
        # a stand-in or a second game without the bridge (say a test's enshrouded_server.exe) does not count
        $found = $procs.Count
        $pipes = @([System.IO.Directory]::GetFiles("\\.\pipe\"))
        $procs = @($procs | Where-Object { Test-ServesBridge $_ $pipes })
        if ($procs.Count -gt 1) {
            Fail "more than one game with the debug bridge is running (pids $(($procs | ForEach-Object { $_.Id }) -join ', ')): pass -GamePid or -Game" 2
        }
        if ($procs.Count -eq 0) { Fail "$found game processes run, none with the debug bridge on: is [debug] bridge=1 set in emf\emf_core.ini?" 2 }
    }
    if ($procs.Count -eq 1) {
        $dir = if ($procs[0].Path) { Split-Path -Parent $procs[0].Path } else { "" }
        if ($dir) {
            $p = Read-BridgeFile $dir
            if ($p) { return $p }
        }
        Fail "the game runs (pid $($procs[0].Id)) but has no emf\bridge.txt: is [debug] bridge=1 set in emf\emf_core.ini?" 2
    }
    $steam = Get-SteamGameFolder
    if ($steam) {
        $p = Read-BridgeFile $steam
        if ($p) { return $p }
    }
    Fail "the game is not running (or [debug] bridge=1 is not set in emf\emf_core.ini)" 2
}

$pipePath = Find-Pipe
$pipeName = $pipePath -replace '^\\\\\.\\pipe\\', ''
$listed = @([System.IO.Directory]::GetFiles("\\.\pipe\") | Where-Object { $_ -ieq "\\.\pipe\$pipeName" })
if ($listed.Count -eq 0) { Fail "no pipe $pipePath`: is the game running with [debug] bridge=1 in emf\emf_core.ini?" 2 }
# Identification only: the game can tell who connects, but cannot act as this user.
$client = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipeName, [System.IO.Pipes.PipeDirection]::InOut,
    [System.IO.Pipes.PipeOptions]::None, [System.Security.Principal.TokenImpersonationLevel]::Identification)
try {
    $client.Connect(30000)  # all 8 places taken: wait for one
} catch {
    Fail "could not connect to $pipePath ($($_.Exception.Message)); is the game running with [debug] bridge=1, and are 8 clients connected already?" 2
}
# The pipe must belong to the game it is named after (another program could have made a pipe with that name first).
Add-Type -Namespace EmfBridgeClient -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetNamedPipeServerProcessId(Microsoft.Win32.SafeHandles.SafePipeHandle pipe, out uint serverProcessId);
'@
if ($pipeName -match '^emf-bridge-(\d+)$') {
    $expected = [uint32]$Matches[1]
    $server = [uint32]0
    if (-not [EmfBridgeClient.Native]::GetNamedPipeServerProcessId($client.SafePipeHandle, [ref]$server) -or $server -ne $expected) {
        Fail "$pipePath is served by process $server, not by the game (pid $expected): not using it" 2
    }
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$writer = New-Object System.IO.StreamWriter($client, $utf8)
$writer.NewLine = "`n"
$writer.AutoFlush = $true
$reader = New-Object System.IO.StreamReader($client, $utf8)
$script:nextId = 1
$script:lastLine = ""

# How long a reply may take: the command's own time (timeout_ms, settle, hold) plus a margin of 15 s
# (EMF_BRIDGE_REPLY_MARGIN_MS changes it; tests). A stuck game (crashed, paused) would otherwise leave this waiting.
# load_world answers when the local player is in the world, at the latest after its timeout_ms (default 180 s) and a
# 10 s backstop of the game's own.
function Get-ReplyTimeoutMs([hashtable]$request) {
    $ms = if ($request["timeout_ms"]) { [int]$request["timeout_ms"] } else { @{ console = 10000; wait = 30000; screenshot = 5000; load_world = 180000; join = 180000 }[$request["cmd"]] }
    if (-not $ms) { $ms = 0 }
    if ($request["cmd"] -eq "console") { $ms += $(if ($null -ne $request["settle_ms"]) { [Math]::Min([Math]::Max([int]$request["settle_ms"], 0), 5000) } else { 300 }) }
    if ($request["cmd"] -eq "mod_key" -and (-not $request["action"] -or $request["action"] -eq "press")) {
        $ms += $(if ($request["hold_ms"]) { [int]$request["hold_ms"] } else { 150 })
    }
    if ($request["cmd"] -eq "load_world" -or $request["cmd"] -eq "join") { $ms += 10000 }
    $margin = 15000
    if ("$env:EMF_BRIDGE_REPLY_MARGIN_MS" -match '^\d+$') { $margin = [int]$env:EMF_BRIDGE_REPLY_MARGIN_MS }
    return $ms + $margin
}

# The next line, or exit 2 when none came within $timeoutMs (-1: wait as long as it takes, for pushed events).
function Read-Line([int]$timeoutMs) {
    if ($timeoutMs -lt 0) { return $reader.ReadLine() }
    $task = $reader.ReadLineAsync()
    if (-not $task.Wait($timeoutMs)) { Fail "no reply from the game in time: is it stuck (crashed, paused)?" 2 }
    return $task.Result
}

# Sends one request (a hashtable) and returns the reply object; pushed events meanwhile go to $onEvent.
function Invoke-Bridge([hashtable]$request, [scriptblock]$onEvent = $null) {
    $id = $script:nextId++
    $request["id"] = $id
    $deadline = (Get-Date).AddMilliseconds((Get-ReplyTimeoutMs $request))
    $writer.WriteLine(($request | ConvertTo-Json -Compress -Depth 5))
    while ($true) {
        $left = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
        $line = Read-Line $left
        if ($null -eq $line) { Fail "the game closed the connection" 2 }
        $msg = $line | ConvertFrom-Json
        if ($msg.PSObject.Properties["event"]) {
            if ($onEvent) { & $onEvent $msg }
            continue
        }
        if ($msg.id -eq $id) {
            $script:lastLine = $line
            return $msg
        }
    }
}

# -Json: the reply as it came; then the exit code from "ok".
function Show-Json($reply) {
    $script:lastLine
    if ($reply.ok) { exit 0 } else { exit 1 }
}

function Check-Ok($reply) {
    if (-not $reply.ok) { Fail "$($reply.code): $($reply.error)" 1 }
}

function Show-Log($line) { "{0,7}  {1}" -f $line.seq, $line.line }

function Follow-Events([scriptblock]$print) {
    while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line) { Fail "the game closed the connection" 2 }
        $msg = $line | ConvertFrom-Json
        if ($msg.PSObject.Properties["event"]) { & $print $msg }
    }
}

switch ($Command) {
    "hello" {
        $r = Invoke-Bridge @{ cmd = "hello" }
        if ($Json) { Show-Json $r }
        Check-Ok $r
        "EMF $($r.emf) (API $($r.api)), game build $($r.game_build), $($r.process), pid $($r.pid), bridge protocol $($r.protocol)"
    }
    "console" {
        if (-not $Arg1) { Fail "usage: emf_bridge.ps1 console `"<command line>`" [-TimeoutMs n] [-SettleMs n]" 2 }
        $req = @{ cmd = "console"; text = $Arg1 }
        if ($TimeoutMs -gt 0) { $req["timeout_ms"] = $TimeoutMs }
        if ($SettleMs -ge 0) { $req["settle_ms"] = $SettleMs }
        $r = Invoke-Bridge $req
        if ($Json) { Show-Json $r }
        foreach ($l in $r.output) { $l }
        if ($r.truncated) { "(more output was cut; the log has all of it)" }
        Check-Ok $r
        if ($r.status -ne "ran") { Fail "(the command did not run: $($r.status))" 1 }
    }
    "state" {
        $r = Invoke-Bridge @{ cmd = "state" }
        if ($Json) { Show-Json $r }
        Check-Ok $r
        $w = $r.world
        $summary = "world $($w.status)"
        if ($w.kind) { $summary += " ($($w.kind))" }
        if ($null -ne $w.slot) { $summary += ", slot $($w.slot)" }
        if ($r.character) { $summary += ", character $($r.character.storage)$(if ($null -ne $r.character.slot) { " slot $($r.character.slot)" })$(if ($r.character.name) { " '$($r.character.name)'" })" }
        if ($null -ne $w.time_of_day_h) { $summary += (", time of day {0:N2} h" -f $w.time_of_day_h) }
        if ($r.player) {
            $summary += ", player $($r.player.id)"
            if ($r.player.position) { $summary += (" at ({0:N1}, {1:N1}, {2:N1})" -f $r.player.position.x, $r.player.position.y, $r.player.position.z) }
            if ($r.player.health) {
                $summary += ", health $($r.player.health.value)"
                if ($null -ne $r.player.health.max) { $summary += "/$($r.player.health.max)" }
            }
        } else {
            $summary += ", no player"
        }
        $summary
        $r | Select-Object -Property * -ExcludeProperty id, ok | ConvertTo-Json -Depth 10
    }
    "mods" {
        $r = Invoke-Bridge @{ cmd = "mods" }
        if ($Json) { Show-Json $r }
        Check-Ok $r
        $r.mods | Format-Table -AutoSize id, version, status, reason | Out-String -Width 200
    }
    "wait" {
        $what = $Arg1
        $req = @{ cmd = "wait"; for = $what }
        $secondsArg = $Arg2
        if ($what -eq "log") {
            if (-not $Arg2) { Fail "usage: emf_bridge.ps1 wait log `"<text>`" [seconds] [-Since n]" 2 }
            $req["match"] = $Arg2
            $secondsArg = $Arg3
            if ($Since -ge 0) { $req["since"] = $Since }
        }
        if ($secondsArg) { $req["timeout_ms"] = [int]([double]$secondsArg * 1000) }
        elseif ($TimeoutMs -gt 0) { $req["timeout_ms"] = $TimeoutMs }
        $r = Invoke-Bridge $req
        if ($Json) { Show-Json $r }
        Check-Ok $r
        switch ($what) {
            "world" { "a world is running" }
            "player" { "the local player exists" }
            "log" { "log line $($r.seq): $($r.line)" }
        }
    }
    "log" {
        $req = @{ cmd = "log" }
        if ($Since -ge 0) { $req["since"] = $Since }
        if ($Max -gt 0) { $req["max"] = $Max }
        if ($Follow) { $req["follow"] = $true }
        $r = Invoke-Bridge $req
        if ($Json -and -not $Follow) { Show-Json $r }
        Check-Ok $r
        if ($r.PSObject.Properties["missed"]) { "(missed $($r.missed) lines: the game keeps the last 5000)" }
        foreach ($l in $r.lines) { Show-Log $l }
        if ($r.more -and -not $Follow) { "(more lines: emf_bridge.ps1 log -Since $($r.last))" }
        if ($Follow) {
            Follow-Events {
                param($e)
                if ($e.event -eq "log") {
                    if ($e.PSObject.Properties["missed"]) { "(missed $($e.missed) lines)" }
                    Show-Log $e
                } elseif ($e.event -eq "dropped") {
                    "(the bridge dropped $($e.lines) lines: this window reads too slowly)"
                }
            }
        }
    }
    "events" {
        $names = @()
        if ($Arg1) { $names = @($Arg1 -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        $r = Invoke-Bridge @{ cmd = "events"; names = $names }
        Check-Ok $r
        "pushing: $($r.names -join ', ') (Ctrl+C stops)"
        Follow-Events { param($e) if ($e.event -eq "game") { $e | ConvertTo-Json -Compress -Depth 5 } }
    }
    { $_ -in "shot", "screenshot" } {
        $req = @{ cmd = "screenshot" }
        if ($NoOverlay) { $req["overlay"] = $false }
        if ($MaxWidth -gt 0) { $req["max_width"] = $MaxWidth }
        $r = Invoke-Bridge $req
        if ($Json) { Show-Json $r }
        Check-Ok $r
        $hdr = if ($r.hdr) { ", HDR tone-mapped" } else { "" }
        "screenshot: $($r.path) ($($r.width)x$($r.height)$hdr)"
    }
    { $_ -in "key", "mod_key" } {
        if (-not $Arg1) { Fail "usage: emf_bridge.ps1 key <name> [-Down | -Up] [-HoldMs n]" 2 }
        $req = @{ cmd = "mod_key"; key = $Arg1 }
        if ($Down) { $req["action"] = "down" } elseif ($Up) { $req["action"] = "up" }
        if ($HoldMs -gt 0) { $req["hold_ms"] = $HoldMs }
        $r = Invoke-Bridge $req
        if ($Json) { Show-Json $r }
        Check-Ok $r
        switch ($r.action) {
            "press" { "pressed $($r.key) for mods; they read it $($r.mod_reads) times" }
            "down" { "$($r.key) is held down for mods (emf_bridge.ps1 key $($r.key) -Up releases it; at most 60 s)" }
            "up" { "released $($r.key); mods read it $($r.mod_reads) times" }
        }
    }
    "quit" {
        $r = Invoke-Bridge @{ cmd = "quit" }
        if ($Json) { Show-Json $r }
        Check-Ok $r
        "the game saves and closes"
    }
    "load_world" {
        if (-not $Arg1 -or -not $Arg2) { Fail "usage: emf_bridge.ps1 load_world <LOCAL world slot> <LOCAL character slot> [<expected character name>] [-TimeoutMs n]" 2 }
        $req = @{ cmd = "load_world"; slot = [int]$Arg1; character = [int]$Arg2 }
        if ($Arg3) { $req["expect_name"] = $Arg3 }
        if ($TimeoutMs -gt 0) { $req["timeout_ms"] = $TimeoutMs }
        $r = Invoke-Bridge $req
        if ($Json) { Show-Json $r }
        Check-Ok $r
        "'$($r.world)' runs with '$($r.character_name)' (LOCAL world slot $($r.slot), character $($r.character), $($r.ms) ms)"
    }
    "join" {
        if (-not $Arg1) { Fail "usage: emf_bridge.ps1 join <LOCAL character slot> [<expected character name>] [-TimeoutMs n]" 2 }
        $req = @{ cmd = "join"; character = [int]$Arg1 }
        if ($env:EMF_JOIN_PASSWORD) { $req["password"] = $env:EMF_JOIN_PASSWORD }
        if ($Arg2) { $req["expect_name"] = $Arg2 }
        if ($TimeoutMs -gt 0) { $req["timeout_ms"] = $TimeoutMs }
        $r = Invoke-Bridge $req
        if ($Json) { Show-Json $r }
        Check-Ok $r
        "joined with '$($r.character_name)' (LOCAL character $($r.character), $($r.ms) ms)"
    }
    "raw" {
        if (-not $Arg1) { Fail "usage: emf_bridge.ps1 raw '{`"cmd`":`"hello`"}'" 2 }
        $obj = $Arg1 | ConvertFrom-Json
        $req = @{}
        foreach ($p in $obj.PSObject.Properties) { $req[$p.Name] = $p.Value }
        $r = Invoke-Bridge $req
        Show-Json $r
    }
    default { Fail "unknown command '$Command' (hello, console, state, mods, wait, log, events, shot, key, quit, load_world, join, raw)" 2 }
}
$client.Dispose()
exit 0
