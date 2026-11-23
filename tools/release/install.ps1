# Installs EMF (the Enshrouded Modding Framework) and its mods into the game folder, with FlameKit. An older FlameKit
# is taken out first (Remove-OldFlameKit); the player's own FlameKit data stays.
#   install.cmd                                finds the game through Steam
#   install.cmd "D:\Games\Enshrouded"          or drag the game folder onto install.cmd
#   install.cmd "D:\EnshroudedServer"          a dedicated server's folder works the same way
# Copies the package's game\ folder next to enshrouded.exe (or enshrouded_server.exe). Your settings in emf\config are never overwritten, so
# installing a newer EMF over an older one keeps them. Files an older EMF installed that this one no longer ships are
# removed (emf\installed.txt lists what EMF copied; other mods in emf\mods are left alone). Another mod's dinput8.dll
# is renamed and listed in dinput8-chain.ini, and EMF's loader starts it (emf\moved.txt records it for uninstall).
# Before it changes anything in the game folder it backs up your saves once (the starter backup, "Before EMF", in
# %LOCALAPPDATA%\EMF\save-backups; docs\saves.md). When that fails it says so and asks whether to go on;
# -IfBackupFails Continue or Stop answers for a run without a console.
# install.cmd also asks once whether to put a shortcut to emf\EMF.exe on the desktop (-AskDesktopShortcut; the download
# with the mod manager has EMF.exe). -DesktopShortcut or -NoDesktopShortcut answers for a scripted install, which is
# never asked. uninstall.cmd removes the shortcut it made (emf\desktop_shortcut.txt), and only that one.
param(
    [string]$Game = "",
    [string]$From = (Join-Path $PSScriptRoot "game"),
    [string]$SteamRoot = "",
    [ValidateSet("Ask", "Continue", "Stop")][string]$IfBackupFails = "Ask",
    [switch]$DesktopShortcut,
    [switch]$NoDesktopShortcut,
    [switch]$AskDesktopShortcut
)
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "emf_common.ps1")

function Install-Emf([string]$Dir, [string]$Source) {
    if (-not (Test-GameFolder $Dir)) { throw "no enshrouded.exe or enshrouded_server.exe in $Dir" }
    if (-not (Test-Path -LiteralPath (Join-Path $Source "emf\emf_core.dll"))) { throw "not an EMF package: $Source\emf\emf_core.dll is missing" }
    $running = Get-GameRunning $Dir
    if ($running) { throw $running }
    # the player's saves first, once, before anything changes (not for a dedicated server: its world is in its own folder)
    if (Test-Path -LiteralPath (Join-Path $Dir "enshrouded.exe")) { Invoke-StarterBackup $Source $IfBackupFails }
    $proxy = Join-Path $Dir "dinput8.dll"
    $plan = $null
    if ((Test-Path -LiteralPath $proxy) -and -not (Test-EmfLoader $proxy)) {
        $plan = Get-MovePlan $Dir $proxy (Read-KnownTools (Join-Path $Source "emf\known_tools.txt"))
    }
    $movedRecord = Join-Path $Dir "emf\moved.txt"
    $recordBefore = @(Read-Lines $movedRecord)
    $done = @{ Moved = $false; Added = $false; Created = $false; Off = @() }
    $notes = @()
    try {
        if ($plan) {
            $to = Join-Path $Dir $plan.Name
            if ($plan.Identical) { Remove-Item -LiteralPath $proxy -Force }  # the same bytes are kept under $plan.Name
            else { Move-Item -LiteralPath $proxy -Destination $to }
            $done.Moved = $true
            # recorded at once, so even an interrupted install leaves a record uninstall can use
            New-Item -ItemType Directory -Force (Split-Path $movedRecord) | Out-Null
            $lines = @($recordBefore | Where-Object { $_ -ne "moved`t$($plan.Name)" }) + "moved`t$($plan.Name)"
            Write-Lines $movedRecord $lines
            if (-not $plan.RunsAs) {
                $r = Add-ChainEntry $Dir $plan.Name
                $done.Added = $r.Added; $done.Created = $r.Created
                if ($r.Created) { Write-Lines $movedRecord ($lines + "created`t$($script:ChainFileName)") }
                foreach ($old in $plan.SwitchOff) { Set-ChainEntryOn $Dir $old $false; $done.Off += $old }
            }
        }
        foreach ($name in @(Get-ChainEntries $Dir)) {  # a copy of EMF's own loader listed by hand: it would start EMF twice
            $at = Join-Path $Dir $name
            if ((Test-Path -LiteralPath $at) -and (Test-EmfLoader $at)) {
                Remove-ChainEntry $Dir $name $false
                $notes += "$($script:ChainFileName) listed $name, a copy of EMF's own loader: that line is taken out."
            }
        }
        Remove-OldFlameKit $Dir
        Copy-EmfFiles $Dir $Source
    } catch {
        if ($done.Moved) {  # put the other mod back as it was
            if ((Test-Path -LiteralPath $proxy) -and (Test-EmfLoader $proxy)) { Remove-Item -LiteralPath $proxy -Force }
            if (-not (Test-Path -LiteralPath $proxy)) {
                $from = Join-Path $Dir $plan.Name
                if ($plan.Identical) { Copy-Item -LiteralPath $from -Destination $proxy } else { Move-Item -LiteralPath $from -Destination $proxy }
            }
            if ($done.Added) { Remove-ChainEntry $Dir $plan.Name $done.Created }
            foreach ($old in $done.Off) { Set-ChainEntryOn $Dir $old $true }
            if ($recordBefore.Count) { Write-Lines $movedRecord $recordBefore }
            elseif (Test-Path -LiteralPath $movedRecord) { Remove-Item -LiteralPath $movedRecord -Force }
        }
        throw
    }
    # EMF 0.3.x listed the DLLs it renamed (emf\moved.txt) and the DLL mods EMF.exe installed (emf\installed_mods\*.json,
    # "chain") in [Chain]; they go into EMF's own [EMF] (ShroudForge reads only [Chain]). Only now, with the new loader
    # in place (it reads both): a failed install keeps the old loader, which reads only [Chain]. A failure here leaves
    # the lines where they are, which still works.
    $movedToEmf = @()
    try {
        $emfNames = @($recordBefore | Where-Object { $_ -like "moved`t*" } | ForEach-Object { $_.Substring(6) })
        $records = Join-Path $Dir "emf\installed_mods"
        if (Test-Path -LiteralPath $records) {
            foreach ($r in @(Get-ChildItem -LiteralPath $records -Filter "*.json" -File)) {
                try { $emfNames += @((Get-Content -LiteralPath $r.FullName -Raw | ConvertFrom-Json).chain | Where-Object { $_ }) }
                catch { }  # a record that cannot be read: its lines stay in [Chain]
            }
        }
        $movedToEmf = @(Move-ChainEntriesToEmf $Dir $emfNames)
    } catch {
        "Could not move EMF's own lines in $($script:ChainFileName) to [EMF] ($($_.Exception.Message)): they stay " +
            "in [Chain], where EMF still starts them (ShroudForge shows them as failed)."
    }
    if ($plan) {
        if ($plan.RunsAs) {
            "Another mod's dinput8.dll was renamed to $($plan.Name) and is not started: the same tool already runs " +
                "through its $($plan.RunsAs). Uninstalling EMF puts it back."
        } elseif ($plan.Identical) {
            "Another mod's dinput8.dll is the same file as $($plan.Name), which EMF starts (listed in " +
                "$($script:ChainFileName)); no second copy was kept."
        } else {
            "Another mod's dinput8.dll was renamed to $($plan.Name) and listed in $($script:ChainFileName): EMF starts it " +
                "before the game runs. Uninstalling EMF puts it back."
        }
        foreach ($old in $done.Off) {
            "The older copy $old of the same tool is switched off in $($script:ChainFileName) (kept, not deleted; " +
                "remove the '; ' in front of its line to switch it on again)."
        }
        foreach ($old in $plan.Earlier) {
            "Note: $($script:ChainFileName) also still starts $old, an earlier dinput8.dll EMF could not identify. If " +
                "$($plan.Name) is a newer copy of the same mod, switch $old off: put '; ' in front of its line."
        }
    }
    if ($movedToEmf.Count) {
        "EMF's own lines in $($script:ChainFileName) ($($movedToEmf -join ', ')) moved from [Chain] to [EMF], the " +
            "section only EMF reads: other chain loaders such as ShroudForge read only [Chain]."
    }
    $sfHere = (Test-Path -LiteralPath (Join-Path $Dir "shroudforge")) -or
        ((Test-Path -LiteralPath (Join-Path $Dir "dbghelp.dll")) -and
            (Get-DllToolName (Join-Path $Dir "dbghelp.dll") (Read-KnownTools (Join-Path $Source "emf\known_tools.txt"))) -eq "shroudforge")
    $rootLines = @(Get-ChainGameRootEntries $Dir)
    if ($sfHere -and $rootLines.Count) {
        "ShroudForge reads [Chain] in $($script:ChainFileName) too and shows $($rootLines -join ', ') there as failed " +
            "(it wants each DLL in its own folder under mods\). EMF still starts them: leave them where they are " +
            "(moving one into mods\ can break it, for example Ultimate ASI Loader's plugins)."
    }
    $notes
    # EMF is installed now: a problem with the shortcut is said, never an install failure
    try { Set-DesktopShortcut $Dir } catch { "EMF could not set up the desktop shortcut: $($_.Exception.Message)" }
    if (Test-Path -LiteralPath (Join-Path $Dir "enshrouded_server.exe")) {
        "Start the server normally. Its window and emf\emf_core.log show what loaded; players' chat commands need " +
            "[chat] admins in emf\emf_core.ini (docs\modding\server.md)."
    } else {
        "Start the game normally. emf\emf_core.log shows what loaded; the key under Esc opens the EMF console."
    }
}

# The desktop shortcut to emf\EMF.exe: asked once by install.cmd, or -DesktopShortcut / -NoDesktopShortcut. The answer
# is remembered in emf\desktop_shortcut.txt; a shortcut of the same name that EMF did not make is never replaced. When
# the recorded one is gone (the desktop moved, OneDrive), the one of that name on the current desktop that opens this
# EMF.exe is EMF's.
function Set-DesktopShortcut([string]$Dir) {
    $exe = Join-Path $Dir "emf\EMF.exe"
    if (-not (Test-Path -LiteralPath $exe)) { return }  # the manual download has no EMF.exe
    $recordPath = Join-Path $Dir $script:ShortcutRecord
    $record = "$(@(Read-Lines $recordPath | Where-Object { $_ }) | Select-Object -First 1)"
    $prompt = {
        param($question)
        if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) { return $null }
        Read-Host $question
    }
    $choice = Resolve-DesktopShortcut $record $DesktopShortcut.IsPresent $NoDesktopShortcut.IsPresent `
        $AskDesktopShortcut.IsPresent $prompt
    if ($choice -eq "decline" -and $record -notlike "made`t*") { Write-Lines $recordPath @("declined") }
    if ($choice -ne "make") { return }
    $desk = Get-DesktopFolder
    if (-not $desk -or -not (Test-Path -LiteralPath $desk -PathType Container)) {
        "EMF could not find your desktop folder, so it added no shortcut."
        return
    }
    $name = if (Test-Path -LiteralPath (Join-Path $Dir "enshrouded.exe")) { "EMF" } else { "EMF (server)" }
    $lnk = Join-Path $desk "$name.lnk"
    $recorded = if ($record -like "made`t*") { $record.Substring(5) } else { "" }
    $moved = $recorded -and -not (Test-Path -LiteralPath $recorded) -and (Test-Path -LiteralPath $lnk) -and
        (Get-ShortcutTarget $lnk) -ieq $exe
    $ours = $recorded -and (($recorded -ieq $lnk) -or $moved)
    if ((Test-Path -LiteralPath $lnk) -and -not $ours) {
        "There is already a shortcut called $name on your desktop, so EMF left it as it is and added none."
        return
    }
    try {
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
        $s.TargetPath = $exe
        $s.WorkingDirectory = Split-Path $exe
        $s.Description = "EMF, the mod manager for Enshrouded"
        $s.Save()
    } catch {
        "EMF could not add the desktop shortcut: $($_.Exception.Message)"
        return
    }
    Write-Lines $recordPath @("made`t$lnk")
    "Added a shortcut to EMF.exe on your desktop ($name). uninstall.cmd removes it."
}

# The starter backup of the saves ("Before EMF") when there is none yet. Says what it did; when the copy fails it asks
# whether to install anyway (or follows -IfBackupFails), and throws when the answer is no.
function Invoke-StarterBackup([string]$Source, [string]$IfFails) {
    $roots = Get-SaveRoots
    if (-not $roots.Store) { "EMF could not back up your saves: LOCALAPPDATA is not set."; return }
    if (Test-StarterBackup $roots.Store) { return }
    $version = ""
    $core = Join-Path $Source "emf\emf_core.dll"
    if (Test-Path -LiteralPath $core) {
        $text = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($core))
        if ($text -match 'emf_core (\d+\.\d+\.\d+)') { $version = $Matches[1] }
    }
    $r = New-SaveBackup $roots "starter" "Before EMF" "install" $version
    if ($r.Nothing) { "No Enshrouded saves on this PC yet, so there was nothing to back up."; return }
    if ($r.Ok -and $r.Problems.Count -eq 0) {
        "Backed up your saves first: $($r.Files) files ($(Format-Size $r.Bytes)) in $($r.Folder). EMF.exe's Saves tab can restore them."
        return
    }
    $what = if ($r.Ok) { "EMF backed up your saves, but not all of them: $($r.Problems -join '; ')." } else { "EMF could not back up your saves: $($r.Error)." }
    $what += " Close the game (and Steam's cloud sync) and run the install again, or copy your saves yourself first."
    if ($IfFails -eq "Continue") { "$what Installing anyway (-IfBackupFails Continue)."; return }
    if ($IfFails -eq "Stop") { throw "$what Nothing was installed." }
    if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) {
        throw "$what Nothing was installed. To install anyway, run: install.cmd -IfBackupFails Continue"
    }
    Write-Host $what
    $answer = Read-Host "Install EMF anyway? Type y for yes, anything else stops"
    if ($answer -notmatch '^\s*(y|yes)\s*$') { throw "Nothing was installed: your saves could not be backed up first." }
    "Installing anyway, as you chose."
}

# (FlameKit) Takes out an older FlameKit before the new one is copied in, so no old file is left behind:
# - emf\mods\flamekit_map: FlameKit 0.14's minimap DLL (with it a second overlay and minimap would run), all of it;
# - emf\mods\flamekit_native: the DLL part (and the .old copy the updater leaves), all of it;
# - emf\flamekit_update: an update that was waiting for the next game start;
# - emf\mods\flamekit: the old program files. The player's own data stays: the saved .json files (the junk list,
#   What's New's last version, the experimental switches, a hosted world's leaderboard; never mod.json, which is FlameKit's
#   own), the window places (ui_layout.txt), the update channel (update_channel.txt), the log level (debug.txt) and the
#   logs folder. Everything else in it is made again by FlameKit.
function Remove-OldFlameKit([string]$Dir) {
    $mods = Join-Path $Dir "emf\mods"
    $gone = @()
    foreach ($name in @("flamekit_map", "flamekit_native")) {
        $path = Join-Path $mods $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force; $gone += "emf\mods\$name" }
    }
    $held = Join-Path $Dir "emf\flamekit_update"
    if (Test-Path -LiteralPath $held) { Remove-Item -LiteralPath $held -Recurse -Force; $gone += "emf\flamekit_update" }
    $kit = Join-Path $mods "flamekit"
    $kept = 0
    if (Test-Path -LiteralPath $kit) {
        $keepFiles = @("ui_layout.txt", "update_channel.txt", "debug.txt")
        foreach ($item in @(Get-ChildItem -LiteralPath $kit -Force)) {
            $keep = ($item.PSIsContainer -and $item.Name -ieq "logs") -or
                (-not $item.PSIsContainer -and (($item.Extension -ieq ".json" -and $item.Name -ine "mod.json") -or ($keepFiles -icontains $item.Name)))
            if ($keep) { $kept++; continue }
            Remove-Item -LiteralPath $item.FullName -Recurse -Force
        }
        $gone += "the old program files in emf\mods\flamekit"
    }
    if ($gone.Count) { "Removed the old FlameKit: $($gone -join ', ') ($kept of your own files kept: junk list, window places, settings)." }
}

# Copies the package's files (the player's settings are never overwritten) and removes files an older EMF shipped
# that this one does not.
function Copy-EmfFiles([string]$Dir, [string]$Source) {
    $record = Join-Path $Dir "emf\installed.txt"
    $before = @()
    if (Test-Path -LiteralPath $record) { $before = @(Get-Content -LiteralPath $record | Where-Object { $_ }) }
    $copied = 0; $kept = 0; $now = @()
    # dinput8.dll last: if a copy fails half-way, the game keeps the older loader rather than a new loader with an old
    # core
    $files = @(Get-ChildItem -LiteralPath $Source -Recurse -File | Sort-Object { $_.FullName -ieq (Join-Path $Source "dinput8.dll") })
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($Source.Length).TrimStart("\")
        $dst = Join-Path $Dir $rel
        $isConfig = $rel -like "emf\config\*"
        if ($isConfig -and (Test-Path -LiteralPath $dst)) { $kept++; continue }  # the player's settings
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
        $copied++
        if (-not $isConfig) { $now += $rel }
    }
    $removed = 0
    foreach ($rel in $before) {  # shipped by an older EMF, not by this one
        if ($now -contains $rel -or $rel -like "emf\config\*" -or $rel -like "*..*") { continue }
        $path = Join-Path $Dir $rel
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force; $removed++ }
    }
    Set-Content -LiteralPath $record -Value $now -Encoding ascii
    "EMF installed into $Dir ($copied files copied, $kept existing settings files kept, $removed old files removed)."
}

if (-not $Game) {
    $Game = Find-EnshroudedDir $SteamRoot
    if (-not $Game) { throw "could not find Enshrouded through Steam; drag the game folder (the one with enshrouded.exe) onto install.cmd" }
}
Install-Emf (Resolve-Path -LiteralPath $Game).Path ([System.IO.Path]::GetFullPath($From))
