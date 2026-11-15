# upload.ps1 (FlameKit FTP tool): uploads what Claude left in the outbox to the production server, then fetches the
# server's log back into the outbox so Claude can check the reload. The owner runs it (upload.cmd); this folder is not
# connected to Claude, so Claude can neither change this script nor use the password. It only ever writes into the
# server's FlameKit folder (ftp.txt mod_dir), mod.json last, and reads the log (log_path). It never deletes on the server.
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
    $logDir = Join-Path $out 'server_log'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $resp = (Req $s.log_path ([System.Net.WebRequestMethods+Ftp]::DownloadFile)).GetResponse()
    $fs = [System.IO.File]::Create((Join-Path $logDir 'emf_core.log')); $resp.GetResponseStream().CopyTo($fs); $fs.Close(); $resp.Close()
    $last = Select-String -Path (Join-Path $logDir 'emf_core.log') -Pattern 'Lua mod flamekit reloaded' | Select-Object -Last 1
    Write-Host "Server log fetched. Last reload: $(if ($last) { $last.Line } else { 'none found (restart the server once)' })"
}
