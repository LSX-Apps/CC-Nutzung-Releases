Set-StrictMode -Version 2.0
$ErrorActionPreference = "Continue"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallScript = Join-Path $SourceDir "install-ccusage-windows.ps1"
$InstallDir = Join-Path $env:LOCALAPPDATA "ClaudeUsageTray"
$CredentialsPath = Join-Path $env:USERPROFILE ".claude\.credentials.json"

function Find-Claude {
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $candidates = @(
        (Join-Path $env:USERPROFILE ".local\bin\claude.exe"),
        (Join-Path $env:USERPROFILE ".local\bin\claude"),
        (Join-Path $env:APPDATA "npm\claude.cmd"),
        (Join-Path $env:APPDATA "npm\claude.ps1")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}

function Test-ClaudeCredentials {
    if (!(Test-Path -LiteralPath $CredentialsPath)) {
        return $false
    }

    try {
        $credentials = Get-Content -LiteralPath $CredentialsPath -Raw | ConvertFrom-Json
        return [bool]($credentials.claudeAiOauth.accessToken)
    } catch {
        return $false
    }
}

function Start-VisiblePowerShellScript {
    param(
        [Parameter(Mandatory=$true)][string]$ScriptText
    )

    $tmp = Join-Path $env:TEMP ("ClaudeUsageTray-" + [Guid]::NewGuid().ToString("N") + ".ps1")
    Set-Content -LiteralPath $tmp -Value $ScriptText -Encoding UTF8
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-NoExit",
        "-File", $tmp
    )
}

function Show-Info {
    param([string]$Text)
    [System.Windows.Forms.MessageBox]::Show($Text, "Claude Usage Tray", "OK", "Information") | Out-Null
}

function Show-Warn {
    param([string]$Text)
    [System.Windows.Forms.MessageBox]::Show($Text, "Claude Usage Tray", "OK", "Warning") | Out-Null
}

function Refresh-State {
    $claudePath = Find-Claude
    $hasClaude = [bool]$claudePath
    $hasCreds = Test-ClaudeCredentials
    $isInstalled = Test-Path -LiteralPath (Join-Path $InstallDir "ccusage-tray.ps1")

    if ($hasClaude) {
        $ClaudeStatus.Text = "OK - Claude Code gefunden: $claudePath"
        $ClaudeStatus.ForeColor = [System.Drawing.Color]::FromArgb(25, 135, 84)
    } else {
        $ClaudeStatus.Text = "Fehlt - Claude Code ist noch nicht installiert."
        $ClaudeStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 60, 20)
    }

    if ($hasCreds) {
        $LoginStatus.Text = "OK - Login/Credentials gefunden."
        $LoginStatus.ForeColor = [System.Drawing.Color]::FromArgb(25, 135, 84)
    } else {
        $LoginStatus.Text = "Fehlt - bitte einmal Claude im Terminal starten und im Browser anmelden."
        $LoginStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 60, 20)
    }

    if ($isInstalled) {
        $InstallStatus.Text = "OK - Tray-App ist installiert."
        $InstallStatus.ForeColor = [System.Drawing.Color]::FromArgb(25, 135, 84)
    } else {
        $InstallStatus.Text = "Noch nicht installiert."
        $InstallStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    }

    $LoginButton.Enabled = $hasClaude
    $InstallButton.Enabled = $hasCreds
}

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "Claude Usage Tray Setup"
$Form.StartPosition = "CenterScreen"
$Form.Size = New-Object System.Drawing.Size(720, 560)
$Form.MinimumSize = New-Object System.Drawing.Size(680, 520)
$Form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$Title = New-Object System.Windows.Forms.Label
$Title.Text = "Claude Usage Tray einrichten"
$Title.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$Title.AutoSize = $true
$Title.Location = New-Object System.Drawing.Point(24, 20)
$Form.Controls.Add($Title)

$Intro = New-Object System.Windows.Forms.Label
$Intro.Text = "Dieser Assistent installiert Claude Code, startet den Login und richtet danach das Tray-Icon fuer die Claude-Nutzung ein."
$Intro.AutoSize = $false
$Intro.Size = New-Object System.Drawing.Size(650, 44)
$Intro.Location = New-Object System.Drawing.Point(26, 62)
$Form.Controls.Add($Intro)

$Step1 = New-Object System.Windows.Forms.GroupBox
$Step1.Text = "1. Claude Code installieren"
$Step1.Location = New-Object System.Drawing.Point(26, 116)
$Step1.Size = New-Object System.Drawing.Size(650, 100)
$Form.Controls.Add($Step1)

$ClaudeStatus = New-Object System.Windows.Forms.Label
$ClaudeStatus.AutoSize = $false
$ClaudeStatus.Size = New-Object System.Drawing.Size(425, 40)
$ClaudeStatus.Location = New-Object System.Drawing.Point(18, 32)
$Step1.Controls.Add($ClaudeStatus)

$InstallClaudeButton = New-Object System.Windows.Forms.Button
$InstallClaudeButton.Text = "Claude Code installieren"
$InstallClaudeButton.Size = New-Object System.Drawing.Size(180, 34)
$InstallClaudeButton.Location = New-Object System.Drawing.Point(448, 30)
$Step1.Controls.Add($InstallClaudeButton)

$Step2 = New-Object System.Windows.Forms.GroupBox
$Step2.Text = "2. Bei Claude anmelden"
$Step2.Location = New-Object System.Drawing.Point(26, 228)
$Step2.Size = New-Object System.Drawing.Size(650, 100)
$Form.Controls.Add($Step2)

$LoginStatus = New-Object System.Windows.Forms.Label
$LoginStatus.AutoSize = $false
$LoginStatus.Size = New-Object System.Drawing.Size(425, 42)
$LoginStatus.Location = New-Object System.Drawing.Point(18, 32)
$Step2.Controls.Add($LoginStatus)

$LoginButton = New-Object System.Windows.Forms.Button
$LoginButton.Text = "Login starten"
$LoginButton.Size = New-Object System.Drawing.Size(180, 34)
$LoginButton.Location = New-Object System.Drawing.Point(448, 30)
$Step2.Controls.Add($LoginButton)

$Step3 = New-Object System.Windows.Forms.GroupBox
$Step3.Text = "3. Tray-App installieren"
$Step3.Location = New-Object System.Drawing.Point(26, 340)
$Step3.Size = New-Object System.Drawing.Size(650, 100)
$Form.Controls.Add($Step3)

$InstallStatus = New-Object System.Windows.Forms.Label
$InstallStatus.AutoSize = $false
$InstallStatus.Size = New-Object System.Drawing.Size(425, 42)
$InstallStatus.Location = New-Object System.Drawing.Point(18, 32)
$Step3.Controls.Add($InstallStatus)

$InstallButton = New-Object System.Windows.Forms.Button
$InstallButton.Text = "Tray installieren"
$InstallButton.Size = New-Object System.Drawing.Size(180, 34)
$InstallButton.Location = New-Object System.Drawing.Point(448, 30)
$Step3.Controls.Add($InstallButton)

$RefreshButton = New-Object System.Windows.Forms.Button
$RefreshButton.Text = "Erneut pruefen"
$RefreshButton.Size = New-Object System.Drawing.Size(130, 34)
$RefreshButton.Location = New-Object System.Drawing.Point(26, 462)
$Form.Controls.Add($RefreshButton)

$ReadmeButton = New-Object System.Windows.Forms.Button
$ReadmeButton.Text = "Anleitung oeffnen"
$ReadmeButton.Size = New-Object System.Drawing.Size(150, 34)
$ReadmeButton.Location = New-Object System.Drawing.Point(166, 462)
$Form.Controls.Add($ReadmeButton)

$CloseButton = New-Object System.Windows.Forms.Button
$CloseButton.Text = "Fertig"
$CloseButton.Size = New-Object System.Drawing.Size(110, 34)
$CloseButton.Location = New-Object System.Drawing.Point(566, 462)
$Form.Controls.Add($CloseButton)

$InstallClaudeButton.Add_Click({
    $script = @'
Write-Host ""
Write-Host "Claude Code wird installiert..."
Write-Host "Quelle: https://claude.ai/install.ps1"
Write-Host ""
try {
  irm https://claude.ai/install.ps1 | iex
  Write-Host ""
  Write-Host "Installation beendet."
  Write-Host "Falls 'claude' noch nicht gefunden wird, dieses Fenster schliessen und Setup neu pruefen."
} catch {
  Write-Host ""
  Write-Host "Installation fehlgeschlagen:"
  Write-Host $_
}
Write-Host ""
Write-Host "Dieses Fenster kann danach geschlossen werden."
'@
    Start-VisiblePowerShellScript -ScriptText $script
    Show-Info "Es wurde ein Terminal geoeffnet. Warte, bis die Installation dort fertig ist, schliesse das Terminal und klicke hier auf 'Erneut pruefen'."
})

$LoginButton.Add_Click({
    $claude = Find-Claude
    if (!$claude) {
        Show-Warn "Claude Code wurde noch nicht gefunden. Bitte zuerst Schritt 1 ausfuehren."
        return
    }

    $script = @"
Write-Host ""
Write-Host "Claude Code Login startet..."
Write-Host "Wenn ein Browserfenster aufgeht, dort anmelden und Zugriff erlauben."
Write-Host ""
& "$claude"
Write-Host ""
Write-Host "Wenn der Login fertig ist, dieses Fenster schliessen und im Setup 'Erneut pruefen' klicken."
"@
    Start-VisiblePowerShellScript -ScriptText $script
})

$InstallButton.Add_Click({
    if (!(Test-Path -LiteralPath $InstallScript)) {
        Show-Warn "Installationsdatei fehlt: $InstallScript"
        return
    }

    try {
        & $InstallScript
        Show-Info "Die Tray-App wurde installiert und gestartet. Das Icon ist unten rechts in der Windows-Taskleiste, eventuell im Pfeil-Menue."
    } catch {
        Show-Warn "Installation fehlgeschlagen: $_"
    }
    Refresh-State
})

$RefreshButton.Add_Click({ Refresh-State })
$ReadmeButton.Add_Click({
    $readme = Join-Path $SourceDir "README.md"
    if (Test-Path -LiteralPath $readme) {
        Start-Process notepad.exe $readme
    }
})
$CloseButton.Add_Click({ $Form.Close() })

$Form.Add_Shown({ Refresh-State })
[System.Windows.Forms.Application]::Run($Form)

