param(
    [switch]$Restore,
    [switch]$ResetWindows,
    [switch]$ValidateOnly,
    [switch]$CompareCurrent,
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
$modRoot = 'HKLM:\SOFTWARE\Windhawk\Engine\Mods'
$stylerPath = "$modRoot\windows-11-taskbar-styler"
$settingsPath = "$stylerPath\Settings"
$sizePath = "$modRoot\taskbar-icon-size"
$profilePath = Join-Path $PSScriptRoot 'Win11-Default-Transparent.json'
$backupRoot = Join-Path $PSScriptRoot 'Windows-Taskbar-Backups'
$latestPath = Join-Path $backupRoot 'latest.txt'
$resultPath = Join-Path $PSScriptRoot 'Windows-Default-Transparent-result.txt'

function Read-Values([string]$path) {
    $key = Get-Item -LiteralPath $path
    @($key.GetValueNames() | ForEach-Object {
        [pscustomobject]@{Name=$_; Value=$key.GetValue($_); Kind=$key.GetValueKind($_).ToString()}
    })
}
function Write-Values([string]$path, $values, [switch]$Replace) {
    if ($Replace) {
        foreach ($name in @((Get-Item -LiteralPath $path).GetValueNames())) {
            Remove-ItemProperty -LiteralPath $path -Name $name
        }
    }
    foreach ($entry in $values) {
        New-ItemProperty -LiteralPath $path -Name $entry.Name -Value $entry.Value -PropertyType $entry.Kind -Force | Out-Null
    }
}
function Notify-Mod([string]$path) {
    Set-ItemProperty -LiteralPath $path -Name SettingsChangeTime -Value ([int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
}
function Save-Snapshot {
    [pscustomobject]@{
        Format=1
        Settings=@(Read-Values $settingsPath)
        StylerFlags=@(Read-Values $stylerPath | Where-Object Name -eq 'Disabled')
        SizePresent=(Test-Path -LiteralPath $sizePath)
        SizeFlags=@(if (Test-Path -LiteralPath $sizePath) { Read-Values $sizePath | Where-Object Name -eq 'Disabled' })
    }
}
function Restore-Flags([string]$path, $flags) {
    if (@($flags | Where-Object Name -ne 'Disabled').Count) { throw 'Unexpected mod flag in snapshot.' }
    if (!@($flags).Count) { Remove-ItemProperty -LiteralPath $path -Name Disabled -ErrorAction SilentlyContinue }
    Write-Values $path $flags
    Notify-Mod $path
}
function Restore-Snapshot($snapshot) {
    if ($snapshot.Format -ne 1 -or !$snapshot.Settings) { throw 'Invalid snapshot format.' }
    Write-Values $settingsPath $snapshot.Settings -Replace
    Restore-Flags $stylerPath $snapshot.StylerFlags
    if ($snapshot.SizePresent -and (Test-Path -LiteralPath $sizePath)) {
        Restore-Flags $sizePath $snapshot.SizeFlags
    }
}
function Read-Profile {
    $document = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $values = @($document.PSObject.Properties | ForEach-Object {
        if ($_.Value -is [string]) { $kind='String' }
        elseif ($_.Value -is [int] -or $_.Value -is [long]) { $kind='DWord' }
        else { throw "Unsupported setting type: $($_.Name)" }
        [pscustomobject]@{Name=$_.Name; Value=$_.Value; Kind=$kind}
    })
    if ($document.theme -ne '') { throw 'This profile must use the native Windows theme.' }
    if ($document.clickThroughTaskbar -ne 0) { throw 'This profile must retain the native taskbar hit area.' }
    $targets = @($values | Where-Object Name -match '^controlStyles\[\d+\]\.target$')
    if ($targets.Count -ne 3) { throw 'Expected three background/button paint targets.' }
    foreach ($entry in $values) {
        if ($entry.Name -match '^controlStyles\[\d+\]\.styles\[\d+\]$') {
            # Keep all native geometry: only XAML paint properties are allowed.
            if ($entry.Value -notmatch '^(Fill|Background@[A-Za-z0-9_]+|BorderBrush@[A-Za-z0-9_]+):=') {
                throw "Non-paint setting in native profile: $($entry.Name)"
            }
            $xaml = $entry.Value.Substring($entry.Value.IndexOf(':=') + 2)
            [void]([xml]$xaml)
        } elseif ($entry.Name -notmatch '^(theme|clickThroughTaskbar|xamlDiagnosticsHandling|styleConstants\[0\]|themeResourceVariables\[0\]|controlStyles\[[0-2]\]\.target)$') {
            throw "Unexpected setting: $($entry.Name)"
        }
    }
    return $values
}
function Assert-Settings($expected) {
    $key = Get-Item -LiteralPath $settingsPath
    if ($key.GetValueNames().Count -ne @($expected).Count) { throw 'Saved settings count does not match.' }
    foreach ($entry in $expected) {
        if ($key.GetValue($entry.Name) -ne $entry.Value -or $key.GetValueKind($entry.Name).ToString() -ne $entry.Kind) {
            throw "Setting verification failed: $($entry.Name)"
        }
    }
}
function Finish([int]$code) {
    if (!$NoPause) { [void](Read-Host 'Press Enter to close') }
    exit $code
}

$before = $null
try {
    if (([int][bool]$Restore + [int][bool]$ResetWindows + [int][bool]$ValidateOnly) -gt 1) { throw 'Choose only one operation.' }
    if ($CompareCurrent -and !$ValidateOnly) { throw '-CompareCurrent requires -ValidateOnly.' }
    if ($ValidateOnly) {
        $profile = @(Read-Profile)
        if ($CompareCurrent) {
            Assert-Settings $profile
            if ((Get-ItemProperty -LiteralPath $stylerPath).Disabled -ne 0) { throw 'Taskbar Styler is not enabled.' }
            if ((Test-Path -LiteralPath $sizePath) -and (Get-ItemProperty -LiteralPath $sizePath).Disabled -ne 1) { throw 'The icon-size mod is enabled.' }
        }
        Write-Output "Validated $($profile.Count) settings. Native geometry preserved. CompareCurrent=$CompareCurrent. No changes made."
        Finish 0
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (!([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -NoPause'
        if ($Restore) { $arguments += ' -Restore' }
        if ($ResetWindows) { $arguments += ' -ResetWindows' }
        $child = Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -Wait -PassThru
        if (Test-Path -LiteralPath $resultPath) { Get-Content -LiteralPath $resultPath }
        Finish $child.ExitCode
    }

    if (!(Test-Path -LiteralPath $settingsPath)) { throw 'Install Windows 11 Taskbar Styler in Windhawk first.' }
    $before = Save-Snapshot
    if ($Restore) {
        $backupName = (Get-Content -LiteralPath $latestPath -Raw).Trim()
        if ([IO.Path]::GetFileName($backupName) -ne $backupName) { throw 'Invalid backup filename.' }
        $snapshot = Import-Clixml -LiteralPath (Join-Path $backupRoot $backupName)
        Restore-Snapshot $snapshot
        Assert-Settings $snapshot.Settings
        $message = 'SUCCESS: Previous taskbar settings and mod states restored.'
    } else {
        if (!$ResetWindows) { $profile = @(Read-Profile) }
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        $backupName = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.clixml'
        $backupPath = Join-Path $backupRoot $backupName
        $before | Export-Clixml -LiteralPath $backupPath
        if (Test-Path -LiteralPath $sizePath) {
            Set-ItemProperty -LiteralPath $sizePath -Name Disabled -Value 1
            Notify-Mod $sizePath
            if ((Get-ItemProperty -LiteralPath $sizePath).Disabled -ne 1) { throw 'Could not disable the icon-size mod.' }
        }
        if ($ResetWindows) {
            Set-ItemProperty -LiteralPath $stylerPath -Name Disabled -Value 1
            Notify-Mod $stylerPath
            if ((Get-ItemProperty -LiteralPath $stylerPath).Disabled -ne 1) { throw 'Could not disable Taskbar Styler.' }
            $message = 'SUCCESS: Taskbar mods disabled; native Windows taskbar restored.'
        } else {
            Write-Values $settingsPath $profile -Replace
            Assert-Settings $profile
            Set-ItemProperty -LiteralPath $stylerPath -Name Disabled -Value 0
            Notify-Mod $stylerPath
            if ((Get-ItemProperty -LiteralPath $stylerPath).Disabled -ne 0) { throw 'Could not enable Taskbar Styler.' }
            $message = 'SUCCESS: Native transparent taskbar with glass hover and selected states applied.'
        }
        $backupName | Set-Content -LiteralPath $latestPath -Encoding UTF8
        $message += " Backup: $backupPath"
    }
    $message | Set-Content -LiteralPath $resultPath -Encoding UTF8
    Write-Output $message
    Finish 0
} catch {
    $failure = $_ | Out-String
    if ($null -ne $before) {
        try { Restore-Snapshot $before; $failure += "`nPrevious settings restored." }
        catch { $failure += "`nRollback failed: $_" }
    }
    if (!$ValidateOnly) { $failure | Set-Content -LiteralPath $resultPath -Encoding UTF8 }
    Write-Output $failure
    Finish 1
}
