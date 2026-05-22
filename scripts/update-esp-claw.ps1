<#
.SYNOPSIS
    Automatisiert den Update-, Rebuild- und Re-Flash-Workflow für ESP-Claw
    auf dem Guition JC1060P470.

.DESCRIPTION
    Setzt die Schritte aus dem Blog Post
    "ESP-Claw aktuell halten - Update, Rebuild und Re-Flash auf das Guition JC1060P470"
    in einem einzigen PowerShell-Skript um:

      Phase 1  : ZIP-Backup der Board-Adaption mit Zeitstempel
      Phase 3  : git stash, fetch, log, pull --rebase, submodule update
      Phase 4  : ZIP wieder einspielen + Check auf alte .c-Backup-Dateien
      Phase 5  : pip install --upgrade esp-bmgr-assist
      Phase 6  : idf.py reconfigure + gen-bmgr-config
      Phase 8  : idf.py build
      Phase 10 : idf.py -p <COM> app-flash monitor

    Wichtig: Das Skript MUSS in der "ESP-IDF 5.5 PowerShell" ausgeführt werden,
    da es das idf.py-Kommando voraussetzt.

.PARAMETER RepoPath
    Pfad zum lokalen ESP-Claw-Repository. Default: D:\esp32-claw\esp-claw

.PARAMETER BackupPath
    Pfad zum Backup-Ordner für die ZIP-Dateien. Default: D:\esp32-claw\backups

.PARAMETER BoardName
    Name der Board-Adaption (Unterordner unter boards/<Vendor>/). Default: jc1060p470_m3_dev

.PARAMETER BoardVendor
    Hersteller-Unterordner unter boards/. Default: guition

.PARAMETER ComPort
    COM-Port des angeschlossenen Boards. Default: COM7

.PARAMETER SkipFlash
    Wenn gesetzt: Build wird ausgeführt, aber nicht geflasht.

.PARAMETER SkipMonitor
    Wenn gesetzt: Flashen, aber ohne anschließenden Monitor.

.PARAMETER NonInteractive
    Wenn gesetzt: Keine Bestätigungsabfragen vor kritischen Schritten.

.EXAMPLE
    .\update-esp-claw.ps1
    Standard-Lauf mit allen Default-Werten.

.EXAMPLE
    .\update-esp-claw.ps1 -ComPort COM5 -SkipFlash
    Build durchführen, aber nicht flashen (z. B. auf einem Rechner ohne angeschlossenes Board).

.EXAMPLE
    .\update-esp-claw.ps1 -NonInteractive
    Komplett-Durchlauf ohne Rückfragen.
#>

[CmdletBinding()]
param(
    [string]$RepoPath       = "D:\esp32-claw\esp-claw",
    [string]$BackupPath     = "D:\esp32-claw\backups",
    [string]$BoardName      = "jc1060p470_m3_dev",
    [string]$BoardVendor    = "guition",
    [string]$ComPort        = "COM7",
    [switch]$SkipFlash,
    [switch]$SkipMonitor,
    [switch]$NonInteractive
)

# --------------------------------------------------------------------------
# Voreinstellungen und Pfade
# --------------------------------------------------------------------------
$ErrorActionPreference = "Stop"
$startTime             = Get-Date
$dateStamp             = Get-Date -Format "yyyyMMdd_HHmmss"
$edgeAgentPath         = Join-Path $RepoPath "application\edge_agent"
$boardsPath            = Join-Path $edgeAgentPath "boards"
$boardAdaptPath        = Join-Path $boardsPath "$BoardVendor\$BoardName"
$backupFileName        = "boards_${BoardVendor}_${dateStamp}.zip"
$backupFile            = Join-Path $BackupPath $backupFileName
$logFile               = Join-Path $BackupPath "update_log_${dateStamp}.txt"

# --------------------------------------------------------------------------
# Hilfsfunktionen
# --------------------------------------------------------------------------
function Write-Phase {
    param([int]$Number, [string]$Title)
    Write-Host ""
    Write-Host ("=" * 76) -ForegroundColor DarkCyan
    Write-Host (" Phase {0}: {1}" -f $Number, $Title) -ForegroundColor Cyan
    Write-Host ("=" * 76) -ForegroundColor DarkCyan
}

function Write-Step {
    param([string]$Message)
    Write-Host ("> {0}" -f $Message) -ForegroundColor Yellow
}

function Write-OK {
    param([string]$Message)
    Write-Host ("[OK] {0}" -f $Message) -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host ("[WARN] {0}" -f $Message) -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host ("[FEHLER] {0}" -f $Message) -ForegroundColor Red
}

function Invoke-Native {
    param(
        [string]$Description,
        [scriptblock]$Block
    )
    Write-Step $Description
    & $Block
    if ($LASTEXITCODE -ne 0) {
        Write-Err "$Description fehlgeschlagen (Exit-Code: $LASTEXITCODE)"
        throw "Befehl fehlgeschlagen: $Description"
    }
}

function Confirm-Continue {
    param([string]$Prompt)
    if ($NonInteractive) { return $true }
    Write-Host ""
    $answer = Read-Host ("{0} [J/n]" -f $Prompt)
    if ([string]::IsNullOrWhiteSpace($answer)) { return $true }
    return ($answer -match '^(j|y|ja|yes)$')
}

function Test-Environment {
    # ESP-IDF 5.5 PowerShell?
    $idfPath = Get-Command idf.py -ErrorAction SilentlyContinue
    if (-not $idfPath) {
        Write-Err "idf.py wurde nicht gefunden."
        Write-Err "Bitte dieses Skript in der ESP-IDF 5.5 PowerShell ausfuehren."
        throw "ESP-IDF-Umgebung nicht aktiv."
    }
    Write-OK "ESP-IDF-Umgebung aktiv: $($idfPath.Source)"

    # Repo vorhanden?
    if (-not (Test-Path $RepoPath)) {
        throw "Repo-Pfad nicht gefunden: $RepoPath"
    }
    Write-OK "Repo gefunden: $RepoPath"

    # Board-Adaption vorhanden?
    if (-not (Test-Path $boardAdaptPath)) {
        throw "Board-Adaption nicht gefunden: $boardAdaptPath"
    }
    Write-OK "Board-Adaption gefunden: $boardAdaptPath"

    # Backup-Verzeichnis sicherstellen
    if (-not (Test-Path $BackupPath)) {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        Write-OK "Backup-Verzeichnis angelegt: $BackupPath"
    } else {
        Write-OK "Backup-Verzeichnis vorhanden: $BackupPath"
    }
}

# --------------------------------------------------------------------------
# Header und Logging
# --------------------------------------------------------------------------
Start-Transcript -Path $logFile -Append | Out-Null

Write-Host ""
Write-Host "##############################################################" -ForegroundColor Magenta
Write-Host "#                                                            #" -ForegroundColor Magenta
Write-Host "#   ESP-Claw Update-Skript - Guition JC1060P470              #" -ForegroundColor Magenta
Write-Host "#   Blog Post: ai-box.eu - Teil 5 der ESP-Claw-Serie         #" -ForegroundColor Magenta
Write-Host "#                                                            #" -ForegroundColor Magenta
Write-Host "##############################################################" -ForegroundColor Magenta
Write-Host ""
Write-Host ("Start:      {0}" -f $startTime)
Write-Host ("Repo:       {0}" -f $RepoPath)
Write-Host ("Edge-Agent: {0}" -f $edgeAgentPath)
Write-Host ("Board:      {0}\{1}" -f $BoardVendor, $BoardName)
Write-Host ("COM-Port:   {0}" -f $ComPort)
Write-Host ("Backup:     {0}" -f $backupFile)
Write-Host ("Log:        {0}" -f $logFile)
Write-Host ""

try {
    # ----------------------------------------------------------------------
    # Vorpruefung
    # ----------------------------------------------------------------------
    Write-Phase 0 "Vorpruefung der Umgebung"
    Test-Environment

    # ----------------------------------------------------------------------
    # Phase 1: Backup der Board-Adaption
    # ----------------------------------------------------------------------
    Write-Phase 1 "Backup der Board-Adaption als ZIP"
    Set-Location $edgeAgentPath

    Write-Step "Erstelle ZIP-Backup von boards\$BoardVendor"
    Compress-Archive `
        -Path  (Join-Path $boardsPath $BoardVendor) `
        -DestinationPath $backupFile `
        -Force
    Write-OK "Backup gespeichert: $backupFile"

    # ----------------------------------------------------------------------
    # Phase 3: ESP-Claw-Repository aktualisieren
    # ----------------------------------------------------------------------
    Write-Phase 3 "ESP-Claw-Repository aktualisieren"
    Set-Location $RepoPath

    Invoke-Native "git status" { git status }
    Invoke-Native "Lokale Aenderungen via git stash sichern" {
        git stash --include-untracked
    }
    Invoke-Native "git fetch" { git fetch }

    Write-Step "Anstehende Commits seit letztem Stand"
    git --no-pager log HEAD..origin/master --oneline

    if (-not (Confirm-Continue "Mit 'git pull --rebase' fortfahren?")) {
        throw "Abbruch durch Benutzer."
    }

    Invoke-Native "git pull --rebase" { git pull --rebase }
    Invoke-Native "Submodule aktualisieren" {
        git submodule update --init --recursive
    }

    # ----------------------------------------------------------------------
    # Phase 4: Backup wieder einspielen + Check auf alte .c-Backup-Dateien
    # ----------------------------------------------------------------------
    Write-Phase 4 "Backup einspielen und Boards-Verzeichnis pruefen"

    Write-Step "Entpacke ZIP-Backup zurueck nach boards\"
    Expand-Archive `
        -Path  $backupFile `
        -DestinationPath $boardsPath `
        -Force
    Write-OK "Board-Adaption wiederhergestellt."

    Write-Step "Pruefe auf alte Backup-Dateien (*.c) im Boards-Verzeichnis"
    $bakSources = Get-ChildItem -Path $boardAdaptPath -Filter "*BACKUP*.c" -ErrorAction SilentlyContinue
    if ($bakSources) {
        foreach ($f in $bakSources) {
            $newName = "$($f.Name).bak"
            Rename-Item -Path $f.FullName -NewName $newName
            Write-Warn "Backup-Datei umbenannt: $($f.Name) -> $newName"
        }
    } else {
        Write-OK "Keine *BACKUP*.c Dateien gefunden."
    }

    # ----------------------------------------------------------------------
    # Phase 5: Tooling-Updates
    # ----------------------------------------------------------------------
    Write-Phase 5 "Tooling-Update: esp-bmgr-assist"
    Invoke-Native "pip install --upgrade esp-bmgr-assist" {
        pip install --upgrade esp-bmgr-assist
    }

    # ----------------------------------------------------------------------
    # Phase 6: Reconfigure + gen-bmgr-config
    # ----------------------------------------------------------------------
    Write-Phase 6 "Komponenten neu aufloesen und gen-bmgr-config"
    Set-Location $edgeAgentPath

    Invoke-Native "idf.py reconfigure" { idf.py reconfigure }
    Invoke-Native "idf.py gen-bmgr-config -c .\boards -b $BoardName" {
        idf.py gen-bmgr-config -c .\boards -b $BoardName
    }

    # ----------------------------------------------------------------------
    # Phase 8: Build
    # ----------------------------------------------------------------------
    Write-Phase 8 "Firmware bauen"
    $buildStart = Get-Date
    Invoke-Native "idf.py build" { idf.py build }
    $buildDuration = (Get-Date) - $buildStart
    Write-OK ("Build abgeschlossen in {0:N1} Minuten" -f $buildDuration.TotalMinutes)

    # ----------------------------------------------------------------------
    # Phase 10: Re-Flash (mit app-flash!) + optional Monitor
    # ----------------------------------------------------------------------
    if ($SkipFlash) {
        Write-Phase 10 "Flash uebersprungen (Schalter -SkipFlash)"
        Write-OK "Build steht bereit. Naechster Schritt manuell: idf.py -p $ComPort app-flash monitor"
    }
    else {
        Write-Phase 10 "Sanfter Re-Flash via app-flash"
        Write-Host ""
        Write-Host "  WICHTIG: Es wird 'app-flash' verwendet, NICHT 'flash'." -ForegroundColor Yellow
        Write-Host "  Dadurch bleibt die storage.bin auf dem Board erhalten" -ForegroundColor Yellow
        Write-Host "  und WiFi, LLM-Config sowie Memory-Dateien gehen NICHT verloren." -ForegroundColor Yellow
        Write-Host ""

        if (-not (Confirm-Continue "Jetzt 'idf.py -p $ComPort app-flash' starten?")) {
            throw "Abbruch durch Benutzer."
        }

        if ($SkipMonitor) {
            Invoke-Native "idf.py -p $ComPort app-flash" {
                idf.py -p $ComPort app-flash
            }
            Write-OK "Flash abgeschlossen. Monitor wurde uebersprungen."
        }
        else {
            Write-Step "Starte idf.py -p $ComPort app-flash monitor"
            Write-Host "  (Monitor mit Strg + ] beenden)" -ForegroundColor DarkGray
            idf.py -p $ComPort app-flash monitor
            # Monitor laeuft interaktiv; Exit-Code nach Strg+] ist normal.
        }
    }

    # ----------------------------------------------------------------------
    # Fertig
    # ----------------------------------------------------------------------
    $totalDuration = (Get-Date) - $startTime
    Write-Host ""
    Write-Host "##############################################################" -ForegroundColor Green
    Write-Host "#  Update erfolgreich abgeschlossen                          #" -ForegroundColor Green
    Write-Host "##############################################################" -ForegroundColor Green
    Write-Host ("Gesamtdauer: {0:N1} Minuten" -f $totalDuration.TotalMinutes)
    Write-Host ("Log:         {0}" -f $logFile)
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "##############################################################" -ForegroundColor Red
    Write-Host "#  Update FEHLGESCHLAGEN                                     #" -ForegroundColor Red
    Write-Host "##############################################################" -ForegroundColor Red
    Write-Err $_.Exception.Message
    Write-Host ""
    Write-Host "Tipp zur Wiederherstellung des Stash:" -ForegroundColor Yellow
    Write-Host "  cd $RepoPath"                       -ForegroundColor Yellow
    Write-Host "  git stash list"                     -ForegroundColor Yellow
    Write-Host "  git stash pop"                      -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Letztes Backup liegt unter: $backupFile" -ForegroundColor Yellow
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}
