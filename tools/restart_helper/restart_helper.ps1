# restart_helper.ps1: FlameKit's restart helper (started by restart_watch.cmd; leave its window open).
#
# Whenever a file restart.request appears in this folder, it does what the file asks, logs every step to restart.log
# and writes the result to restart.done ("ok <text>" or "failed <text>"). The request is one word, nothing else is
# ever run from it:
#   client  close the game client (like Alt+F4) and start it again through Steam
#   server  stop the local dedicated server with Ctrl+C (it saves the world first), start it again, wait for its world
#   both    close the game client, restart the server, then start the game client
#   stop    stop this helper
# Nothing is ever killed by force: a program that does not close within its time is left running and the request
# fails. The places are in restart_paths.txt next to this file (on this PC only; never in the public repository):
#   server_folder = <the local dedicated server's folder>
#   game_app_id = 1203220
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
$request = Join-Path $here 'restart.request'
$doneFile = Join-Path $here 'restart.done'
$logFile = Join-Path $here 'restart.log'

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
$serverExe = if ($serverDir) { Join-Path $serverDir 'enshrouded_server.exe' } else { $null }
$emfLog = if ($serverDir) { Join-Path $serverDir 'emf\emf_core.log' } else { $null }
$saveDir = if ($serverDir) { Join-Path $serverDir 'savegame' } else { $null }

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
    $before = Newest-Save
    Log "server: sending Ctrl+C (process $($p.Id)); newest save before: $(if ($before) { '{0} {1:HH:mm:ss}' -f $before.Name, $before.LastWriteTime } else { 'none found' })"
    $c = Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $here 'ctrl_c.ps1'), $p.Id) -WindowStyle Hidden -Wait -PassThru
    if ($c.ExitCode -ne 0) { Log "server: FAILED: Ctrl+C could not be sent (code $($c.ExitCode))"; return $false }
    if (-not $p.WaitForExit(120000)) { Log 'server: FAILED: still running 120 s after Ctrl+C (left running)'; return $false }
    $after = Newest-Save
    $saved = $after -and (-not $before -or $after.LastWriteTime -gt $before.LastWriteTime)
    Log "server: stopped; newest save after: $(if ($after) { '{0} {1:HH:mm:ss}' -f $after.Name, $after.LastWriteTime } else { 'none found' }) ($(if ($saved) { 'saved on stop' } else { 'NOT newer than before' }))"
    return $true
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

Log "restart helper started; server folder: $(if ($serverDir) { if (Test-Path $serverExe) { 'found' } else { 'enshrouded_server.exe NOT found' } } else { 'not set' }); game app id $appId"
while ($true) {
    if (Test-Path $request) {
        $what = ((Get-Content $request -Raw) -as [string]).Trim().ToLowerInvariant()
        Remove-Item $request
        if (Test-Path $doneFile) { Remove-Item $doneFile }
        Log "request: $what"
        try {
            switch ($what) {
                'client' { $ok = (Close-Client) -and (Start-Client); Finish $ok 'client restart' }
                'server' { $ok = (Stop-Server) -and (Start-Server); Finish $ok 'server restart' }
                'both' {
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
    Start-Sleep -Seconds 2
}
