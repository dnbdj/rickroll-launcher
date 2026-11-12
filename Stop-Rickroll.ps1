#Requires -Version 5.1
<#
.SYNOPSIS
    Panic button: closes the prank browser windows and the virtual desktops they
    were opened on. Works from a console even while Launcher.ps1 is running.

.PARAMETER KeepDesktops
    Leave the extra virtual desktops in place; only close the windows.

.PARAMETER KeepProfile
    Keep the throwaway browser profile in %TEMP%\rickroll-profile.

.EXAMPLE
    .\Stop-Rickroll.ps1

.EXAMPLE
    .\Stop-Rickroll.ps1 -KeepDesktops
#>
[CmdletBinding()]
param(
    [switch]$KeepDesktops,
    [switch]$KeepProfile
)

$ErrorActionPreference = 'Continue'
Import-Module -Name (Join-Path $PSScriptRoot 'Rickroll.Core.psm1') -Force

$desktops = Get-RickrollDesktopCount

$closed = 0
try {
    $closed = Stop-RickrollPrank -DesktopsToClose $desktops -KeepDesktops:$KeepDesktops -KeepProfile:$KeepProfile
}
catch {
    Write-Warning $_.Exception.Message
}

if ($closed -gt 0) {
    Write-Host ("Closed {0} prank browser process(es)." -f $closed) -ForegroundColor Green
}
else {
    Write-Host 'No prank windows found.' -ForegroundColor DarkGray
}

if (-not $KeepDesktops -and $desktops -gt 0) {
    Write-Host ("Closed {0} virtual desktop(s); stay off any desktop you want to keep." -f $desktops) -ForegroundColor Green
}

Write-Host 'All clear.' -ForegroundColor Green
