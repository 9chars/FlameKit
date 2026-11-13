# restart_helper.ps1: FlameKit's restart helper (started by restart_watch.cmd; leave its window open).
#
# Whenever a file restart.request appears in this folder, it does what the file asks, logs every step to restart.log
# and writes the result to restart.done ("ok <text>" or "failed <text>"). The request is one word, nothing else is
# ever run from it:
#   client  close the game client (like Alt+F4) and start it again through Steam
#   server  close the game client, have the server save its world, stop it and start it again, then start the client
#   both    the same as server
#   stop    stop this helper
# Whenever a file chime.request appears, it plays a chime: Claude is done and waits for the owner.
#
# Stopping the server: Ctrl+C cannot be sent to it reliably from another program, so FlameKit on the server saves the
# world on request (features/server_save.lua: save_now.request -> emf.request_save -> save_now.done). With the game
# client closed (no player connected), the server process is ended only once a save file newer than the request
# exists; without one within 90 s nothing is stopped and the request fails. The game client is never ended by force.
# The places are in restart_paths.txt next to this file (on this PC only; never in the public repository):
#   server_folder = <the local dedicated server's folder>
#   game_app_id = 1203220
#   chime_sound = <a .wav file>          (optional; default C:\Windows\Media\chimes.wav)
# When this file changes, the helper exits with code 10 and restart_watch.cmd starts it again.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
$self = $MyInvocation.MyCommand.Path
$selfTime = (Get-Item $self).LastWriteTime
$request = Join-Path $here 'restart.request'
$doneFile = Join-Path $here 'restart.done'
$logFile = Join-Path $here 'restart.log'
$chimeRequest = Join-Path $here 'chime.request'

function Log([string]$text) {
    $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $text
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

$cfg = @{}
$cfgFile = Join-Path $here 'restart_paths.txt'
if (Test-Path $cfgFile) {
    foreach ($l in Get-Content $cfgFile) { if ($l -match '^\s*(\w+)\s*=\s*(.+?)\s*$') { $cfg[$matches[1]] = $matches[2] } }
}
$serverDir = $cfg['server_folder']
$appId = if ($cfg['game_app_id']) { $cfg['game_app_id'] } else { '1203220' }
$chimeSound = if ($cfg['chime_sound']) { $cfg['chime_sound'] } else { Join-Path $env:WINDIR 'Media\chimes.wav' }
$serverExe = if ($serverDir) { Join-Path $serverDir 'enshrouded_server.exe' } else { $null }
$emfLog = if ($serverDir) { Join-Path $serverDir 'emf\emf_core.log' } else { $null }
$saveDir = if ($serverDir) { Join-Path $serverDir 'savegame' } else { $null }
$modDir = if ($serverDir) { Join-Path $serverDir 'emf\mods\flamekit' } else { $null }

function Chime {
    try {
        if (Test-Path $chimeSound) {
            $player = New-Object System.Media.SoundPlayer $chimeSound
            $player.PlaySync()
            Start-Sleep -Milliseconds 250
            $player.PlaySync()
        } else {
            [System.Media.SystemSounds]::Exclamation.Play()
        }
    } catch {
        [System.Media.SystemSounds]::Exclamation.Play()
    }
}

function Newest-Save {
    if (-not $saveDir -or -not (Test-Path $saveDir)) { return $null }
    Get-ChildItem -Path $saveDir -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Close-Client {
    $p = Get-Process -Name 'enshrouded' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { Log 'client: not running'; return $true }
    Log "client: closing (process $($p.Id)), the same as Alt+F4"
    if (-not $p.CloseMainWindow()) { Log 'client: FAILED: it has no window to close'; return $false }
    if (-not $p.WaitForExit(90000)) { Log 'client: FAILED: still running after 90 s (left running)'; return $false }
    Log 'client: closed'
    Start-Sleep -Seconds 3  # Steam notes the game ended before it is started again
    return $true
}

function Start-Client {
    Log "client: starting through Steam (steam://rungameid/$appId)"
    Start-Process "steam://rungameid/$appId"
    for ($i = 0; $i -lt 90; $i++) {
        Start-Sleep -Seconds 2
        $p = Get-Process -Name 'enshrouded' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p) { Log "client: running (process $($p.Id))"; return $true }
    }
    Log 'client: FAILED: the game did not start within 3 minutes'
    return $false
}

function Stop-Server {
    $p = Get-Process -Name 'enshrouded_server' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { Log 'server: not running'; return $true }
    if (Get-Process -Name 'enshrouded' -ErrorAction SilentlyContinue) { Log 'server: FAILED: the game client still runs (left the server running)'; return $false }
    $number = [string][DateTimeOffset]::Now.ToUnixTimeSeconds()
    $asked = Get-Date
    $before = Newest-Save
    Log "server: asking FlameKit on the server to save the world (request $number); newest save before: $(if ($before) { '{0} {1:HH:mm:ss}' -f $before.Name, $before.LastWriteTime } else { 'none found' })"
    Set-Content -Path (Join-Path $modDir 'save_now.request') -Value $number -Encoding ASCII -NoNewline
    $answered = $false
    for ($i = 0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 2
        $doneNow = Join-Path $modDir 'save_now.done'
        if (-not $answered -and (Test-Path $doneNow) -and ((Get-Content $doneNow -Raw) -as [string]).Trim() -eq $number) {
            $answered = $true
            Log 'server: FlameKit on the server asked the game to save'
        }
        $now = Newest-Save
        if ($now -and $now.LastWriteTime -gt $asked) {
            Log ("server: world saved ({0} {1:HH:mm:ss}); ending the server process" -f $now.Name, $now.LastWriteTime)
            Start-Sleep -Seconds 2  # the save files are closed
            Stop-Process -Id $p.Id -Force
            if (-not $p.WaitForExit(30000)) { Log 'server: FAILED: still running 30 s after it was ended'; return $false }
            Log 'server: stopped'
            return $true
        }
    }
    Log "server: FAILED: no new save within 90 s ($(if ($answered) { 'FlameKit answered' } else { 'FlameKit did not answer: is the server on 0.15.23?' })); the server was left running"
    return $false
}

function Start-Server {
    if (-not $serverExe -or -not (Test-Path $serverExe)) { Log "server: FAILED: enshrouded_server.exe not found (server_folder in restart_paths.txt)"; return $false }
    $started = Get-Date
    Log 'server: starting (its window opens minimized)'
    Start-Process -FilePath $serverExe -WorkingDirectory $serverDir -WindowStyle Minimized
    for ($i = 0; $i -lt 150; $i++) {
        Start-Sleep -Seconds 2
        if ($emfLog -and (Test-Path $emfLog) -and (Get-Item $emfLog).LastWriteTime -gt $started) {
            if (Select-String -Path $emfLog -Pattern 'world loaded' -SimpleMatch -Quiet) { Log 'server: world loaded'; return $true }
        }
    }
    Log 'server: FAILED: no "world loaded" in emf_core.log within 5 minutes'
    return $false
}

function Finish([bool]$ok, [string]$text) {
    Set-Content -Path $doneFile -Value ("{0} {1}" -f $(if ($ok) { 'ok' } else { 'failed' }), $text) -Encoding UTF8
    Log "done: $(if ($ok) { 'ok' } else { 'FAILED' }): $text"
}

Log "restart helper started; server folder: $(if ($serverDir) { if (Test-Path $serverExe) { 'found' } else { 'enshrouded_server.exe NOT found' } } else { 'not set' }); game app id $appId; chime: $(if (Test-Path $chimeSound) { Split-Path $chimeSound -Leaf } else { 'Windows exclamation sound' })"
while ($true) {
    if (Test-Path $chimeRequest) {
        Remove-Item $chimeRequest
        Log 'chime: Claude waits for you'
        Chime
    }
    if (Test-Path $request) {
        $what = ((Get-Content $request -Raw) -as [string]).Trim().ToLowerInvariant()
        Remove-Item $request
        if (Test-Path $doneFile) { Remove-Item $doneFile }
        Log "request: $what"
        try {
            switch ($what) {
                'client' { $ok = (Close-Client) -and (Start-Client); Finish $ok 'client restart' }
                { $_ -eq 'server' -or $_ -eq 'both' } {
                    $ok = (Close-Client) -and (Stop-Server) -and (Start-Server) -and (Start-Client)
                    Finish $ok 'client and server restart'
                }
                'stop' { Finish $true 'helper stopped'; exit 0 }
                default { Finish $false "unknown request '$what' (only client, server, both, stop)" }
            }
        } catch {
            Finish $false "error: $($_.Exception.Message)"
        }
    }
    if ((Get-Item $self).LastWriteTime -ne $selfTime) { Log 'restart helper: its script changed: starting again'; exit 10 }
    Start-Sleep -Seconds 2
}
