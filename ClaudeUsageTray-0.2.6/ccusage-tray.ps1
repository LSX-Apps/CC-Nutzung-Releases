param(
    [int]$PollIntervalSeconds = 300,
    [int]$ReadIntervalSeconds = 30
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Continue"

# Kill any other running instances of ccusage-tray.ps1 at startup
try {
    $myId = $PID
    $procs = Get-CimInstance Win32_Process | Where-Object {
        ($_.Name -eq "powershell.exe" -or $_.Name -eq "pwsh.exe") -and
        $_.CommandLine -and
        $_.CommandLine -like "*ccusage-tray.ps1*" -and
        $_.ProcessId -ne $myId
    }
    foreach ($proc in $procs) {
        try { Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
} catch {}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-ClaudeConfigDir {
    if ($env:CLAUDE_CONFIG_DIR -and $env:CLAUDE_CONFIG_DIR.Trim().Length -gt 0) {
        return $env:CLAUDE_CONFIG_DIR
    }
    return (Join-Path $env:USERPROFILE ".claude")
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PollScript = Join-Path $ScriptDir "ccusage-poll.ps1"
$UpdateScript = Join-Path $ScriptDir "ccusage-update.ps1"
$ConfigPath = Join-Path $ScriptDir "ccusage-config.json"
$VersionPath = Join-Path $ScriptDir "app-version.json"
$DataPath = Join-Path (Get-ClaudeConfigDir) "cc-usage.json"
$PowerShellExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$Script:PollProcess = $null
$Script:LastPollStart = [DateTime]::MinValue
$Script:CurrentState = $null
$Script:CurrentIcon = $null

function Get-AppVersion {
    if (!(Test-Path -LiteralPath $VersionPath)) {
        return "0.0.0"
    }
    try {
        return (Get-Content -LiteralPath $VersionPath -Raw | ConvertFrom-Json).version
    } catch {
        return "0.0.0"
    }
}

function Read-Config {
    $defaults = [pscustomobject]@{
        poll_interval_seconds = $PollIntervalSeconds
        read_interval_seconds = $ReadIntervalSeconds
        update_manifest_url = ""
    }

    if (!(Test-Path -LiteralPath $ConfigPath)) {
        return $defaults
    }

    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        $pollProp = $config.PSObject.Properties["poll_interval_seconds"]
        $readProp = $config.PSObject.Properties["read_interval_seconds"]
        $manifestProp = $config.PSObject.Properties["update_manifest_url"]
        if ($pollProp -and $pollProp.Value) { $defaults.poll_interval_seconds = [int]$pollProp.Value }
        if ($readProp -and $readProp.Value) { $defaults.read_interval_seconds = [int]$readProp.Value }
        if ($manifestProp -and $manifestProp.Value) { $defaults.update_manifest_url = [string]$manifestProp.Value }
    } catch {}
    return $defaults
}

$Config = Read-Config
$PollIntervalSeconds = [Math]::Max(60, [int]$Config.poll_interval_seconds)
$ReadIntervalSeconds = [Math]::Max(5, [int]$Config.read_interval_seconds)
$AppVersion = Get-AppVersion

function Get-UsageColor {
    param([Nullable[int]]$Pct)

    if ($null -eq $Pct) {
        return [System.Drawing.Color]::FromArgb(110, 110, 110)
    }
    if ($Pct -ge 90) {
        return [System.Drawing.Color]::FromArgb(220, 53, 69)
    }
    if ($Pct -ge 70) {
        return [System.Drawing.Color]::FromArgb(245, 158, 11)
    }
    return [System.Drawing.Color]::FromArgb(25, 135, 84)
}

function New-UsageIcon {
    param(
        [string]$Text,
        [System.Drawing.Color]$Color
    )

    $bitmap = New-Object System.Drawing.Bitmap 64, 64
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $shadowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(80, 0, 0, 0))
    $brush = New-Object System.Drawing.SolidBrush $Color
    $borderPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(245, 245, 245)), 4
    $symbolPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 8
    $symbolPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $symbolPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $symbolBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)

    $graphics.FillEllipse($shadowBrush, 5, 6, 56, 56)
    $graphics.FillEllipse($brush, 3, 3, 58, 58)
    $graphics.DrawEllipse($borderPen, 4, 4, 56, 56)

    $pct = $null
    try {
        if ($Text -ne "?") { $pct = [int]$Text }
    } catch {}

    if ($null -eq $pct) {
        $font = New-Object System.Drawing.Font "Segoe UI", 34, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
        $format = New-Object System.Drawing.StringFormat
        $format.Alignment = [System.Drawing.StringAlignment]::Center
        $format.LineAlignment = [System.Drawing.StringAlignment]::Center
        $rect = New-Object System.Drawing.RectangleF 0, -2, 64, 64
        $graphics.DrawString("?", $font, $symbolBrush, $rect, $format)
        $format.Dispose()
        $font.Dispose()
    } elseif ($pct -ge 70) {
        $graphics.DrawLine($symbolPen, 32, 15, 32, 38)
        $graphics.FillEllipse($symbolBrush, 27, 45, 10, 10)
    } else {
        $graphics.DrawLine($symbolPen, 17, 33, 27, 43)
        $graphics.DrawLine($symbolPen, 27, 43, 47, 22)
    }

    $icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())

    $symbolBrush.Dispose()
    $symbolPen.Dispose()
    $borderPen.Dispose()
    $brush.Dispose()
    $shadowBrush.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()

    return $icon
}

function Get-PercentText {
    param($Value)
    if ($null -eq $Value) { return "?" }
    try { return ([int]$Value).ToString() } catch { return "?" }
}

function Get-Prop {
    param(
        $Object,
        [Parameter(Mandatory=$true)][string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) {
        return $prop.Value
    }
    return $null
}

function Read-State {
    if (!(Test-Path -LiteralPath $DataPath)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $DataPath -Raw | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{
            status = "error"
            message = "cc-usage.json konnte nicht gelesen werden: $_"
        }
    }
}

function Start-Poll {
    param([switch]$Force)

    if (!(Test-Path -LiteralPath $PollScript)) {
        return
    }

    if ($Script:PollProcess -and !$Script:PollProcess.HasExited) {
        return
    }

    if (!$Force) {
        $age = (New-TimeSpan -Start $Script:LastPollStart -End (Get-Date)).TotalSeconds
        if ($age -lt [Math]::Min(60, $PollIntervalSeconds)) {
            return
        }
    }

    $Script:LastPollStart = Get-Date
    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-WindowStyle", "Hidden",
        "-File", $PollScript
    )

    try {
        $Script:PollProcess = Start-Process -FilePath $PowerShellExe -ArgumentList $args -WindowStyle Hidden -PassThru
    } catch {}
}

function Get-WindowSummary {
    param($Window)

    if (!$Window) { return "?%" }
    $pct = Get-PercentText (Get-Prop $Window "used_percentage")
    $reset = "?"
    $resetValue = Get-Prop $Window "resets_at_local"
    if ($resetValue) { $reset = $resetValue }
    return "$pct%  Reset $reset"
}

function Update-Tray {
    $state = Read-State
    $Script:CurrentState = $state

    $sessionPct = $null
    $weekPct = $null
    $status = "waiting"
    $message = "Noch keine Daten. Der erste Abruf laeuft."
    $updated = "?"
    $fiveHour = $null
    $sevenDay = $null

    if ($state) {
        $stateStatus = Get-Prop $state "status"
        if ($stateStatus) { $status = $stateStatus }
        $stateUpdated = Get-Prop $state "updated_at_local"
        if (!$stateUpdated) { $stateUpdated = Get-Prop $state "updated_at" }
        if ($stateUpdated) { $updated = $stateUpdated }
        $stateMessage = Get-Prop $state "message"
        if ($stateMessage) { $message = $stateMessage }

        $fiveHour = Get-Prop $state "five_hour"
        $sevenDay = Get-Prop $state "seven_day"
        $fivePct = Get-Prop $fiveHour "used_percentage"
        $sevenPct = Get-Prop $sevenDay "used_percentage"
        if ($null -ne $fivePct) { $sessionPct = [int]$fivePct }
        if ($null -ne $sevenPct) { $weekPct = [int]$sevenPct }
    }

    $displayPct = $sessionPct
    if ($null -eq $displayPct -and $null -ne $weekPct) {
        $displayPct = $weekPct
    }
    $iconText = Get-PercentText $displayPct
    $color = Get-UsageColor $displayPct

    $newIcon = New-UsageIcon -Text $iconText -Color $color
    $oldIcon = $Script:CurrentIcon
    $NotifyIcon.Icon = $newIcon
    $Script:CurrentIcon = $newIcon
    if ($oldIcon) {
        try { $oldIcon.Dispose() } catch {}
    }

    if ($status -eq "ok") {
        $NotifyIcon.Text = "Claude Usage: 5h $iconText%, 7d $(Get-PercentText $weekPct)%"
    } else {
        $NotifyIcon.Text = "Claude Usage: $status"
    }

    $SessionItem.Text = "5 Stunden: $(Get-WindowSummary $fiveHour)"
    $WeekItem.Text = "Woche: $(Get-WindowSummary $sevenDay)"
    $UpdatedItem.Text = "Aktualisiert: $updated"
    $StatusItem.Text = "Status: $status"
    if ($status -ne "ok" -and $message) {
        $MessageItem.Text = "Hinweis: $message"
        $MessageItem.Visible = $true
    } else {
        $MessageItem.Visible = $false
    }
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$MenuOwner = New-Object System.Windows.Forms.Form
$MenuOwner.ShowInTaskbar = $false
$MenuOwner.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
$MenuOwner.Size = New-Object System.Drawing.Size(0, 0)
$MenuOwner.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None

$NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
$NotifyIcon.Visible = $true
$NotifyIcon.Text = "Claude Usage startet..."
$NotifyIcon.Icon = New-UsageIcon -Text "?" -Color ([System.Drawing.Color]::FromArgb(110, 110, 110))
$Script:CurrentIcon = $NotifyIcon.Icon

$Menu = New-Object System.Windows.Forms.ContextMenuStrip
$VersionItem = $Menu.Items.Add("Claude Usage Tray v$AppVersion")
$VersionItem.Enabled = $false
$Menu.Items.Add("-") | Out-Null
$SessionItem = $Menu.Items.Add("5 Stunden: ?")
$SessionItem.Enabled = $false
$WeekItem = $Menu.Items.Add("Woche: ?")
$WeekItem.Enabled = $false
$UpdatedItem = $Menu.Items.Add("Aktualisiert: ?")
$UpdatedItem.Enabled = $false
$StatusItem = $Menu.Items.Add("Status: startet")
$StatusItem.Enabled = $false
$MessageItem = $Menu.Items.Add("Hinweis: ?")
$MessageItem.Enabled = $false
$MessageItem.Visible = $false
$Menu.Items.Add("-") | Out-Null
$RefreshItem = $Menu.Items.Add("Jetzt aktualisieren")
$UpdateItem = $Menu.Items.Add("Update pr$([char]0xFC)fen")
$OpenUsageItem = $Menu.Items.Add("Claude Usage im Browser $([char]0xF6)ffnen")
$OpenFileItem = $Menu.Items.Add("JSON-Datei anzeigen")
$Menu.Items.Add("-") | Out-Null
$UninstallItem = $Menu.Items.Add("App deinstallieren")
$Menu.Items.Add("-") | Out-Null
$ExitItem = $Menu.Items.Add("Beenden")

$RefreshItem.Add_Click({
    Start-Poll -Force
    Start-Sleep -Milliseconds 500
    Update-Tray
})
$UpdateItem.Add_Click({
    if (Test-Path -LiteralPath $UpdateScript) {
        Start-Process -FilePath $PowerShellExe -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-WindowStyle", "Hidden",
            "-File", $UpdateScript,
            "-Interactive"
        ) -WindowStyle Hidden
    }
})
$OpenUsageItem.Add_Click({
    Start-Process "https://claude.ai/settings/usage"
})
$OpenFileItem.Add_Click({
    if (Test-Path -LiteralPath $DataPath) {
        Start-Process explorer.exe "/select,`"$DataPath`""
    } else {
        Start-Process explorer.exe (Get-ClaudeConfigDir)
    }
})
$UninstallItem.Add_Click({
    $InstallScript = Join-Path $ScriptDir "install-ccusage-windows.ps1"
    if (Test-Path -LiteralPath $InstallScript) {
        Start-Process -FilePath $PowerShellExe -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-WindowStyle", "Hidden",
            "-File", $InstallScript,
            "-Uninstall"
        ) -WindowStyle Hidden
    }
})
$ExitItem.Add_Click({
    $NotifyIcon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

$NotifyIcon.ContextMenuStrip = $null
$NotifyIcon.Add_MouseUp({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Update-Tray
        $NotifyIcon.ShowBalloonTip(5000, "Claude Usage", $NotifyIcon.Text, [System.Windows.Forms.ToolTipIcon]::Info)
    } elseif ($_.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        Update-Tray
        $Menu.Show($MenuOwner, [System.Windows.Forms.Cursor]::Position)
    }
})

$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = [Math]::Max(5, $ReadIntervalSeconds) * 1000
$Timer.Add_Tick({
    Update-Tray
})

$PollTimer = New-Object System.Windows.Forms.Timer
$PollTimer.Interval = [Math]::Max(60, $PollIntervalSeconds) * 1000
$PollTimer.Add_Tick({
    Start-Poll
})

Start-Poll -Force
Update-Tray
$Timer.Start()
$PollTimer.Start()

[System.Windows.Forms.Application]::Run()

try {
    $NotifyIcon.Visible = $false
    if ($Script:CurrentIcon) { $Script:CurrentIcon.Dispose() }
    $NotifyIcon.Dispose()
} catch {}
