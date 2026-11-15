# upload.ps1 (FlameKit FTP tool): uploads what Claude left in the outbox to the production server, then fetches the
# server's log back into the outbox so Claude can check the reload. The owner runs it (upload.cmd), or (owner,
# 2026-11-15) Claude through the restart helper's 'upload' request. The password stays encrypted for the owner's Windows
# user (ftp_password.dat, DPAPI): it is never shown or logged, and Claude never opens that file. It only ever writes into the
# server's FlameKit folder (ftp.txt mod_dir), mod.json last, and reads the log (log_path). It never deletes on the server.
param([switch]$List)  # (2026-11-15) -List: also writes what is on the FTP (names, sizes, dates) to production_stable_logs\ftp_list.txt
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$conf = Join-Path $here 'ftp.txt'
$pass = Join-Path $here 'ftp_password.dat'
if (-not (Test-Path $conf) -or -not (Test-Path $pass)) { throw 'Run ftp_setup.cmd first.' }
$s = @{ port = '21'; tls = 'no' }
foreach ($line in Get-Content $conf) { if ($line -match '^\s*([a-z_]+)\s*=\s*(.*?)\s*$') { $s[$Matches[1]] = $Matches[2] } }
$pw = (Get-Content $pass -Raw).Trim() | ConvertTo-SecureString
function Req([string]$path, [string]$method) {
    $r = [System.Net.FtpWebRequest]::Create("ftp://$($s.host):$($s.port)/" + ($path.TrimStart('/') -replace '\\', '/'))
    $r.Method = $method
    $r.Credentials = New-Object System.Net.NetworkCredential($s.user, $pw)
    $r.EnableSsl = $s.tls -eq 'yes'
    $r.UsePassive = $true; $r.UseBinary = $true; $r.KeepAlive = $false; $r.Timeout = 30000
    return $r
}
$out = $s.outbox
# (owner, 2026-11-15) the production server's logs go to <work folder>\production_stable_logs, beside the outbox (not in it,
# so they can never be uploaded); ftp.txt logs = <folder> changes it
$logRoot = if ($s.logs) { $s.logs } else { Join-Path (Split-Path -Parent $out) 'production_stable_logs' }
$files = @()
if (Test-Path $out) { $files = @(Get-ChildItem $out -Recurse -File | Where-Object { $_.FullName -notlike (Join-Path $out 'server_log\*') } |
    Sort-Object { $_.Name -ieq 'mod.json' -and $_.DirectoryName -ieq $out }) }
if (-not $files.Count) { Write-Host 'The outbox is empty: nothing to upload.' }
foreach ($f in $files) {
    $rel = $f.FullName.Substring($out.Length).TrimStart('\') -replace '\\', '/'
    $dir = ($rel -replace '/[^/]*$', '')
    if ($dir -ne $rel) {
        $acc = $s.mod_dir.TrimEnd('/')
        foreach ($part in $dir.Split('/')) { $acc = "$acc/$part"; try { (Req $acc ([System.Net.WebRequestMethods+Ftp]::MakeDirectory)).GetResponse().Close() } catch { } }
    }
    $r = Req ($s.mod_dir.TrimEnd('/') + '/' + $rel) ([System.Net.WebRequestMethods+Ftp]::UploadFile)
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $r.ContentLength = $bytes.Length
    $st = $r.GetRequestStream(); $st.Write($bytes, 0, $bytes.Length); $st.Close(); $r.GetResponse().Close()
    Write-Host "uploaded $rel ($($bytes.Length) bytes)"
    Remove-Item $f.FullName -Force
}
if ($files.Count) { Write-Host "Done: $($files.Count) file(s) on the server. Waiting 15 s for EMF to reload FlameKit..."; Start-Sleep -Seconds 15 }
if ($s.log_path) {
    $logDir = $logRoot
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $resp = (Req $s.log_path ([System.Net.WebRequestMethods+Ftp]::DownloadFile)).GetResponse()
    $fs = [System.IO.File]::Create((Join-Path $logDir 'emf_core.log')); $resp.GetResponseStream().CopyTo($fs); $fs.Close(); $resp.Close()
    $last = Select-String -Path (Join-Path $logDir 'emf_core.log') -Pattern 'Lua mod flamekit reloaded' | Select-Object -Last 1
    Write-Host "Server log fetched. Last reload: $(if ($last) { $last.Line } else { 'none found (restart the server once)' })"
}
# (owner, 2026-11-14) also the game server's own log (its step times and "Bad Performance" lines): ftp.txt game_log_path,
# else the usual places are tried; the one that worked is said
$tries = @()
if ($s.game_log_path) { $tries += $s.game_log_path }
$tries += '/logs/enshrouded_server.log', '/enshrouded_server.log', '/log/enshrouded_server.log'
$got = $false
foreach ($p in $tries) {
    try {
        $resp = (Req $p ([System.Net.WebRequestMethods+Ftp]::DownloadFile)).GetResponse()
        $logDir = $logRoot
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        $fs = [System.IO.File]::Create((Join-Path $logDir 'enshrouded_server.log')); $resp.GetResponseStream().CopyTo($fs); $fs.Close(); $resp.Close()
        Write-Host "Game server log fetched ($p)."
        $got = $true
        break
    } catch { }
}
if (-not $got) { Write-Host 'The game server log (enshrouded_server.log) was not found: tell Claude where it is on the FTP.' }

# (owner, 2026-11-15: "all the relevant logs you need to check for bugs and problems, including performance") What the
# FTP list showed (2026-11-15) besides the two logs above:
# - /emf/emf_loader.log: how EMF itself was loaded (a failed load shows here first)
# - /logs/<date>.eml.log: EML, the other mod loader on this server (EMF leaves its content alone)
# Not fetched: /logs/stats_log.txt, connection_log*.txt and the system*.txt files are the Steam client's own logs (its
# login and achievements), nothing about the game; player connection quality (ping, loss) is in enshrouded_server.log
# ("m#1(...)" lines every 30 s).
# - /logs/backup/enshrouded_server_<time>.log: the game server log of the run before the last restart (the server
#   starts a new log on every start, G-Portal restarts it every night at about 04:10): the newest one is fetched once
# - /crash_dumps/<name>/enshrouded_server.dmp: a crash of the game server: the newest one is fetched once
# emf_core.log is started anew on every server start and has no backup: what happened before a restart is only in a
# copy fetched before it. Never fetched: the save game, the snapshots, the world files, emf/config (player names).
function List-Dir([string]$dir) {
    $items = @()
    try {
        $resp = (Req $dir ([System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails)).GetResponse()
        $rd = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $text = $rd.ReadToEnd(); $rd.Close(); $resp.Close()
    } catch { return $items }
    foreach ($l in ($text -split "`r?`n")) {
        if ($l -match '^([d\-l])[rwxst\-]{9}\s+\S+\s+\S+\s+\S+\s+(\d+)\s+\w{3}\s+\d+\s+[\d:]+\s+(.+)$') {
            $items += [pscustomobject]@{ name = $Matches[3]; dir = ($Matches[1] -eq 'd'); size = [int64]$Matches[2] }
        } elseif ($l -match '^\S+\s+\S+\s+(<DIR>|\d+)\s+(.+)$') {
            $items += [pscustomobject]@{ name = $Matches[2]; dir = ($Matches[1] -eq '<DIR>'); size = $(if ($Matches[1] -eq '<DIR>') { 0 } else { [int64]$Matches[1] }) }
        }
    }
    return $items
}
function Fetch([string]$remote, [string]$local, [int64]$size = -1) {
    $logDir = $logRoot
    $path = Join-Path $logDir $local
    if ($size -ge 0 -and (Test-Path $path) -and (Get-Item $path).Length -eq $size) { return }  # already here, unchanged
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    try {
        $resp = (Req $remote ([System.Net.WebRequestMethods+Ftp]::DownloadFile)).GetResponse()
        $fs = [System.IO.File]::Create($path); $resp.GetResponseStream().CopyTo($fs); $fs.Close(); $resp.Close()
        Write-Host "fetched $remote ($((Get-Item $path).Length) bytes)"
    } catch { Write-Host "could not fetch ${remote}: $($_.Exception.Message)" }
}
$emfDir = (Split-Path $s.log_path -Parent) -replace '\\', '/'
if ($emfDir) { Fetch ($emfDir.TrimEnd('/') + '/emf_loader.log') 'emf_loader.log' }
$logs = List-Dir '/logs'
$eml = $logs | Where-Object { -not $_.dir -and $_.name -like '*.eml.log' } | Sort-Object name | Select-Object -Last 1
if ($eml) { Fetch "/logs/$($eml.name)" 'eml.log' }
$bk = List-Dir '/logs/backup' | Where-Object { -not $_.dir -and $_.name -like 'enshrouded_server_*.log' } | Sort-Object name | Select-Object -Last 1
if ($bk) { Fetch "/logs/backup/$($bk.name)" "backup\$($bk.name)" $bk.size; Write-Host "game server log before the last restart: backup\$($bk.name)" }
$dump = List-Dir '/crash_dumps' | Where-Object { $_.dir } | Sort-Object name | Select-Object -Last 1
if ($dump) {
    foreach ($f in (List-Dir "/crash_dumps/$($dump.name)")) {
        if (-not $f.dir) { Fetch "/crash_dumps/$($dump.name)/$($f.name)" "crash_dumps\$($dump.name)\$($f.name)" $f.size }
    }
    Write-Host "newest server crash dump: $($dump.name)"
}

# (owner, 2026-11-15: "make sure the upload script is downloading all the relevant logs") -List: every folder and file
# on the FTP (names, sizes, dates only; nothing is downloaded or changed), at most 5 folders deep and 4000 lines, into
# production_stable_logs\ftp_list.txt, so Claude can see which logs exist
if ($List) {
    $lines = New-Object System.Collections.Generic.List[string]
    function Walk([string]$dir, [int]$depth) {
        if ($depth -gt 5 -or $lines.Count -ge 4000) { return }
        try {
            $resp = (Req $dir ([System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails)).GetResponse()
            $rd = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $text = $rd.ReadToEnd(); $rd.Close(); $resp.Close()
        } catch { $lines.Add("$dir  (cannot list: $($_.Exception.Message))"); return }
        foreach ($l in ($text -split "`r?`n")) {
            if (-not $l.Trim()) { continue }
            $isDir = $false; $name = $null
            if ($l -match '^([d\-l])[rwxst\-]{9}\s+\S+\s+\S+\s+\S+\s+(\d+)\s+(\w{3}\s+\d+\s+[\d:]+)\s+(.+)$') {
                $isDir = $Matches[1] -eq 'd'; $name = $Matches[4]; $info = "$($Matches[2]) bytes, $($Matches[3])"
            } elseif ($l -match '^(\S+\s+\S+)\s+(<DIR>|\d+)\s+(.+)$') {
                $isDir = $Matches[2] -eq '<DIR>'; $name = $Matches[3]; $info = if ($isDir) { $Matches[1] } else { "$($Matches[2]) bytes, $($Matches[1])" }
            } else { $lines.Add("$dir  ? $l"); continue }
            if ($name -eq '.' -or $name -eq '..') { continue }
            $path = ($dir.TrimEnd('/') + '/' + $name)
            if ($isDir) { $lines.Add("$path/"); Walk $path ($depth + 1) } else { $lines.Add("$path  ($info)") }
            if ($lines.Count -ge 4000) { $lines.Add('... (stopped at 4000 lines)'); return }
        }
    }
    Walk '/' 0
    $logDir = $logRoot
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    Set-Content -Path (Join-Path $logDir 'ftp_list.txt') -Value $lines -Encoding UTF8
    Write-Host "FTP list written: $($lines.Count) lines (production_stable_logs\ftp_list.txt)."
}
