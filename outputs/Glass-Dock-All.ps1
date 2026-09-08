param([switch]$Restore, [switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'

# Appearance: ARGB colors. Change these values to customize the whole theme.
$Glass = 'Background:=<WindhawkBlur BlurAmount="20" TintColor="#10000000" FallbackColor="#80303030" />'
$Hover = '#18FFFFFF'
$Pressed = '#28FFFFFF'
$Frame = @($Glass,'CornerRadius=16','BorderBrush=#28FFFFFF','BorderThickness=1','Padding=6,0,6,0')
$Button = @('Background=Transparent','Background@Normal=Transparent',"Background@PointerOver=$Hover", "Background@Pressed=$Pressed",'Background@CheckedNormal=Transparent',"Background@CheckedPointerOver=$Hover", "Background@CheckedPressed=$Pressed",'BorderBrush=Transparent','BorderThickness=0','CornerRadius=10')
$Rules = @(
    @{target='Taskbar.TaskbarFrame > Grid#RootGrid'; styles=($Frame + 'Margin=0,2,0,6')},
    @{target='StackPanel#SystemTrayFrameGrid, Grid#SystemTrayFrameGrid'; styles=($Frame + 'Margin=8,2,8,6')},
    @{target='Grid#IconPanel@CommonStates > Border#BackgroundElement, Taskbar.TaskListButtonPanel@CommonStates > Grid > Border#BackgroundElement, Taskbar.TaskListButtonPanel@CommonStates > Border#BackgroundElement, Taskbar.TaskListLabeledButtonPanel@CommonStates > Border#BackgroundElement, SearchUx.SearchUI.SearchButtonRootGrid@CommonStates > Grid > Border#BackgroundElement, SearchUx.SearchUI.SearchButtonRootGrid@CommonStates > Border#BackgroundElement'; styles=@('Background=Transparent','Background@InactiveNormal=Transparent','Background@ActiveNormal=Transparent',"Background@InactivePointerOver=$Hover", "Background@ActivePointerOver=$Hover", "Background@InactivePressed=$Pressed", "Background@ActivePressed=$Pressed",'Background@MultiWindowNormal=Transparent','Background@MultiWindowActive=Transparent',"Background@MultiWindowPointerOver=$Hover", "Background@MultiWindowPressed=$Pressed",'BorderBrush=Transparent','BorderThickness=0','CornerRadius=10')},
    @{target='SystemTray.ChevronIconView > Grid@, SystemTray.NotifyIconView > Grid@, SystemTray.IconView > Grid@, SystemTray.OmniButton > Grid@'; styles=@('Background=Transparent','Background@Normal=Transparent','Background@PointerOver=Transparent','Background@Pressed=Transparent','Background@CheckedNormal=Transparent','Background@CheckedPointerOver=Transparent','Background@CheckedPressed=Transparent')},
    @{target='SystemTray.ChevronIconView > Grid@ > Border#BackgroundBorder, SystemTray.NotifyIconView > Grid@ > Border#BackgroundBorder, SystemTray.IconView > Grid@ > Border#BackgroundBorder'; styles=$Button},
    @{target='SystemTray.OmniButton > Grid@CommonStates > Border#BackgroundBorder'; styles=$Button},
    @{target='Border#OverflowFlyoutBackgroundBorder'; styles=@($Glass,'BorderBrush=#28FFFFFF','BorderThickness=1','CornerRadius=16')}
)

if ($ValidateOnly) {
    $seen = @{}
    foreach ($r in $Rules) {
        if ($seen.ContainsKey($r.target)) { throw 'Duplicate rule target' }
        $seen[$r.target] = $true
        foreach ($s in $r.styles) { if ($s -notmatch '^.+?=.+$') { throw "Invalid style: $s" } }
    }
    Write-Output "Validated $($Rules.Count) rule groups. No settings changed."
    return
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    if ($Restore) { $arguments += ' -Restore' }
    $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $p.ExitCode
}

$Base = 'HKLM:\SOFTWARE\Windhawk\Engine\Mods'
$Styler = "$Base\windows-11-taskbar-styler"
$Size = "$Base\taskbar-icon-size"
$SnapshotRoot = Join-Path $PSScriptRoot 'Glass-Dock-Backups'
$Latest = Join-Path $SnapshotRoot 'latest.txt'

function Read-Values([string]$Path) {
    $key = Get-Item -LiteralPath $Path
    @($key.GetValueNames() | ForEach-Object {
        [pscustomobject]@{Name=$_; Value=$key.GetValue($_); Kind=$key.GetValueKind($_).ToString()}
    })
}
function Restore-Values([string]$Path, $Values, [switch]$Replace) {
    if ($Replace) {
        $names = @((Get-Item -LiteralPath $Path).GetValueNames())
        foreach ($name in $names) { Remove-ItemProperty -LiteralPath $Path -Name $name }
    }
    foreach ($v in $Values) {
        New-ItemProperty -LiteralPath $Path -Name $v.Name -Value $v.Value -PropertyType $v.Kind -Force | Out-Null
    }
}
function Restore-Snapshot([string]$Path) {
    $snapshot = Import-Clixml -LiteralPath $Path
    Restore-Values "$Styler\Settings" $snapshot.StylerSettings -Replace
    Restore-Values "$Size\Settings" $snapshot.SizeSettings -Replace
    Restore-Values $Styler $snapshot.StylerFlags
    Restore-Values $Size $snapshot.SizeFlags
    $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Set-ItemProperty $Styler SettingsChangeTime $now
    Set-ItemProperty $Size SettingsChangeTime $now
}

$SnapshotPath = $null
try {
    foreach ($path in @($Styler,$Size,"$Styler\Settings","$Size\Settings")) {
        if (!(Test-Path -LiteralPath $path)) { throw "Required installed mod missing: $path" }
    }
    if ($Restore) {
        if (!(Test-Path -LiteralPath $Latest)) { throw 'No integrated-script backup found.' }
        $restorePath = Join-Path $SnapshotRoot ((Get-Content -LiteralPath $Latest -Raw).Trim())
        Restore-Snapshot $restorePath
        Write-Host 'Restored the settings from before the most recent Apply.'
    } else {
        New-Item -ItemType Directory -Path $SnapshotRoot -Force | Out-Null
        $SnapshotPath = Join-Path $SnapshotRoot ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.clixml')
        [pscustomobject]@{
            StylerSettings=@(Read-Values "$Styler\Settings")
            SizeSettings=@(Read-Values "$Size\Settings")
            StylerFlags=@(Read-Values $Styler | Where-Object Name -in @('Disabled','SettingsChangeTime'))
            SizeFlags=@(Read-Values $Size | Where-Object Name -in @('Disabled','SettingsChangeTime'))
        } | Export-Clixml -LiteralPath $SnapshotPath
        [IO.Path]::GetFileName($SnapshotPath) | Set-Content -LiteralPath $Latest

        # Replace old control-style rules to avoid duplicate/conflicting partial scripts.
        $names = @((Get-Item "$Styler\Settings").GetValueNames())
        foreach ($name in $names) {
            if ($name -match '^controlStyles\[') { Remove-ItemProperty "$Styler\Settings" -Name $name }
        }
        Set-ItemProperty "$Styler\Settings" theme 'DockLike'
        for ($i=0; $i -lt $Rules.Count; $i++) {
            New-ItemProperty "$Styler\Settings" -Name "controlStyles[$i].target" -Value $Rules[$i].target -PropertyType String -Force | Out-Null
            for ($j=0; $j -lt $Rules[$i].styles.Count; $j++) {
                New-ItemProperty "$Styler\Settings" -Name "controlStyles[$i].styles[$j]" -Value $Rules[$i].styles[$j] -PropertyType String -Force | Out-Null
            }
        }
        Set-ItemProperty "$Size\Settings" TaskbarHeight 52
        Set-ItemProperty "$Size\Settings" IconSize 24
        Set-ItemProperty "$Size\Settings" TaskbarButtonWidth 40
        $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        Set-ItemProperty $Styler SettingsChangeTime $now
        Set-ItemProperty $Size SettingsChangeTime $now
        Set-ItemProperty $Styler Disabled 0
        Set-ItemProperty $Size Disabled 0

        # Verify each saved rule, not just the command exit status.
        $saved = Get-Item "$Styler\Settings"
        for ($i=0; $i -lt $Rules.Count; $i++) {
            if ($saved.GetValue("controlStyles[$i].target") -ne $Rules[$i].target) { throw 'Target verification failed' }
            for ($j=0; $j -lt $Rules[$i].styles.Count; $j++) {
                if ($saved.GetValue("controlStyles[$i].styles[$j]") -ne $Rules[$i].styles[$j]) { throw 'Style verification failed' }
            }
        }
        Write-Host 'SUCCESS: All glass Dock settings applied and verified.'
        Write-Host "Backup: $SnapshotPath"
        Write-Host 'Close and reopen the tray popup. If needed, toggle Taskbar Styler off/on in Windhawk.'
    }
    'SUCCESS ' + (Get-Date -Format o) | Set-Content (Join-Path $PSScriptRoot 'Glass-Dock-All-result.txt')
} catch {
    $failure = $_ | Out-String
    if (!$Restore -and $SnapshotPath -and (Test-Path -LiteralPath $SnapshotPath)) {
        try { Restore-Snapshot $SnapshotPath; Write-Host 'Previous settings restored after failure.' }
        catch { $failure += "`nRollback failed: $_" }
    }
    $failure | Set-Content (Join-Path $PSScriptRoot 'Glass-Dock-All-result.txt')
    Write-Host $failure -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}
Read-Host 'Press Enter to close'

