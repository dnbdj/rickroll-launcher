#Requires -Version 5.1
<#
    Rickroll.Core - the prank engine shared by Rickroll.ps1 (console),
    Stop-Rickroll.ps1 (panic button) and Launcher.ps1 (the GUI).

    Nothing in here touches the UI: every function either returns data or
    reports progress through an optional -OnLog scriptblock, so a console
    script and a WinForms timer can drive the exact same steps.
#>

$script:ProfileName = 'rickroll-profile'
$script:StateName   = 'rickroll-state.json'

function Get-RickrollProfileDir {
    [CmdletBinding()] param()
    return (Join-Path $env:TEMP $script:ProfileName)
}

function Get-RickrollStateFilePath {
    [CmdletBinding()] param()
    return (Join-Path $env:TEMP $script:StateName)
}

function Get-PrankBrowser {
    [CmdletBinding()] param()

    $candidates = @()
    if (${env:ProgramFiles(x86)}) { $candidates += Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe' }
    if ($env:ProgramFiles)        { $candidates += Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe' }
    if ($env:ProgramFiles)        { $candidates += Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe' }
    if (${env:ProgramFiles(x86)}) { $candidates += Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe' }
    if ($env:LOCALAPPDATA)        { $candidates += Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe' }
    if ($env:ProgramFiles)        { $candidates += Join-Path $env:ProgramFiles 'BraveSoftware\Brave-Browser\Application\brave.exe' }

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Initialize-RickrollKeys {
    [CmdletBinding()] param()
    if ('RickrollKeys' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class RickrollKeys
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
'@
}

function Send-KeyCombo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$Keys,
        [int]$GapMs = 35
    )

    Initialize-RickrollKeys
    $keyUp = 0x0002

    foreach ($key in $Keys) {
        [RickrollKeys]::keybd_event($key, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds $GapMs
    }

    $order = [byte[]]$Keys.Clone()
    [array]::Reverse($order)
    foreach ($key in $order) {
        [RickrollKeys]::keybd_event($key, 0, $keyUp, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds $GapMs
    }
}

function New-VirtualDesktop {
    [CmdletBinding()] param()
    Send-KeyCombo -Keys @(0x11, 0x5B, 0x44)   # Ctrl + Win + D
}

function Close-VirtualDesktop {
    [CmdletBinding()] param()
    Send-KeyCombo -Keys @(0x11, 0x5B, 0x73)   # Ctrl + Win + F4
}

function Open-RickrollWindow {
    [CmdletBinding()]
    param(
        [string]$BrowserPath,
        [Parameter(Mandatory)][string]$ProfileDir,
        [Parameter(Mandatory)][string]$Url
    )

    if ($BrowserPath) {
        $arguments = @(
            '--new-window',
            ('--user-data-dir="{0}"' -f $ProfileDir),
            '--no-first-run',
            '--no-default-browser-check',
            '--start-maximized',
            '--disable-sync',
            '--autoplay-policy=no-user-gesture-required',
            '--disable-features=msEdgeFirstRunExperience,Translate',
            ('"{0}"' -f $Url)
        )
        Start-Process -FilePath $BrowserPath -ArgumentList $arguments | Out-Null
    }
    else {
        Start-Process -FilePath $Url | Out-Null
    }
}

function Get-PrankProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProfileDir)

    $names = @('msedge.exe', 'chrome.exe', 'brave.exe')
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $names -contains $_.Name -and
        $_.CommandLine -and
        $_.CommandLine.IndexOf($ProfileDir, [StringComparison]::OrdinalIgnoreCase) -ge 0
    }
}

function Stop-PrankWindow {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProfileDir)

    $targets = @(Get-PrankProcess -ProfileDir $ProfileDir)
    if ($targets.Count -eq 0) { return 0 }

    foreach ($target in $targets) {
        Stop-Process -Id $target.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 600
    foreach ($target in @(Get-PrankProcess -ProfileDir $ProfileDir)) {
        Stop-Process -Id $target.ProcessId -Force -ErrorAction SilentlyContinue
    }
    return $targets.Count
}

function Save-RickrollState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$CreatedDesktops,
        [Parameter(Mandatory)][string]$ProfileDir
    )

    @{
        CreatedDesktops = $CreatedDesktops
        ProfileDir      = $ProfileDir
        StartedAt       = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath (Get-RickrollStateFilePath) -Encoding UTF8
}

function Get-RickrollState {
    [CmdletBinding()] param()

    $stateFile = Get-RickrollStateFilePath
    if (-not (Test-Path -LiteralPath $stateFile)) { return $null }
    try {
        return (Get-Content -Raw -LiteralPath $stateFile | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-RickrollDesktopCount {
    [CmdletBinding()] param()

    $state = Get-RickrollState
    if (-not $state) { return 0 }
    try {
        return [int]$state.CreatedDesktops
    }
    catch {
        return 0
    }
}

function Write-PrankLog {
    param(
        [scriptblock]$OnLog,
        [string]$Message,
        [string]$Level = 'info'
    )
    if ($OnLog) { & $OnLog $Message $Level }
}

function New-RickrollPlan {
    [CmdletBinding()]
    param(
        [int]$Windows = 8,
        [int]$Desktops = 3,
        [int]$DelayMs = 800,
        [string]$Url = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ&autoplay=1',
        [switch]$NoVirtualDesktops
    )

    if ($Windows -lt 1)  { $Windows = 1 }
    if ($Windows -gt 40) { $Windows = 40 }
    if ($Desktops -lt 0) { $Desktops = 0 }
    if ($Desktops -gt 8) { $Desktops = 8 }
    if ($DelayMs -lt 100)  { $DelayMs = 100 }
    if ($DelayMs -gt 5000) { $DelayMs = 5000 }

    $slots = 1
    if (-not $NoVirtualDesktops) { $slots = $Desktops + 1 }

    $perSlot = @()
    $base = [Math]::Floor($Windows / $slots)
    $extra = $Windows - ($base * $slots)
    for ($i = 0; $i -lt $slots; $i++) {
        $count = $base
        if ($i -lt $extra) { $count++ }
        $perSlot += [int]$count
    }

    $usedSlots = @($perSlot | Where-Object { $_ -gt 0 })

    return [pscustomobject]@{
        Windows           = $Windows
        Desktops          = $Desktops
        DelayMs           = $DelayMs
        Url               = $Url
        NoVirtualDesktops = [bool]$NoVirtualDesktops
        Slots             = $perSlot
        NewDesktops       = [Math]::Max(0, $usedSlots.Count - 1)
        TotalDesktops     = [Math]::Max(0, $usedSlots.Count - 1) + 1
        BrowserPath       = Get-PrankBrowser
        ProfileDir        = Get-RickrollProfileDir
    }
}

function Get-RickrollStep {
    <#
        Turns a plan into an ordered list of actions. Each step says what to do
        and how long to wait afterwards, so a console loop and a UI timer can
        both walk the same script.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan)

    $steps = @()
    $desktopNumber = 0
    $windowNumber = 0

    for ($slot = 0; $slot -lt $Plan.Slots.Count; $slot++) {
        $count = $Plan.Slots[$slot]
        if ($count -le 0) { continue }

        if ($slot -gt 0) {
            $desktopNumber++
            $steps += [pscustomobject]@{
                Kind    = 'newdesktop'
                DelayMs = 900
                Number  = $desktopNumber
                Total   = $Plan.NewDesktops
            }
        }

        for ($i = 0; $i -lt $count; $i++) {
            $windowNumber++
            $steps += [pscustomobject]@{
                Kind    = 'window'
                DelayMs = $Plan.DelayMs
                Number  = $windowNumber
                Total   = $Plan.Windows
            }
        }
    }

    return $steps
}

function Invoke-RickrollStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Step,
        [Parameter(Mandatory)]$Plan,
        [scriptblock]$OnLog
    )

    $createdDesktop = $false

    switch ($Step.Kind) {
        'newdesktop' {
            New-VirtualDesktop
            $createdDesktop = $true
            Save-RickrollState -CreatedDesktops ((Get-RickrollDesktopCount) + 1) -ProfileDir $Plan.ProfileDir
            Write-PrankLog -OnLog $OnLog -Level 'info' -Message ("Created virtual desktop {0} of {1}" -f $Step.Number, $Step.Total)
        }
        'window' {
            Open-RickrollWindow -BrowserPath $Plan.BrowserPath -ProfileDir $Plan.ProfileDir -Url $Plan.Url
            Write-PrankLog -OnLog $OnLog -Level 'info' -Message ("Opened window {0} of {1}" -f $Step.Number, $Step.Total)
        }
        default {
            Write-PrankLog -OnLog $OnLog -Level 'warn' -Message ("Unknown step: {0}" -f $Step.Kind)
        }
    }

    return [pscustomobject]@{
        Kind           = $Step.Kind
        DesktopCreated = $createdDesktop
    }
}

function Stop-RickrollPrank {
    [CmdletBinding()]
    param(
        [string]$ProfileDir = (Get-RickrollProfileDir),
        [int]$DesktopsToClose = 0,
        [switch]$KeepDesktops,
        [switch]$KeepProfile
    )

    $closed = Stop-PrankWindow -ProfileDir $ProfileDir

    if (-not $KeepDesktops -and $DesktopsToClose -gt 0) {
        for ($i = 0; $i -lt $DesktopsToClose; $i++) {
            Close-VirtualDesktop
            Start-Sleep -Milliseconds 700
        }
    }

    $stateFile = Get-RickrollStateFilePath
    if (Test-Path -LiteralPath $stateFile) {
        Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
    }

    if (-not $KeepProfile) {
        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            if (-not (Test-Path -LiteralPath $ProfileDir)) { break }
            Remove-Item -LiteralPath $ProfileDir -Recurse -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 400
        }
    }

    return $closed
}

Export-ModuleMember -Function @(
    'Get-RickrollProfileDir',
    'Get-RickrollStateFilePath',
    'Get-PrankBrowser',
    'New-RickrollPlan',
    'Get-RickrollStep',
    'Invoke-RickrollStep',
    'Stop-RickrollPrank',
    'Get-RickrollState',
    'Get-RickrollDesktopCount',
    'Open-RickrollWindow',
    'New-VirtualDesktop',
    'Close-VirtualDesktop',
    'Send-KeyCombo'
)
