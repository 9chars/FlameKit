# ftp_setup.ps1 (FlameKit FTP tool): how upload.cmd reaches the production server by FTP (it uploads Claude's outbox and
# fetches the server's log). Run ftp_setup.cmd once, and again when the server's FTP details change. The password is
# typed here and
# kept in ftp_password.dat, encrypted for this Windows user (Windows DPAPI): only this user on this PC can read it, and
# it is never shown, logged or sent anywhere but to the FTP server. ftp.txt keeps the rest (no password) and can be
# edited by hand. Neither file is ever put in the repository.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$conf = Join-Path $here 'ftp.txt'
$old = @{}
if (Test-Path $conf) { foreach ($l in Get-Content $conf) { if ($l -match '^\s*([a-z_]+)\s*=\s*(.*?)\s*$') { $old[$Matches[1]] = $Matches[2] } } }
function Ask([string]$key, [string]$question, [string]$default) {
    if ($old[$key]) { $default = $old[$key] }
    $a = Read-Host "$question$(if ($default) { " [$default]" })"
    if (-not $a) { $a = $default }
    return $a
}
Write-Host "FTP details of the production server (G-Portal's FTP page has them). Press Enter to keep the value in [ ]."
$h = Ask 'host' 'Server address (host name or IP, without ftp://)' ''
$p = Ask 'port' 'Port' '21'
$u = Ask 'user' 'User name' ''
$t = Ask 'tls' 'Use FTPS (encrypted)? yes or no' 'no'
$m = Ask 'mod_dir' "Path of the server's FlameKit folder, from the FTP login (for example /emf/mods/flamekit)" '/emf/mods/flamekit'
$g = Ask 'log_path' "Path of the server's emf_core.log, from the FTP login" '/emf/emf_core.log'
$o = Ask 'outbox' 'The outbox folder on this PC where Claude leaves the files' 'C:\enshrouded mod shit\outbox'
$passFile = Join-Path $here 'ftp_password.dat'
$pw = Read-Host $(if (Test-Path $passFile) { 'Password (not shown; press Enter to keep the saved one)' } else { 'Password (not shown)' }) -AsSecureString
if ($pw.Length -eq 0 -and (Test-Path $passFile)) { $pw = (Get-Content $passFile -Raw).Trim() | ConvertTo-SecureString }  # keep the saved one
Set-Content -Path $conf -Encoding ASCII -Value @("host = $h", "port = $p", "user = $u", "tls = $t", "mod_dir = $m", "log_path = $g", "outbox = $o")
Set-Content -Path $passFile -Encoding ASCII -Value (ConvertFrom-SecureString $pw)
# a quick look: list the FlameKit folder
try {
    $r = [System.Net.FtpWebRequest]::Create("ftp://${h}:$p/" + $m.TrimStart('/'))
    $r.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails  # LIST: G-Portal's FTP has no NLST (502)
    $r.Credentials = New-Object System.Net.NetworkCredential($u, $pw)
    $r.EnableSsl = $t -eq 'yes'
    $r.UsePassive = $true
    $resp = $r.GetResponse()
    $names = (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd()
    $resp.Close()
    Write-Host ''
    Write-Host 'Connected. The FlameKit folder on the server holds:'
    Write-Host $names
    if ($names -notmatch 'mod\.json') { Write-Host 'WARNING: no mod.json there: check the folder path and run this again.' }
} catch {
    Write-Host ''
    Write-Host "Could not connect: $($_.Exception.Message)"
    Write-Host 'Check the details and run ftp_setup.cmd again.'
}
