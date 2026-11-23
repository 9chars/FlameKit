# Removes EMF from the game folder: EMF's dinput8.dll and the emf folder, and the desktop shortcut install.cmd made.
# Your settings (emf\config and emf\emf_core.ini) and mod profiles (emf\profiles) stay unless -All. Another mod's
# dinput8.dll that EMF renamed (emf\moved.txt) is put back, and so is EML's dbghelp.dll that EMF.exe set aside ("Let
# EMF load EML content").
# EMF.exe's Nexus API key and downloads (%LOCALAPPDATA%\EMF) and its saved nxm:// setting (HKCU\Software\EMF\NxmBackup)
# stay unless -All; the saved setting also stays while a copy of EMF still opens nxm:// links (it needs it to give them
# back). When this folder's EMF.exe opens nxm:// links, it gives them back first.
#   uninstall.cmd                              finds the game through Steam
#   uninstall.cmd "D:\Games\Enshrouded" -All   also removes the settings
# -All refuses while the companion still holds gear you gave it: those items exist only in its file under
# emf\config\companion. Take them back in game first (the order wheel key, F6 by default, then Gear), or add -Force
# to delete them anyway.
# Your world saves are not touched (they live in Saved Games, not in the game folder). The save backups EMF made
# (%LOCALAPPDATA%\EMF\save-backups) always stay, also with -All: delete that folder yourself if you do not want them.
param(
    [string]$Game = "",
    [switch]$All,
    [switch]$Force,
    [string]$SteamRoot = ""
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "emf_common.ps1")

if (-not $Game) {
    $Game = Find-EnshroudedDir $SteamRoot
    if (-not $Game) { throw "could not find Enshrouded through Steam; drag the game folder (the one with enshrouded.exe) onto uninstall.cmd" }
}
$Game = (Resolve-Path -LiteralPath $Game).Path
if (-not (Test-GameFolder $Game)) {
    throw "no enshrouded.exe or enshrouded_server.exe in $Game; uninstall only works on the game's or a server's folder"
}
$running = Get-GameRunning $Game
if ($running) { throw $running }
$emf = Join-Path $Game "emf"
if ($All -and -not $Force) {
    $held = 0
    $dir = Join-Path $emf "config\companion"
    if (Test-Path -LiteralPath $dir) {
        foreach ($f in Get-ChildItem -LiteralPath $dir -Filter *.txt -File) {
            $held += @(Get-Content -LiteralPath $f.FullName | Where-Object { $_ -match '^piece ' }).Count
        }
    }
    if ($held -gt 0) {
        throw ("the companion still holds $held gear piece(s) you gave it; they exist only in emf\config\companion and " +
               "would be lost. Take them back in game first (the companion's wheel key, F6 by default, then Gear), or run: " +
               "uninstall.cmd -All -Force")
    }
}
$removed = @()
$proxy = Join-Path $Game "dinput8.dll"
if (Test-Path -LiteralPath $proxy) {
    if (Test-EmfLoader $proxy) { Remove-Item -LiteralPath $proxy -Force; $removed += "dinput8.dll" }
    else { "left $proxy alone (it is not EMF's)" }
}
$keep = @("config", "emf_core.ini", "profiles", "backup", "installed_mods")  # settings, mod profiles; EMF.exe's backups and install records
# When this folder's EMF.exe opens Nexus's Mod Manager Download links (nxm://, the player's opt-in in EMF.exe), it gives
# them back to the program that had them before (Vortex, Mod Organizer 2), while it is still there to do it.
# (The package test points these at a scratch key with EMF_TEST_REGISTRY_ROOT, never at the player's.)
$registryRoot = if ($env:EMF_TEST_REGISTRY_ROOT) { $env:EMF_TEST_REGISTRY_ROOT } else { "HKCU:\Software" }
$nxmCommandKey = "$registryRoot\Classes\nxm\shell\open\command"
$app = Join-Path $emf "EMF.exe"
$nxmCommand = (Get-ItemProperty -LiteralPath $nxmCommandKey -ErrorAction SilentlyContinue).'(default)'
if ($nxmCommand -and (Test-Path -LiteralPath $app) -and $nxmCommand.StartsWith('"' + $app + '"', [System.StringComparison]::OrdinalIgnoreCase)) {
    $release = Start-Process -FilePath $app -ArgumentList "--release-nxm" -PassThru
    if (-not $release.WaitForExit(15000)) { $release.Kill() }
    $after = (Get-ItemProperty -LiteralPath $nxmCommandKey -ErrorAction SilentlyContinue).'(default)'
    if ($after -and $after.StartsWith('"' + $app + '"', [System.StringComparison]::OrdinalIgnoreCase)) {
        "EMF.exe still opens nxm:// links and could not give them back: open Vortex or Mod Organizer 2 to take them, or delete HKCU\Software\Classes\nxm"
    } else {
        "gave Nexus's Mod Manager Download links (nxm://) back to the program that had them before EMF"
    }
}
# The desktop shortcut install.cmd made (emf\desktop_shortcut.txt), and only while it still points to this EMF.exe:
# never one the player made or changed. When the recorded one is gone (the desktop moved, OneDrive), the one EMF names
# on the current desktop that opens this EMF.exe. A problem here is said; the uninstall goes on.
try {
    foreach ($line in @(Read-Lines (Join-Path $Game $script:ShortcutRecord))) {
        if ($line -notlike "made`t*") { continue }
        $lnk = $line.Substring(5)
        if (-not (Test-Path -LiteralPath $lnk)) {
            $desk = Get-DesktopFolder
            $lnk = ""
            if ($desk) {
                foreach ($name in @("EMF.lnk", "EMF (server).lnk")) {
                    $here = Join-Path $desk $name
                    if ((Test-Path -LiteralPath $here) -and (Get-ShortcutTarget $here) -ieq $app) { $lnk = $here }
                }
            }
            if (-not $lnk) { continue }
        }
        if ((Get-ShortcutTarget $lnk) -ieq $app) {
            try {
                Remove-Item -LiteralPath $lnk -Force
                "removed the desktop shortcut EMF made ($lnk)"
            } catch {
                "could not remove the desktop shortcut $lnk ($($_.Exception.Message)): delete it yourself"
            }
        } else {
            "left the desktop shortcut $lnk alone: it no longer points to this folder's EMF.exe"
        }
    }
} catch {
    "could not read emf\desktop_shortcut.txt ($($_.Exception.Message)): delete EMF's desktop shortcut yourself"
}
# Other mods' dinput8.dll that the installer renamed: the newest goes back to its name, its chain line goes. Only one
# file can be dinput8.dll: the others stay renamed (and are named in the output); the record of them is kept.
$movedRecord = Join-Path $emf "moved.txt"
$recordLines = @(Read-Lines $movedRecord)
$createdChain = @($recordLines | Where-Object { $_ -like "created`t*" }).Count -gt 0
$left = @()
$listed = @(Get-ChainEntries $Game)
$movedNames = @($recordLines | Where-Object { $_ -like "moved`t*" } | ForEach-Object { $_.Substring(6) })
[array]::Reverse($movedNames)
foreach ($name in $movedNames) {
    $at = Join-Path $Game $name
    if (-not (Test-Path -LiteralPath $at)) {
        Remove-ChainEntry $Game $name $createdChain
        "$name (renamed by EMF) is gone; its line is taken out of $($script:ChainFileName)"
        continue
    }
    if (Test-Path -LiteralPath $proxy) {
        $why = if ($listed -contains $name) { "it stays listed in $($script:ChainFileName)" } else { "it was not started" }
        "left $name renamed: only one file can be dinput8.dll ($why)"
        $left += "moved`t$name"
        continue
    }
    Move-Item -LiteralPath $at -Destination $proxy
    Remove-ChainEntry $Game $name $createdChain
    "put $name back as dinput8.dll"
}
# EMF is going: nothing reads [EMF] any more. What is left there (DLLs that stay renamed, a player's lines) goes to
# [Chain], where the chain loader that is dinput8.dll again reads it.
$toChain = @(Move-EmfEntriesToChain $Game)
if ($toChain.Count) { "moved $($toChain -join ', ') from [EMF] to [Chain] in $($script:ChainFileName), where other chain loaders read them" }
# EML's dbghelp.dll that EMF.exe set aside ("set-aside<TAB><name><TAB>dbghelp.dll", app/bridge_content.cpp) goes back to
# its name, unless a dbghelp.dll is there again: then it stays set aside, and so does the record of it. Only the names
# EMF.exe gives it (eml-dbghelp.dll, eml-dbghelp-2.dll, ...): a hand-edited record never moves another file.
$aside = @()
foreach ($line in @($recordLines | Where-Object { $_ -like "set-aside`t*" })) {
    $parts = $line.Split("`t")
    if ($parts.Count -ne 3 -or $parts[2] -ne "dbghelp.dll" -or $parts[1] -notmatch '^eml-dbghelp(-\d+)?\.dll$') { continue }
    $at = Join-Path $Game $parts[1]
    if (-not (Test-Path -LiteralPath $at -PathType Leaf)) { continue }
    $to = Join-Path $Game "dbghelp.dll"
    if (Test-Path -LiteralPath $to) {
        "left $($parts[1]) (EML's dbghelp.dll, set aside by EMF.exe) as it is: there is a dbghelp.dll in the game folder again"
        $aside += $line
        continue
    }
    Move-Item -LiteralPath $at -Destination $to
    "put $($parts[1]) back as dbghelp.dll (EML's, set aside by EMF.exe): EML loads the EML mods again"
}
if ($left.Count) {  # keep the record of what is still renamed, also with -All
    [array]::Reverse($left)
    if ($createdChain) { $left += "created`t$($script:ChainFileName)" }
}
$left += $aside
if ($left.Count) { Write-Lines $movedRecord $left }
if (Test-Path -LiteralPath $emf) {
    foreach ($item in Get-ChildItem -LiteralPath $emf -Force) {
        if ($item.Name -eq "moved.txt" -and $left.Count) { continue }  # other mods' files are still renamed
        if (-not $All -and $keep -contains $item.Name) { continue }
        Remove-Item -LiteralPath $item.FullName -Recurse -Force
        $removed += "emf\" + $item.Name
    }
    if (-not (Get-ChildItem -LiteralPath $emf -Force)) { Remove-Item -LiteralPath $emf -Recurse -Force -ErrorAction SilentlyContinue }
}
# What EMF.exe keeps for the player outside the game folder: the Nexus API key and the downloads (%LOCALAPPDATA%\EMF),
# and its saved nxm:// setting. -All removes them; otherwise one line says where they are.
$userData = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "EMF" } else { "" }
$keyFile = if ($userData) { Join-Path $userData "nexus.key" } else { "" }
$downloads = if ($userData) { Join-Path $userData "downloads" } else { "" }
$haveKey = [bool]$keyFile -and (Test-Path -LiteralPath $keyFile)
$haveDownloads = [bool]$downloads -and (Test-Path -LiteralPath $downloads)
$backupKey = "$registryRoot\EMF\NxmBackup"
$userLines = @()
if ($All) {
    if ($haveKey) { Remove-Item -LiteralPath $keyFile -Force; $userLines += "removed your Nexus API key ($keyFile)" }
    if ($keyFile -and (Test-Path -LiteralPath "$keyFile.tmp")) { Remove-Item -LiteralPath "$keyFile.tmp" -Force }
    if ($haveDownloads) { Remove-Item -LiteralPath $downloads -Recurse -Force; $userLines += "removed EMF's downloads ($downloads)" }
    if (Test-Path -LiteralPath $backupKey) {
        # needed while a copy of EMF (another game folder's, or this one when it could not give the links back) opens
        # nxm:// links; otherwise nothing will use it again
        $handler = (Get-ItemProperty -LiteralPath $nxmCommandKey -ErrorAction SilentlyContinue).'(default)'
        if ($handler -and $handler -match '(?i)\\emf\.exe"?(\s|$)') {
            $userLines += "kept EMF's saved nxm:// setting ($backupKey): a copy of EMF still opens nxm:// links and needs it to give them back"
        } else {
            Remove-Item -LiteralPath $backupKey -Recurse -Force
            $parent = "$registryRoot\EMF"
            if ((Test-Path -LiteralPath $parent) -and -not (Get-ChildItem -LiteralPath $parent) -and -not ((Get-Item -LiteralPath $parent).Property)) {
                Remove-Item -LiteralPath $parent -Force
            }
            $userLines += "removed EMF's saved nxm:// setting ($backupKey)"
        }
    }
} elseif ($haveKey -or $haveDownloads) {
    $userLines += "kept your Nexus API key and EMF's downloads in $userData (uninstall.cmd -All removes them too)"
}
# The save backups are the player's saves: never deleted here, not even with -All (docs\saves.md).
$saveStore = (Get-SaveRoots).Store
if ($saveStore -and (Test-Path -LiteralPath $saveStore -PathType Container)) {
    $backups = @(Get-ChildItem -LiteralPath $saveStore -Directory | Where-Object { -not $_.Name.StartsWith(".") }).Count
    if ($backups) {
        $userLines += "kept your $backups save backup(s) in $saveStore (EMF never deletes them; delete that folder yourself if you do not want them)"
    }
}
if ($removed.Count -eq 0) { "nothing to remove in $Game" }
else {
    "removed from ${Game}: $($removed -join ', ')"
    if (-not $All -and (Test-Path -LiteralPath $emf)) {
        "kept your settings, mod profiles, and EMF.exe's backups and install records, in $emf (uninstall.cmd -All removes them too)"
    }
}
$userLines
