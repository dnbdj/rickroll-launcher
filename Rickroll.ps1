#Requires -Version 5.1
<#
.SYNOPSIS
    Console version of the Rickroll prank: floods browser windows across several
    Windows virtual desktops with "Never Gonna Give You Up" playing in each one.

.DESCRIPTION
    Thin wrapper around Rickroll.Core.psm1 - the same engine the GUI launcher
    (Launcher.ps1) drives. Prefer the launcher for day to day use; this script is
    handy for scripting and for a quick console run.

    Every window uses a throwaway profile in %TEMP%\rickroll-profile, so
    Stop-Rickroll.ps1 can close exactly the prank windows and nothing else.

    The prank is self-limiting: it cleans up after -DurationSeconds (default 120).
    Ctrl+C cleans up too.

.PARAMETER Windows
    Total number of browser windows to open (1-40). Default 8.

.PARAMETER Desktops
    How many extra Windows virtual desktops to create (0-8). Default 3.

.PARAMETER DelayMs
    Pause between opening windows, in milliseconds. Default 800.

.PARAMETER DurationSeconds
    How long the prank stays up before cleaning itself up. Default 120.

.PARAMETER Url
    Page to open in every window.

.PARAMETER NoVirtualDesktops
    Skip the virtual desktops and just open the windows where you are.

.PARAMETER DryRun
    Print the plan without opening anything.

.PARAMETER Yes
    Skip the "are you sure" prompt.

.EXAMPLE
    .\Rickroll.ps1 -Windows 4 -Desktops 2

.EXAMPLE
    .\Rickroll.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 40)]     [int]    $Windows = 8,
    [ValidateRange(0, 8)]      [int]    $Desktops = 3,
    [ValidateRange(200, 5000)] [int]    $DelayMs = 800,
    [ValidateRange(5, 3600)]   [int]    $DurationSeconds = 120,
    [string]                            $Url = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ&autoplay=1',
    [switch]                            $NoVirtualDesktops,
    [switch]                            $DryRun,
    [switch]                            $Yes
)

$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'Rickroll.Core.psm1') -Force

$plan = New-RickrollPlan -Windows $Windows -Desktops $Desktops -DelayMs $DelayMs -Url $Url -NoVirtualDesktops:$NoVirtualDesktops

if ($DryRun) {
    Write-Host 'Rickroll plan (nothing has been opened):' -ForegroundColor Magenta
    if ($plan.BrowserPath) { $browserText = $plan.BrowserPath } else { $browserText = 'default browser (cannot auto-close)' }
    $spread = ($plan.Slots | Where-Object { $_ -gt 0 }) -join ', '
    Write-Host ("  browser      : {0}" -f $browserText)
    Write-Host ("  windows      : {0}" -f $plan.Windows)
    Write-Host ("  new desktops : {0}  (Ctrl+Win+D each)" -f $plan.NewDesktops)
    Write-Host ("  windows/desk : {0}" -f $spread)
    Write-Host ("  duration     : {0}s, then it cleans itself up" -f $DurationSeconds)
    Write-Host ("  video        : {0}" -f $Url)
    return
}

if (-not $plan.BrowserPath) {
    Write-Warning 'No Edge/Chrome/Brave found. Falling back to the default browser, which cannot be closed automatically.'
}

if (-not $Yes) {
    Write-Host ("This will open {0} browser windows across {1} desktop(s) at full volume for {2}s. Continue? [y/N] " -f $plan.Windows, $plan.TotalDesktops, $DurationSeconds) -NoNewline -ForegroundColor Yellow
    $answer = Read-Host
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host 'Bailed out. No rickroll today.'
        return
    }
}

$steps = @(Get-RickrollStep -Plan $plan)
$created = 0

try {
    $onLog = {
        param($message, $level)
        Write-Host ("  {0}" -f $message) -ForegroundColor DarkGray
    }

    foreach ($step in $steps) {
        $result = Invoke-RickrollStep -Step $step -Plan $plan -OnLog $onLog
        if ($result.DesktopCreated) { $created++ }
        Start-Sleep -Milliseconds $step.DelayMs
    }

    Write-Host ''
    Write-Host ("Rickroll is live: {0} window(s) on {1} desktop(s)." -f $plan.Windows, ($created + 1)) -ForegroundColor Magenta
    Write-Host 'Ctrl+C to stop, or run Stop-Rickroll.cmd from another window.' -ForegroundColor Magenta

    $deadline = (Get-Date).AddSeconds($DurationSeconds)
    while ($true) {
        $left = [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
        if ($left -le 0) { break }
        Write-Host ("  {0,4}s of rickrolling left" -f $left) -ForegroundColor DarkMagenta
        Start-Sleep -Seconds ([Math]::Min(10, $left))
    }
}
finally {
    Write-Host ''
    Write-Host 'Cleaning up...' -ForegroundColor Cyan
    $closed = Stop-RickrollPrank -ProfileDir $plan.ProfileDir -DesktopsToClose $created
    Write-Host ("  closed {0} browser process(es)" -f $closed) -ForegroundColor DarkGray
    Write-Host 'Done. You know the rules, and so do I.' -ForegroundColor Cyan
}
