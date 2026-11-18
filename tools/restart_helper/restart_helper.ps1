# restart_helper.ps1: FlameKit's restart helper (started by restart_watch.cmd; leave its window open).
#
# Whenever a file restart.request appears in this folder, it does what the file asks, logs every step to restart.log
# and writes the result to restart.done ("ok <text>" or "failed <text>"). The request is one word, nothing else is
# ever run from it:
#   client  close the game client (like Alt+F4) and start it again through Steam
#   server  close the game client, have the server save its world, stop it and start it again, then start the client
#   both    the same as server
#   keygen  make FlameKit's release signing key once (ECDSA P-256) in this Windows user's key store, not exportable:
#           the private key never leaves this PC. Its public key goes to signing\public_key.txt (hex, BCRYPT_ECCPUBLIC_BLOB),
#           which the DLL carries (web_update.hpp) to check updates with
#   sign    sign signing\update.txt with that key (SHA-256, ECDSA P-256): the signature (64 bytes, hex) goes to
#           signing\update.sig, which is published next to the channel's update.txt
#   build   build FlameKit's DLL: ..\flamekit_native\build.cmd, its output in build.log and its result code in build.done
#   buildprobe   the same for ..\flamekit_server_probe (a test mod for the local server)
#           there (the same as build_watch.cmd, which is no longer needed)
#   installold, installnew  (0.15.124, the release packages) a test install into a scratch folder, never the game:
#           installtest\game (a fake dedicated server folder: an empty enshrouded_server.exe, so no save backup is made)
#           gets installtest\old\install.ps1 (the old FlameKit package) or installtest\new\install.ps1 (the new one),
#           -NoDesktopShortcut; the output goes to installtest\old.log or installtest\new.log
#   stop    stop this helper
# Whenever a file chime.request appears, it plays a chime: Claude is done and waits for the owner.
#
# Stopping the server: Ctrl+C cannot be sent to it reliably from another program, so FlameKit on the server saves the
# world on request (features/server_save.lua: save_now.request -> emf.request_save -> save_now.done). With the game
# client closed (no player connected), the server process is ended only once a save file newer than the request
# exists; without one within 90 s nothing is stopped and the request fails. The game client is never ended by force.
# The places are in restart_paths.txt next to this file (on this PC only; never in the public repository):
#   server_folder = <the local dedicated server's folder>
#   game_app_id = 1203620
#   chime_sound = <a .wav file>          (optional; default C:\Windows\Media\Alarm01.wav, else chimes.wav)
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
$appId = if ($cfg['game_app_id']) { $cfg['game_app_id'] } else { '1203620' }
# (owner 2026-11-18 07:56: "that command did work") the client starts through Steam's server connect, which opens the
# game with the test server's session ready to join; restart_paths.txt client_start_url overrides it
$clientUrl = if ($cfg['client_start_url']) { $cfg['client_start_url'] } else { 'steam://connect/127.0.0.1:15637' }
$chimeSound = if ($cfg['chime_sound']) { $cfg['chime_sound'] } elseif (Test-Path (Join-Path $env:WINDIR 'Media\Alarm01.wav')) { Join-Path $env:WINDIR 'Media\Alarm01.wav' } else { Join-Path $env:WINDIR 'Media\chimes.wav' }

# The game's own window: the process also has FlameKit's overlay window (class FlameKitOverlay), which ignores a
# close, so the close goes to the game's largest visible window of another class.
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class FkWindows {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    struct RECT { public int L, T, R, B; }
    public static IntPtr GameWindow(uint pid) {
        IntPtr best = IntPtr.Zero;
        long bestArea = -1;
        EnumWindows((h, l) => {
            uint p;
            GetWindowThreadProcessId(h, out p);
            if (p != pid || !IsWindowVisible(h)) return true;
            var c = new StringBuilder(256);
            GetClassName(h, c, 256);
            if (c.ToString() == "FlameKitOverlay") return true;
            RECT r;
            GetWindowRect(h, out r);
            long area = (long)(r.R - r.L) * (r.B - r.T);
            if (area > bestArea) { bestArea = area; best = h; }
            return true;
        }, IntPtr.Zero);
        return best;
    }
}
"@
$serverExe = if ($serverDir) { Join-Path $serverDir 'enshrouded_server.exe' } else { $null }
$emfLog = if ($serverDir) { Join-Path $serverDir 'emf\emf_core.log' } else { $null }
$saveDir = if ($serverDir) { Join-Path $serverDir 'savegame' } else { $null }
$modDir = if ($serverDir) { Join-Path $serverDir 'emf\mods\flamekit' } else { $null }

function Chime {
    try {
        if (Test-Path $chimeSound) {
            $player = New-Object System.Media.SoundPlayer $chimeSound
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
    $win = [FkWindows]::GameWindow([uint32]$p.Id)
    if ($win -eq [IntPtr]::Zero) { Log 'client: FAILED: its window was not found'; return $false }
    [FkWindows]::PostMessage($win, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null  # WM_CLOSE
    if (-not $p.WaitForExit(90000)) { Log 'client: FAILED: still running after 90 s (left running)'; return $false }
    Log 'client: closed'
    Start-Sleep -Seconds 3  # Steam notes the game ended before it is started again
    return $true
}

function Wait-ForServer {
    Log 'server: waiting 30 s for it to finish coming up before the client starts'
    Start-Sleep -Seconds 30
    return $true
}

function Start-Client {
    Log "client: starting through Steam ($clientUrl)"
    Start-Process $clientUrl
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

function Build([string]$folder = 'flamekit_native') {
    # (2026-11-17) 'buildprobe' builds ..\flamekit_server_probe (a test mod for the local server) the same way
    $dir = Join-Path (Split-Path -Parent $here) $folder
    if (-not (Test-Path (Join-Path $dir 'build.cmd'))) { Log "build: FAILED: build.cmd not found in $dir"; return $false }
    $doneB = Join-Path $dir 'build.done'
    if (Test-Path $doneB) { Remove-Item $doneB }
    Log "build: building $folder"
    # Not Start-Process -Wait: that also waits for the compiler's helper (mspdbsrv.exe), which stays running for minutes
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', 'call build.cmd > build.log 2>&1' -WorkingDirectory $dir -WindowStyle Hidden -PassThru
    if (-not $p.WaitForExit(600000)) { Log 'build: FAILED: not done after 10 minutes'; return $false }
    Set-Content -Path $doneB -Value $p.ExitCode -Encoding ASCII
    Log "build: $(if ($p.ExitCode -eq 0) { 'OK' } else { "FAILED with code $($p.ExitCode) (see build.log)" })"
    return $p.ExitCode -eq 0
}

$keyName = 'FlameKit release signing'
$signDir = Join-Path $here 'signing'

function Release-Key([bool]$create) {
    if ([System.Security.Cryptography.CngKey]::Exists($keyName)) { return [System.Security.Cryptography.CngKey]::Open($keyName) }
    if (-not $create) { return $null }
    $p = New-Object System.Security.Cryptography.CngKeyCreationParameters
    $p.ExportPolicy = [System.Security.Cryptography.CngExportPolicies]::None
    $p.KeyUsage = [System.Security.Cryptography.CngKeyUsages]::Signing
    Log 'keygen: making the release signing key (ECDSA P-256, in this user''s key store, not exportable)'
    return [System.Security.Cryptography.CngKey]::Create([System.Security.Cryptography.CngAlgorithm]::ECDsaP256, $keyName, $p)
}

function Keygen {
    $k = Release-Key $true
    if (-not (Test-Path $signDir)) { New-Item -ItemType Directory -Path $signDir | Out-Null }
    $blob = $k.Export([System.Security.Cryptography.CngKeyBlobFormat]::EccPublicBlob)
    Set-Content -Path (Join-Path $signDir 'public_key.txt') -Value (($blob | ForEach-Object { $_.ToString('x2') }) -join '') -Encoding ASCII -NoNewline
    Log "keygen: public key written to signing\public_key.txt ($($blob.Length) bytes)"
    return $true
}

function Sign {
    $k = Release-Key $false
    if (-not $k) { Log 'sign: FAILED: there is no release signing key yet (request keygen first)'; return $false }
    $file = Join-Path $signDir 'update.txt'
    if (-not (Test-Path $file)) { Log 'sign: FAILED: signing\update.txt is missing'; return $false }
    $ecdsa = New-Object System.Security.Cryptography.ECDsaCng($k)
    $ecdsa.HashAlgorithm = [System.Security.Cryptography.CngAlgorithm]::Sha256
    $sig = $ecdsa.SignData([System.IO.File]::ReadAllBytes($file))
    Set-Content -Path (Join-Path $signDir 'update.sig') -Value (($sig | ForEach-Object { $_.ToString('x2') }) -join '') -Encoding ASCII -NoNewline
    Log "sign: signing\update.txt signed ($($sig.Length) bytes)"
    return $true
}

function Install-Test([string]$which) {
    $t = Join-Path $here 'installtest'
    $game = Join-Path $t 'game'
    $script = Join-Path $t "$which\install.ps1"
    if (-not (Test-Path (Join-Path $game 'enshrouded_server.exe'))) { Log "install${which}: FAILED: installtest\game\enshrouded_server.exe is missing"; return $false }
    if (-not (Test-Path $script)) { Log "install${which}: FAILED: installtest\$which\install.ps1 is missing"; return $false }
    $out = Join-Path $t "$which.log"
    Log "install${which}: installtest\$which\install.ps1 into installtest\game"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Game $game -NoDesktopShortcut *> $out
    $code = $LASTEXITCODE
    Log "install${which}: exit code $code (installtest\$which.log)"
    return $code -eq 0
}

# (owner, 2026-11-15: "I'm going to give you direct access to upload to the production FTP folder") 'upload' runs the
# FTP tool's own upload.ps1 (<work folder>\release\FlameKit FTP tool): it uploads the outbox to the production server's
# FlameKit folder, mod.json last, and fetches the server's logs into outbox\server_log. The password stays encrypted in
# that folder (DPAPI, this Windows user): this helper only starts the script and logs what it prints, never the password.
function Upload([switch]$List, [switch]$LogsOnly) {
    $tool = Join-Path (Split-Path -Parent $here) 'release\FlameKit FTP tool\upload.ps1'
    if (-not (Test-Path $tool)) { Log "upload: FAILED: $tool not found"; return $false }
    Log 'upload: starting the FTP tool'
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tool)
    if ($List) { $args2 += '-List' }
    if ($LogsOnly) { $args2 += '-LogsOnly' }
    $out = & powershell @args2 2>&1
    $code = $LASTEXITCODE
    foreach ($line in $out) { Log "upload: $line" }
    if ($code -ne 0) { Log "upload: FAILED (exit code $code)"; return $false }
    return $true
}

function Finish([bool]$ok, [string]$text) {
    Set-Content -Path $doneFile -Value ("{0} {1}" -f $(if ($ok) { 'ok' } else { 'failed' }), $text) -Encoding UTF8
    Log "done: $(if ($ok) { 'ok' } else { 'FAILED' }): $text"
}

Log "restart helper started; server folder: $(if ($serverDir) { if (Test-Path $serverExe) { 'found' } else { 'enshrouded_server.exe NOT found' } } else { 'not set' }); game app id $appId; chime: $(if (Test-Path $chimeSound) { Split-Path $chimeSound -Leaf } else { 'Windows exclamation sound' })"
# (owner, 2026-11-15) every night at 3:55 (this PC's time; G-Portal restarts the production server at about 4:10, and
# emf_core.log starts anew then) the production logs are fetched, nothing uploaded. Needs this PC on and this window open.
$nightlyDone = ''
while ($true) {
    $now = Get-Date
    if ($now.Hour -eq 3 -and $now.Minute -ge 55 -and $nightlyDone -ne $now.ToString('yyyy-MM-dd')) {
        $nightlyDone = $now.ToString('yyyy-MM-dd')
        Log 'nightly: fetching the production logs before the server restart'
        try { $null = Upload -LogsOnly } catch { Log "nightly: error: $($_.Exception.Message)" }
    }
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
                    # (owner 2026-11-18 09:23/09:25) the client loads faster now than the server comes up: wait 30 s after
                    # "world loaded" before starting the client
                    $ok = (Close-Client) -and (Stop-Server) -and (Start-Server) -and (Wait-ForServer) -and (Start-Client)
                    Finish $ok 'client and server restart'
                }
                'build' { $ok = Build; Finish $ok 'build' }
                'buildprobe' { $ok = Build 'flamekit_server_probe'; Finish $ok 'buildprobe' }
                'keygen' { $ok = Keygen; Finish $ok 'keygen' }
                'sign' { $ok = Sign; Finish $ok 'sign' }
                'installold' { $ok = Install-Test 'old'; Finish $ok 'installold' }
                'installnew' { $ok = Install-Test 'new'; Finish $ok 'installnew' }
                'upload' { $ok = Upload; Finish $ok 'upload' }
                'ftplist' { $ok = Upload -List; Finish $ok 'ftplist' }
                'stop' { Finish $true 'helper stopped'; exit 0 }
                default { Finish $false "unknown request '$what' (only client, server, both, build, buildprobe, keygen, sign, installold, installnew, upload, ftplist, stop)" }
            }
        } catch {
            Finish $false "error: $($_.Exception.Message)"
        }
    }
    if ((Get-Item $self).LastWriteTime -ne $selfTime) { Log 'restart helper: its script changed: starting again'; exit 10 }
    Start-Sleep -Seconds 2
}
