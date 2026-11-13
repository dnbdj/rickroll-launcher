#Requires -Version 5.1
<#
.SYNOPSIS
    Rickroll Launcher - a dark, tabbed front-end for the prank engine.

.DESCRIPTION
    Window chrome with minimise / maximise / close, a sidebar of pages
    (Prank, Logs, Leaderboard, Updates), live channels of logs with a browser
    dropdown, and a "..." menu with a global panic hotkey.

    All prank logic lives in Rickroll.Core.psm1; the custom-drawn controls live
    in Rickroll.UI.ps1. This script is the window and the wiring.

.PARAMETER SelfTest
    Build and show the window briefly, then close it. Proves the UI renders
    without opening a single prank window.

.EXAMPLE
    .\Launcher.ps1

.EXAMPLE
    .\Launcher.ps1 -SelfTest
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [int]$SelfTestMs = 1500
)

$ErrorActionPreference = 'Stop'

trap {
    $message = "LAUNCHER ERROR $((Get-Date).ToString('s'))`r`n$($_.Exception.Message)`r`n$($_.ScriptStackTrace)"
    try { Set-Content -LiteralPath (Join-Path $PSScriptRoot 'launcher-error.log') -Value $message -Encoding UTF8 } catch { }
    Write-Host $message -ForegroundColor Red
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

. (Join-Path $PSScriptRoot 'Rickroll.UI.ps1')
Import-Module -Name (Join-Path $PSScriptRoot 'Rickroll.Core.psm1') -Force

# -------------------------------------------------------------------- scaling

$script:Scale = 1.0
try {
    $screenGraphics = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $script:Scale = [double]$screenGraphics.DpiX / 96.0
    $screenGraphics.Dispose()
}
catch {
    $script:Scale = 1.0
}
if ($script:Scale -le 0.1) { $script:Scale = 1.0 }

function U([double]$value) {
    return [int][Math]::Round($value * $script:Scale)
}

function ToColor([string]$hex) {
    if ([string]::IsNullOrEmpty($hex)) { return [System.Drawing.Color]::Transparent }
    return [System.Drawing.ColorTranslator]::FromHtml($hex)
}

$script:Palette = @{
    Bg       = '#0E0F15'
    Sidebar  = '#11121A'
    Card     = '#161824'
    Inner    = '#1B1E2C'
    Stroke   = '#272A3C'
    Text     = '#E8E9F0'
    Muted    = '#8A8FA6'
    Accent   = '#FF2E74'
    AccentHi = '#FF4E8B'
    AccentLo = '#D6215E'
    LiveBg   = '#241C2C'
    LiveLine = '#4A2340'
    Danger   = '#FF6B6B'
    DangerHi = '#2A1B22'
    Hover    = '#232739'
}

$script:G = @{
    Dot    = [string][char]0x00B7
    Bullet = [string][char]0x25CF
    Check  = [string][char]0x2713
    Play   = [string][char]0x25B6
    Square = [string][char]0x25A0
    Minus  = [string][char]0x2212
    Caret  = [string][char]0x25BE
}

$script:AppVersion = '1.0.8'

# -------------------------------------------------------------------- widgets

function Get-UiFont {
    param([double]$Size = 9, [string]$Style = 'Regular')
    if ($Style -eq 'Semibold') {
        try { return [System.Drawing.Font]::new('Segoe UI Semibold', [single]$Size) }
        catch { return [System.Drawing.Font]::new('Segoe UI', [single]$Size, [System.Drawing.FontStyle]::Bold) }
    }
    return [System.Drawing.Font]::new('Segoe UI', [single]$Size, [System.Drawing.FontStyle]$Style)
}

function New-Label {
    param(
        [string]$Text = '',
        [double]$X = 0,
        [double]$Y = 0,
        [double]$W = 100,
        [double]$H = 20,
        [double]$Size = 9,
        [string]$Style = 'Regular',
        [string]$Color = '#E8E9F0',
        [string]$Back = '#0E0F15',
        [string]$Align = 'MiddleLeft'
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $false
    $label.Bounds = [System.Drawing.Rectangle]::new((U $X), (U $Y), (U $W), (U $H))
    $label.Font = Get-UiFont -Size $Size -Style $Style
    $label.ForeColor = ToColor $Color
    $label.BackColor = ToColor $Back
    $label.TextAlign = [System.Drawing.ContentAlignment]$Align
    return $label
}

function New-RoundButton {
    param(
        [string]$Text = '',
        [double]$X = 0,
        [double]$Y = 0,
        [double]$W = 100,
        [double]$H = 34,
        [double]$Radius = 12,
        [string]$Fill = '#1B1E2C',
        [string]$Hover = '#2A2E44',
        [string]$Press = '#22263A',
        [string]$TextColor = '#E8E9F0',
        [string]$Border = '',
        [double]$Size = 10,
        [string]$Style = 'Regular'
    )

    $button = New-Object Rickroll.UI.RoundButton
    $button.Text = $Text
    $button.Bounds = [System.Drawing.Rectangle]::new((U $X), (U $Y), (U $W), (U $H))
    $button.Radius = (U $Radius)
    $button.FillColor = ToColor $Fill
    $button.HoverFill = ToColor $Hover
    $button.PressFill = ToColor $Press
    $button.ForeColor = ToColor $TextColor
    $button.BorderColor = ToColor $Border
    $button.Font = Get-UiFont -Size $Size -Style $Style
    return $button
}

function New-Card {
    param(
        [double]$X = 0,
        [double]$Y = 0,
        [double]$W = 200,
        [double]$H = 120,
        [double]$Radius = 14,
        [string]$Fill = '#161824',
        [string]$Border = '#272A3C'
    )

    $card = New-Object Rickroll.UI.RoundPanel
    $card.Bounds = [System.Drawing.Rectangle]::new((U $X), (U $Y), (U $W), (U $H))
    $card.Radius = (U $Radius)
    $card.FillColor = ToColor $Fill
    $card.BorderColor = ToColor $Border
    return $card
}

function New-CaptionButton {
    param(
        [string]$Glyph = 'min',
        [double]$X = 0,
        [double]$Y = 0,
        [double]$W = 40,
        [double]$H = 30,
        [string]$Hover = '#232739',
        [string]$GlyphColor = '#969CB0',
        [string]$HoverGlyph = '#FFFFFF'
    )

    $button = New-Object Rickroll.UI.CaptionButton
    $button.Glyph = $Glyph
    $button.Bounds = [System.Drawing.Rectangle]::new((U $X), (U $Y), (U $W), (U $H))
    $button.HoverFill = ToColor $Hover
    $button.GlyphColor = ToColor $GlyphColor
    $button.HoverGlyphColor = ToColor $HoverGlyph
    return $button
}

function New-Dropdown {
    param(
        [string[]]$Items = @(),
        [int]$SelectedIndex = 0,
        [double]$X = 0,
        [double]$Y = 0,
        [double]$W = 180
    )

    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $combo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $combo.BackColor = ToColor $script:Palette.Inner
    $combo.ForeColor = ToColor $script:Palette.Text
    $combo.Font = Get-UiFont -Size 9
    $combo.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $combo.ItemHeight = (U 19)
    $combo.Bounds = [System.Drawing.Rectangle]::new((U $X), (U $Y), (U $W), (U 26))
    foreach ($item in $Items) { [void]$combo.Items.Add($item) }
    if ($combo.Items.Count -gt 0) { $combo.SelectedIndex = $SelectedIndex }

    $combo.add_DrawItem({
        param($sender, $e)
        if ($e.Index -lt 0) { return }
        $isSelected = (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0)
        $background = New-Object System.Drawing.SolidBrush((ToColor ($(if ($isSelected) { '#2A2E44' } else { $script:Palette.Inner }))))
        $e.Graphics.FillRectangle($background, $e.Bounds)
        $background.Dispose()
        $text = New-Object System.Drawing.SolidBrush((ToColor $script:Palette.Text))
        $e.Graphics.DrawString([string]$sender.Items[$e.Index], $e.Font, $text, ($e.Bounds.X + (U 8)), ($e.Bounds.Y + (U 2)))
        $text.Dispose()
    })

    return $combo
}

function Get-LevelColor {
    param([string]$Level)
    switch ($Level) {
        'ok'    { return '#4ADE80' }
        'warn'  { return '#FBBF24' }
        'err'   { return '#FF6B6B' }
        'quiet' { return '#7C8299' }
        default { return '#C3C8D8' }
    }
}

# --------------------------------------------------------------------- state

$script:SettingsPath = Join-Path $PSScriptRoot 'settings.json'

$script:Opts = @{
    Windows      = 8
    Desktops     = 3
    Hotkey       = 'Ctrl+Alt+Q'
    KeepDesktops = $false
    UpdateUrl    = 'https://api.github.com/repos/dnbdj/rickroll-launcher/releases'
}

$script:State = @{
    Running         = $false
    Plan            = $null
    Queue           = $null
    DesktopsCreated = 0
    StartedAt       = $null
}

$script:LogChannels = @{}
foreach ($channel in @('All', 'App', 'Prank', 'Errors')) {
    $script:LogChannels[$channel] = New-Object System.Collections.ArrayList
}
$script:SelectedLog = 'All'

$script:UI = @{
    Values           = @{}
    Steppers         = @()
    Pages            = @{}
    NavButtons       = @{}
    CurrentPage      = 'Prank'
    HotkeyRegistered = $false
    NavGlyphs        = @{}
    NavBar           = $null
    BoardRows        = @()
    BoardStatValues  = @{}
    BoardEmpty       = $null
}

$script:HotkeyMap = [ordered]@{
    'Ctrl+Alt+Q'       = @{ Mod = 0x0001 -bor 0x0002; Vk = 0x51 }
    'Ctrl+Alt+X'       = @{ Mod = 0x0001 -bor 0x0002; Vk = 0x58 }
    'Ctrl+Alt+Z'       = @{ Mod = 0x0001 -bor 0x0002; Vk = 0x5A }
    'Ctrl+Shift+Alt+Q' = @{ Mod = 0x0001 -bor 0x0002 -bor 0x0004; Vk = 0x51 }
    'None'             = $null
}

function Import-Settings {
    if (-not (Test-Path -LiteralPath $script:SettingsPath)) { return }
    try {
        $saved = Get-Content -Raw -LiteralPath $script:SettingsPath | ConvertFrom-Json
        foreach ($key in @('Windows', 'Desktops', 'Hotkey', 'KeepDesktops', 'UpdateUrl')) {
            if ($saved.PSObject.Properties.Name -contains $key) { $script:Opts[$key] = $saved.$key }
        }
    }
    catch { }
}

function Save-Settings {
    try {
        $script:Opts | ConvertTo-Json | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
    }
    catch { }
}

# ---------------------------------------------------------------- leaderboard

$script:BoardPath = Join-Path $PSScriptRoot 'leaderboard.json'
$script:Board = @{ Runs = @() }

function Import-Board {
    if (-not (Test-Path -LiteralPath $script:BoardPath)) { return }
    try {
        $saved = Get-Content -Raw -LiteralPath $script:BoardPath | ConvertFrom-Json
        if ($saved.PSObject.Properties.Name -contains 'Runs') {
            $script:Board.Runs = @($saved.Runs | Where-Object { $null -ne $_ })
        }
    }
    catch { }
}

function Save-Board {
    try {
        @{ Runs = @($script:Board.Runs) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:BoardPath -Encoding UTF8
    }
    catch { }
}

function Format-BoardDuration {
    param([int]$Seconds)

    if ($Seconds -le 0) { return '0s' }
    if ($Seconds -lt 60) { return ("{0}s" -f $Seconds) }
    $minutes = [int][Math]::Floor($Seconds / 60)
    if ($minutes -lt 60) { return ("{0}m {1:00}s" -f $minutes, ($Seconds % 60)) }
    return ("{0}h {1:00}m" -f [int][Math]::Floor($minutes / 60), ($minutes % 60))
}

function Add-BoardRun {
    param(
        [int]$Windows = 0,
        [int]$Seconds = 0,
        [int]$Desktops = 0,
        [bool]$Forced = $false
    )

    if ($Windows -le 0 -and $Seconds -le 0) { return }

    $run = [pscustomobject]@{
        At       = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        Windows  = $Windows
        Seconds  = $Seconds
        Desktops = $Desktops
        Forced   = $Forced
    }

    $runs = New-Object System.Collections.ArrayList
    [void]$runs.Add($run)
    foreach ($old in @($script:Board.Runs)) { [void]$runs.Add($old) }
    while ($runs.Count -gt 50) { $runs.RemoveAt($runs.Count - 1) }

    $script:Board.Runs = $runs.ToArray()
    Save-Board
    Update-Board
}

function Clear-Board {
    $script:Board.Runs = @()
    Save-Board
    Update-Board
    Add-Log 'Leaderboard cleared.' 'quiet' 'App'
}

function Update-Board {
    if ($script:UI.BoardStatValues.Count -eq 0) { return }

    $runs = @($script:Board.Runs)
    $best = 0
    $longest = 0
    $totalWindows = 0
    foreach ($run in $runs) {
        if ([int]$run.Windows -gt $best) { $best = [int]$run.Windows }
        if ([int]$run.Seconds -gt $longest) { $longest = [int]$run.Seconds }
        $totalWindows += [int]$run.Windows
    }

    $script:UI.BoardStatValues['Runs'].Text = [string]$runs.Count
    $script:UI.BoardStatValues['Best'].Text = [string]$best
    $script:UI.BoardStatValues['Longest'].Text = (Format-BoardDuration $longest)
    $script:UI.BoardStatValues['Windows'].Text = [string]$totalWindows

    for ($i = 0; $i -lt $script:UI.BoardRows.Count; $i++) {
        $labels = $script:UI.BoardRows[$i]
        if ($i -lt $runs.Count) {
            $run = $runs[$i]
            $labels['When'].Text = [string]$run.At
            $labels['Windows'].Text = ("{0} windows" -f $run.Windows)
            $labels['Duration'].Text = (Format-BoardDuration ([int]$run.Seconds))
            foreach ($part in $labels.Values) { $part.Visible = $true }
        }
        else {
            foreach ($part in $labels.Values) { $part.Visible = $false }
        }
    }

    if ($script:UI.BoardEmpty) { $script:UI.BoardEmpty.Visible = ($runs.Count -eq 0) }
}

# --------------------------------------------------------------------- form

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Rickroll Launcher'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.ClientSize = [System.Drawing.Size]::new((U 900), (U 620))
$form.MinimumSize = [System.Drawing.Size]::new((U 820), (U 560))
$form.BackColor = ToColor $script:Palette.Bg
$form.ForeColor = ToColor $script:Palette.Text
$form.ShowIcon = $false
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.KeyPreview = $true

function Update-FormRegion {
    if ($script:IsMaximized) {
        $form.Region = $null
        return
    }
    if ($form.Width -le 0 -or $form.Height -le 0) { return }
    $form.Region = [System.Drawing.Region]::new(
        [Rickroll.UI.Shapes]::Rounded([System.Drawing.Rectangle]::new(0, 0, $form.Width, $form.Height), (U 16)))
}

# --- chrome panels (order matters: WinForms docks the last added first) ---

$contentHost = New-Object System.Windows.Forms.Panel
$contentHost.Dock = [System.Windows.Forms.DockStyle]::Fill
$contentHost.BackColor = ToColor $script:Palette.Bg

# The rail is a fixed strip; the nav floats above it so the labels can widen
# over the page instead of reflowing it.
$navRail = New-Object System.Windows.Forms.Panel
$navRail.Dock = [System.Windows.Forms.DockStyle]::Left
$navRail.Width = (U 64)
$navRail.BackColor = ToColor $script:Palette.Sidebar

$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Dock = [System.Windows.Forms.DockStyle]::None
$sidebar.Width = (U 64)
$sidebar.BackColor = ToColor $script:Palette.Sidebar

$statusBar = New-Object System.Windows.Forms.Panel
$statusBar.Dock = [System.Windows.Forms.DockStyle]::Bottom
$statusBar.Height = (U 30)
$statusBar.BackColor = ToColor $script:Palette.Bg

$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.Dock = [System.Windows.Forms.DockStyle]::Top
$titleBar.Height = (U 52)
$titleBar.BackColor = ToColor $script:Palette.Bg

$form.Controls.Add($contentHost)
$form.Controls.Add($navRail)
$form.Controls.Add($statusBar)
$form.Controls.Add($titleBar)
$form.Controls.Add($sidebar)
$form.PerformLayout()
Update-FormRegion

# --- dragging and maximising ---

$script:DragAnchor = $null
$script:DragStart = $null
$script:IsMaximized = $false
$script:RestoreBounds = $null

$dragDown = {
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($script:IsMaximized) { return }
        $script:DragAnchor = [System.Windows.Forms.Cursor]::Position
        $script:DragStart = $form.Location
    }
}
$dragMove = {
    param($sender, $e)
    if ($script:DragAnchor -ne $null) {
        $point = [System.Windows.Forms.Cursor]::Position
        $form.Location = [System.Drawing.Point]::new(
            ($script:DragStart.X + $point.X - $script:DragAnchor.X),
            ($script:DragStart.Y + $point.Y - $script:DragAnchor.Y))
    }
}
$dragUp = { $script:DragAnchor = $null }

$titleLabel = New-Label -Text 'Rickroll' -X 18 -Y 6 -W 180 -H 26 -Size 13 -Style Semibold -Color $script:Palette.Text
$subtitleLabel = New-Label -Text 'prank launcher' -X 18 -Y 29 -W 240 -H 16 -Size 8 -Color $script:Palette.Muted
$titleLine = New-Card -X 0 -Y 51 -W 900 -H 1 -Radius 0 -Fill '#1E2032' -Border ''
$titleLine.Anchor = 'Bottom,Left,Right'

$minButton = New-CaptionButton -Glyph 'min' -X 764 -Y 11
$maxButton = New-CaptionButton -Glyph 'max' -X 804 -Y 11
$closeButton = New-CaptionButton -Glyph 'close' -X 844 -Y 11 -Hover '#E81123' -GlyphColor '#A9AFC4' -HoverGlyph '#FFFFFF'
foreach ($button in @($minButton, $maxButton, $closeButton)) { $button.Anchor = 'Top,Right' }

$titleBar.Controls.Add($titleLabel)
$titleBar.Controls.Add($subtitleLabel)
$titleBar.Controls.Add($titleLine)
$titleBar.Controls.Add($minButton)
$titleBar.Controls.Add($maxButton)
$titleBar.Controls.Add($closeButton)

function Set-Maximized {
    param([switch]$On)
    if ($On) {
        $script:RestoreBounds = $form.Bounds
        $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
        $form.Bounds = $workArea
        $script:IsMaximized = $true
        $maxButton.SetGlyph('restore')
    }
    else {
        $script:IsMaximized = $false
        if ($script:RestoreBounds) { $form.Bounds = $script:RestoreBounds }
        $maxButton.SetGlyph('max')
    }
    Update-FormRegion
}

$titleBar.add_MouseDown($dragDown)
$titleBar.add_MouseMove($dragMove)
$titleBar.add_MouseUp($dragUp)
$titleLabel.add_MouseDown($dragDown)
$titleLabel.add_MouseMove($dragMove)
$titleLabel.add_MouseUp($dragUp)
$subtitleLabel.add_MouseDown($dragDown)
$subtitleLabel.add_MouseMove($dragMove)
$subtitleLabel.add_MouseUp($dragUp)

$captionDoubleClick = {
    param($sender, $e)
    if ($script:IsMaximized) { Set-Maximized } else { Set-Maximized -On }
}
$titleBar.add_DoubleClick($captionDoubleClick)
$titleLabel.add_DoubleClick($captionDoubleClick)
$subtitleLabel.add_DoubleClick($captionDoubleClick)

# --- sidebar navigation ---

$navItems = @(
    @{ Key = 'Prank'; Glyph = $script:G.Play },
    @{ Key = 'Logs'; Glyph = [string][char]0x2261 },
    @{ Key = 'Leaderboard'; Glyph = [string][char]0x2605 },
    @{ Key = 'Updates'; Glyph = [string][char]0x21BB }
)

$navIndex = 0
foreach ($navItem in $navItems) {
    # Icon only; Set-NavExpanded adds the word while the pointer is on the rail.
    $navButton = New-RoundButton -Text ([string]$navItem.Glyph) -X 10 -Y (14 + ($navIndex * 44)) -W 44 -H 38 -Radius 10 -Fill $script:Palette.Sidebar -Hover $script:Palette.Hover -Press $script:Palette.Hover -TextColor $script:Palette.Muted -Size 11
    $navButton.Tag = $navItem.Key
    $navButton.add_Click({
        param($sender, $e)
        Show-Page -Key ([string]$sender.Tag)
        $script:NavSuppressed = $true
        Set-NavExpanded -On:$false
    })
    $sidebar.Controls.Add($navButton)
    $script:UI.NavButtons[$navItem.Key] = $navButton
    $script:UI.NavGlyphs[$navItem.Key] = [string]$navItem.Glyph
    $navIndex++
}

$script:UI.NavBar = New-Card -X 4 -Y 24 -W 3 -H 18 -Radius 2 -Fill $script:Palette.Accent -Border ''
$sidebar.Controls.Add($script:UI.NavBar)

$menuButton = New-RoundButton -Text '...' -X 10 -Y ($sidebar.Height - (U 84)) -W 44 -H 32 -Radius 9 -Fill $script:Palette.Sidebar -Hover $script:Palette.Hover -Press $script:Palette.Hover -TextColor $script:Palette.Muted -Size 11 -Style Bold
$sidebar.Controls.Add($menuButton)

$sidebarVersion = New-Label -Text ("v{0}" -f $script:AppVersion) -X 10 -Y ($sidebar.Height - (U 46)) -W 44 -H 20 -Size 7.5 -Color $script:Palette.Muted -Back $script:Palette.Sidebar -Align 'MiddleCenter'
$sidebar.Controls.Add($sidebarVersion)

# --- nav rail: icons at rest, words while hovered --------------------------

$script:NavExpanded = $false
# A click collapses the rail even though the pointer is still on it; the next
# time the pointer leaves, that suppression clears.
$script:NavSuppressed = $false

function Update-NavRail {
    if ($null -eq $sidebar) { return }
    $height = $form.ClientSize.Height - $titleBar.Height - $statusBar.Height
    if ($height -lt 1) { return }
    $sidebar.Bounds = [System.Drawing.Rectangle]::new(0, $titleBar.Height, $sidebar.Width, $height)
    $menuButton.Top = $sidebar.ClientSize.Height - (U 84)
    $sidebarVersion.Top = $sidebar.ClientSize.Height - (U 46)
    $sidebar.BringToFront()
}

function Test-NavHover {
    # The watch timer can tick once more while the form is closing.
    if ($null -eq $sidebar -or $sidebar.IsDisposed) { return $false }
    $point = [System.Windows.Forms.Cursor]::Position
    $rect = $sidebar.RectangleToScreen($sidebar.ClientRectangle)
    return $rect.Contains($point)
}

function Set-NavExpanded {
    param([switch]$On)
    if ([bool]$On -eq $script:NavExpanded) { return }
    $script:NavExpanded = [bool]$On

    $inset = if ($On) { (U 14) } else { (U 10) }
    $buttonWidth = if ($On) { (U 148) } else { (U 44) }
    foreach ($key in @($script:UI.NavButtons.Keys)) {
        $button = $script:UI.NavButtons[$key]
        $glyph = $script:UI.NavGlyphs[$key]
        $button.Text = if ($On) { ("{0}  {1}" -f $glyph, $key) } else { $glyph }
        $button.Bounds = [System.Drawing.Rectangle]::new($inset, $button.Top, $buttonWidth, $button.Height)
        $button.Invalidate()
    }

    $menuButton.Left = $inset
    $menuButton.Width = $buttonWidth
    $sidebarVersion.Left = $inset
    $sidebarVersion.Width = $buttonWidth
    $script:UI.NavBar.Left = if ($On) { (U 5) } else { (U 4) }

    $sidebar.Width = if ($On) { (U 176) } else { (U 64) }
    Update-NavRail
}

# Watching the pointer beats MouseEnter/MouseLeave here: moving between the
# rail and its own buttons fires leave on the panel, and leaving a button
# straight out of the window may fire nothing at all.
$script:NavWatch = New-Object System.Windows.Forms.Timer
$script:NavWatch.Interval = 120
$script:NavWatch.add_Tick({
    if ($null -eq $sidebar -or $sidebar.IsDisposed) { $script:NavWatch.Stop(); return }
    $hovered = Test-NavHover
    if (-not $hovered) { $script:NavSuppressed = $false }
    $want = $hovered -and (-not $script:NavSuppressed)
    if ($want -ne $script:NavExpanded) { Set-NavExpanded -On:$want }
})
$script:NavWatch.Start()

# --- status bar ---

$statusLine = New-Card -X 0 -Y 0 -W 900 -H 1 -Radius 0 -Fill '#1E2032' -Border ''
$statusLine.Anchor = 'Top,Left,Right'
$statusBar.Controls.Add($statusLine)

$statusDot = New-Card -X 18 -Y 10 -W 10 -H 10 -Radius 5 -Fill $script:Palette.Muted -Border ''
$statusBar.Controls.Add($statusDot)

$statusLabel = New-Label -Text 'Idle' -X 36 -Y 3 -W 420 -H 24 -Size 9 -Color $script:Palette.Muted
$statusBar.Controls.Add($statusLabel)

$hotkeyLabel = New-Label -Text '' -X 600 -Y 3 -W 230 -H 24 -Size 8 -Color $script:Palette.Muted -Align 'MiddleRight'
$hotkeyLabel.Anchor = 'Top,Right'
$statusBar.Controls.Add($hotkeyLabel)

# --------------------------------------------------------------------- pages

function New-Page {
    param([string]$Key)
    # Visible on purpose: a hidden page never lays out, which leaves anchored
    # children with a stale baseline and makes them balloon once it is shown.
    $page = New-Object System.Windows.Forms.Panel
    $page.Dock = [System.Windows.Forms.DockStyle]::Fill
    $page.BackColor = ToColor $script:Palette.Bg
    $page.Visible = $true
    $contentHost.Controls.Add($page)
    $script:UI.Pages[$Key] = $page
    return $page
}

function New-Stepper {
    param(
        [string]$Key,
        [string]$Label,
        [int]$Min = 0,
        [int]$Max = 10,
        [int]$Step = 1,
        [double]$X = 0,
        [double]$Y = 0,
        [double]$W = 96
    )

    $box = New-Card -X $X -Y $Y -W $W -H 70 -Radius 12 -Fill $script:Palette.Inner
    $box.Controls.Add((New-Label -Text $Label.ToUpper() -X 9 -Y 6 -W ($W - 18) -H 16 -Size 7 -Color $script:Palette.Muted -Back $script:Palette.Inner))

    $minus = New-RoundButton -Text $script:G.Minus -X 8 -Y 34 -W 22 -H 24 -Radius 7 -Fill $script:Palette.Inner -Hover $script:Palette.Hover -Press $script:Palette.Hover -TextColor $script:Palette.Text -Size 11 -Style Bold
    $plus = New-RoundButton -Text '+' -X ($W - 30) -Y 34 -W 22 -H 24 -Radius 7 -Fill $script:Palette.Inner -Hover $script:Palette.Hover -Press $script:Palette.Hover -TextColor $script:Palette.Text -Size 11 -Style Bold
    $value = New-Label -Text ([string]$script:Opts[$Key]) -X 32 -Y 32 -W ($W - 64) -H 28 -Size 10.5 -Style Semibold -Align 'MiddleCenter' -Back $script:Palette.Inner

    $stepHandler = {
        param($sender, $e)
        if ($sender.Text -eq $script:G.Minus) { $delta = -$Step } else { $delta = $Step }
        $next = [int]$script:Opts[$Key] + $delta
        if ($next -lt $Min) { $next = $Min }
        if ($next -gt $Max) { $next = $Max }
        $script:Opts[$Key] = $next
        $script:UI.Values[$Key].Text = [string]$next
        Save-Settings
        Update-PlanInfo
    }
    $minus.add_Click($stepHandler)
    $plus.add_Click($stepHandler)

    $box.Controls.Add($minus)
    $box.Controls.Add($plus)
    $box.Controls.Add($value)

    $script:UI.Values[$Key] = $value
    $script:UI.Steppers += $box
    return $box
}

# --- Prank page ---

$prankPage = New-Page -Key 'Prank'

$controlCard = New-Card -X 16 -Y 16 -W 700 -H 98
$controlCard.Anchor = 'Top,Left,Right'
$prankPage.Controls.Add($controlCard)

$startButton = New-RoundButton -Text ("{0}  Start prank" -f $script:G.Play) -X 16 -Y 18 -W 186 -H 60 -Radius 14 -Fill $script:Palette.Accent -Hover $script:Palette.AccentHi -Press $script:Palette.AccentLo -TextColor '#FFFFFF' -Size 11.5 -Style Semibold
$controlCard.Controls.Add($startButton)

$forceButton = New-RoundButton -Text 'Force stop' -X 214 -Y 18 -W 140 -H 60 -Radius 14 -Fill $script:Palette.Inner -Hover $script:Palette.DangerHi -Press $script:Palette.DangerHi -TextColor $script:Palette.Danger -Border '#3A2730' -Size 10 -Style Semibold
$controlCard.Controls.Add($forceButton)

$windowsStepper = New-Stepper -Key 'Windows' -Label 'Windows' -Min 1 -Max 40 -Step 1 -X 474 -Y 14
$desktopsStepper = New-Stepper -Key 'Desktops' -Label 'Desktops' -Min 0 -Max 8 -Step 1 -X 580 -Y 14
foreach ($stepper in @($windowsStepper, $desktopsStepper)) {
    $stepper.Anchor = 'Top,Right'
    $controlCard.Controls.Add($stepper)
}

$infoCard = New-Card -X 16 -Y 126 -W 700 -H 396
$infoCard.Anchor = 'Top,Bottom,Left,Right'
$prankPage.Controls.Add($infoCard)

$infoRows = @(
    @{ Key = 'Plan'; Label = 'PLAN'; Value = '8 windows across 4 desktops (3 new)' },
    @{ Key = 'Video'; Label = 'VIDEO'; Value = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ&autoplay=1' },
    @{ Key = 'Profile'; Label = 'PROFILE'; Value = '' },
    @{ Key = 'Hotkey'; Label = 'PANIC HOTKEY'; Value = '' }
)

$rowY = 18
foreach ($row in $infoRows) {
    $infoCard.Controls.Add((New-Label -Text $row.Label -X 20 -Y $rowY -W 200 -H 16 -Size 7 -Color $script:Palette.Muted -Back $script:Palette.Card))
    $valueLabel = New-Label -Text $row.Value -X 20 -Y ($rowY + 18) -W 660 -H 22 -Size 9 -Color '#BFC4D6' -Back $script:Palette.Card
    $valueLabel.Anchor = 'Top,Left,Right'
    $infoCard.Controls.Add($valueLabel)
    $script:UI[$row.Key + 'Value'] = $valueLabel
    $rowY += 62
}

$infoHint = New-Label -Text 'Panic hotkey works from any desktop, including the ones the prank creates.' -X 20 -Y 292 -W 660 -H 40 -Size 8 -Color $script:Palette.Muted -Back $script:Palette.Card -Align 'TopLeft'
$infoHint.Anchor = 'Top,Left,Right'
$infoCard.Controls.Add($infoHint)

# --- Logs page ---

$logsPage = New-Page -Key 'Logs'

$logCard = New-Card -X 16 -Y 16 -W 700 -H 506
$logCard.Anchor = 'Top,Bottom,Left,Right'
$logsPage.Controls.Add($logCard)
$logCard.Controls.Add((New-Label -Text 'Logs' -X 18 -Y 12 -W 54 -H 26 -Size 10.5 -Style Semibold -Back $script:Palette.Card))

$logSelect = New-Dropdown -Items @('All activity', 'App', 'Prank', 'Errors') -SelectedIndex 0 -X 74 -Y 12 -W 178
$logSelect.Anchor = 'Top,Left'
$logCard.Controls.Add($logSelect)

$copyButton = New-RoundButton -Text 'Copy' -X 556 -Y 13 -W 64 -H 26 -Radius 8 -Fill $script:Palette.Card -Hover $script:Palette.Hover -Press $script:Palette.Hover -TextColor $script:Palette.Muted -Size 8
$copyButton.Anchor = 'Top,Right'
$logCard.Controls.Add($copyButton)

$clearButton = New-RoundButton -Text 'Clear' -X 628 -Y 13 -W 54 -H 26 -Radius 8 -Fill $script:Palette.Card -Hover $script:Palette.Hover -Press $script:Palette.Hover -TextColor $script:Palette.Muted -Size 8
$clearButton.Anchor = 'Top,Right'
$logCard.Controls.Add($clearButton)

$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.Bounds = [System.Drawing.Rectangle]::new((U 12), (U 50), (U 676), (U 444))
$logBox.Anchor = 'Top,Bottom,Left,Right'
$logBox.BackColor = ToColor '#101220'
$logBox.ForeColor = ToColor $script:Palette.Text
$logBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$logBox.Font = [System.Drawing.Font]::new('Consolas', [single]9)
$logBox.ReadOnly = $true
$logBox.WordWrap = $false
$logBox.DetectUrls = $false
$logBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$logBox.HideSelection = $false
$logCard.Controls.Add($logBox)

# --- Leaderboard page ---

$boardPage = New-Page -Key 'Leaderboard'

$boardCard = New-Card -X 16 -Y 16 -W 700 -H 506
$boardCard.Anchor = 'Top,Bottom,Left,Right'
$boardPage.Controls.Add($boardCard)
$boardCard.Controls.Add((New-Label -Text 'Leaderboard' -X 18 -Y 14 -W 200 -H 26 -Size 10.5 -Style Semibold -Back $script:Palette.Card))

$localBadge = New-Card -X 612 -Y 16 -W 70 -H 22 -Radius 11 -Fill $script:Palette.Inner
$localBadge.Anchor = 'Top,Right'
$localBadge.Controls.Add((New-Label -Text 'ON THIS PC' -X 0 -Y 0 -W 70 -H 22 -Size 7 -Style Semibold -Color $script:Palette.Muted -Back $script:Palette.Inner -Align 'MiddleCenter'))
$boardCard.Controls.Add($localBadge)

$boardReset = New-RoundButton -Text 'Reset' -X 526 -Y 16 -W 76 -H 22 -Radius 11 -Fill $script:Palette.Inner -Hover $script:Palette.Hover -Press $script:Palette.Hover -TextColor $script:Palette.Muted -Border $script:Palette.Stroke -Size 8
$boardReset.Anchor = 'Top,Right'
$boardReset.add_Click({
    $answer = [System.Windows.Forms.MessageBox]::Show(
        'Clear the leaderboard? This cannot be undone.',
        'Reset leaderboard', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) { Clear-Board }
})
$boardCard.Controls.Add($boardReset)

$statX = 18
foreach ($statDef in @(
    @{ Key = 'Runs'; Caption = 'RUNS' },
    @{ Key = 'Best'; Caption = 'BEST RUN' },
    @{ Key = 'Longest'; Caption = 'LONGEST RUN' },
    @{ Key = 'Windows'; Caption = 'WINDOWS OPENED' }
)) {
    $boardCard.Controls.Add((New-Label -Text $statDef.Caption -X $statX -Y 58 -W 160 -H 14 -Size 7 -Color $script:Palette.Muted -Back $script:Palette.Card))
    $statValue = New-Label -Text '-' -X $statX -Y 74 -W 160 -H 28 -Size 14 -Style Semibold -Color $script:Palette.Text -Back $script:Palette.Card
    $boardCard.Controls.Add($statValue)
    $script:UI.BoardStatValues[$statDef.Key] = $statValue
    $statX += 168
}

$boardCard.Controls.Add((New-Label -Text 'RECENT RUNS' -X 18 -Y 120 -W 300 -H 14 -Size 7 -Color $script:Palette.Muted -Back $script:Palette.Card))

$boardEmpty = New-Label -Text 'No runs yet - start the prank, stop it, and it lands here.' -X 18 -Y 152 -W 664 -H 30 -Size 9 -Color $script:Palette.Muted -Back $script:Palette.Card -Align 'MiddleCenter'
$boardCard.Controls.Add($boardEmpty)
$script:UI.BoardEmpty = $boardEmpty

$rowY = 150
for ($rowIndex = 0; $rowIndex -lt 5; $rowIndex++) {
    $boardRow = New-Card -X 18 -Y $rowY -W 664 -H 40 -Radius 9 -Fill $script:Palette.Inner -Border $script:Palette.Stroke
    $boardRow.Anchor = 'Top,Left,Right'
    $boardRow.Visible = $false
    $boardCard.Controls.Add($boardRow)

    $rowWhen = New-Label -Text '' -X 14 -Y 0 -W 240 -H 40 -Size 9 -Color $script:Palette.Text -Back $script:Palette.Inner
    $rowCount = New-Label -Text '' -X 264 -Y 0 -W 220 -H 40 -Size 9 -Color '#BFC4D6' -Back $script:Palette.Inner
    $rowDuration = New-Label -Text '' -X 490 -Y 0 -W 160 -H 40 -Size 9 -Style Semibold -Color $script:Palette.Text -Back $script:Palette.Inner -Align 'MiddleRight'
    foreach ($rowLabel in @($rowWhen, $rowCount, $rowDuration)) { $boardRow.Controls.Add($rowLabel) }

    $script:UI.BoardRows += ,@{ When = $rowWhen; Windows = $rowCount; Duration = $rowDuration; Back = $boardRow }
    $rowY += 46
}

Import-Board
Update-Board

# --- Updates page ---

$updatesPage = New-Page -Key 'Updates'

$updateCard = New-Card -X 16 -Y 16 -W 700 -H 506
$updateCard.Anchor = 'Top,Bottom,Left,Right'
$updatesPage.Controls.Add($updateCard)
$updateCard.Controls.Add((New-Label -Text 'Updates' -X 18 -Y 14 -W 200 -H 26 -Size 10.5 -Style Semibold -Back $script:Palette.Card))

$updateCard.Controls.Add((New-Label -Text 'INSTALLED VERSION' -X 20 -Y 64 -W 240 -H 16 -Size 7 -Color $script:Palette.Muted -Back $script:Palette.Card))
$updateCard.Controls.Add((New-Label -Text $script:AppVersion -X 20 -Y 82 -W 240 -H 24 -Size 11 -Style Semibold -Color $script:Palette.Text -Back $script:Palette.Card))
$updateCard.Controls.Add((New-Label -Text 'LATEST AVAILABLE' -X 300 -Y 64 -W 240 -H 16 -Size 7 -Color $script:Palette.Muted -Back $script:Palette.Card))
$script:UI.LatestValue = New-Label -Text 'not checked' -X 300 -Y 82 -W 240 -H 24 -Size 11 -Style Semibold -Color '#BFC4D6' -Back $script:Palette.Card
$updateCard.Controls.Add($script:UI.LatestValue)

$updateCard.Controls.Add((New-Label -Text 'LAST CHECKED' -X 20 -Y 124 -W 240 -H 16 -Size 7 -Color $script:Palette.Muted -Back $script:Palette.Card))
$script:UI.LastCheckedValue = New-Label -Text 'never' -X 20 -Y 142 -W 240 -H 24 -Size 9 -Color '#BFC4D6' -Back $script:Palette.Card
$updateCard.Controls.Add($script:UI.LastCheckedValue)

$updateButton = New-RoundButton -Text 'Check for updates' -X 20 -Y 196 -W 184 -H 44 -Radius 12 -Fill $script:Palette.Accent -Hover $script:Palette.AccentHi -Press $script:Palette.AccentLo -TextColor '#FFFFFF' -Size 10 -Style Semibold
$updateCard.Controls.Add($updateButton)

$updateArrow = New-RoundButton -Text $script:G.Caret -X 210 -Y 196 -W 40 -H 44 -Radius 12 -Fill $script:Palette.Inner -Hover $script:Palette.Hover -Press $script:Palette.Hover -TextColor $script:Palette.Text -Border $script:Palette.Stroke -Size 8
$updateArrow.Visible = $false
$updateCard.Controls.Add($updateArrow)

$script:UI.UpdateStatus = New-Label -Text '' -X 20 -Y 256 -W 660 -H 44 -Size 9 -Color '#BFC4D6' -Back $script:Palette.Card -Align 'TopLeft'
$script:UI.UpdateStatus.Anchor = 'Top,Left,Right'
$updateCard.Controls.Add($script:UI.UpdateStatus)

$updateHint = New-Label -Text 'Update source: put "UpdateUrl" in settings.json - either an https URL or a local .json file shaped like  { "version": "0.5.1", "url": "https://...", "notes": "..." }.' -X 20 -Y 306 -W 660 -H 56 -Size 8 -Color $script:Palette.Muted -Back $script:Palette.Card -Align 'TopLeft'
$updateHint.Anchor = 'Top,Left,Right'
$updateCard.Controls.Add($updateHint)

# every page is laid out at its real size before the first one is picked
$contentHost.PerformLayout()

# -------------------------------------------------------------------- logs

function Update-LogView {
    $entries = $script:LogChannels[$script:SelectedLog]
    $logBox.Clear()
    $start = [Math]::Max(0, $entries.Count - 400)
    for ($i = $start; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]
        $logBox.SelectionStart = $logBox.TextLength
        $logBox.SelectionLength = 0
        $logBox.SelectionColor = ToColor '#5A5F73'
        $logBox.AppendText(("{0}  " -f $entry.Time))
        if ($script:SelectedLog -eq 'All') {
            $logBox.SelectionColor = ToColor '#6B7189'
            $logBox.AppendText(("{0,-6}" -f $entry.Channel))
        }
        $logBox.SelectionColor = ToColor (Get-LevelColor $entry.Level)
        $logBox.AppendText($entry.Message + "`r`n")
    }
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
}

function Add-Log {
    param([string]$Message, [string]$Level = 'info', [string]$Channel = 'App')

    $entry = [pscustomobject]@{
        Time    = (Get-Date).ToString('HH:mm:ss')
        Level   = $Level
        Message = $Message
        Channel = $Channel
    }

    [void]$script:LogChannels['All'].Add($entry)
    if ($Channel -ne 'All' -and $script:LogChannels.ContainsKey($Channel)) {
        [void]$script:LogChannels[$Channel].Add($entry)
    }
    if ($Channel -ne 'Errors' -and ($Level -eq 'warn' -or $Level -eq 'err')) {
        [void]$script:LogChannels['Errors'].Add($entry)
    }

    foreach ($key in @($script:LogChannels.Keys)) {
        $list = $script:LogChannels[$key]
        while ($list.Count -gt 400) { $list.RemoveAt(0) }
    }

    $showsThis = ($script:SelectedLog -eq 'All') -or
                 ($script:SelectedLog -eq $Channel) -or
                 ($script:SelectedLog -eq 'Errors' -and ($Level -eq 'warn' -or $Level -eq 'err'))
    if ($showsThis -and $script:UI.Pages['Logs'].Visible) { Update-LogView }
}

function Set-Status {
    param([string]$Text, [string]$Color = '#8A8FA6')
    $statusLabel.Text = $Text
    $statusDot.FillColor = ToColor $Color
    $statusDot.Invalidate()
}

function Set-UiRunning {
    param([bool]$Running)

    foreach ($stepper in $script:UI.Steppers) { $stepper.Enabled = (-not $Running) }

    if ($Running) {
        $startButton.Text = ("{0}  Stop" -f $script:G.Square)
        $startButton.FillColor = ToColor $script:Palette.LiveBg
        $startButton.HoverFill = ToColor '#2E2338'
        $startButton.PressFill = ToColor '#2A1F32'
        $startButton.BorderColor = ToColor $script:Palette.LiveLine
        $startButton.ForeColor = ToColor $script:Palette.Accent
    }
    else {
        $startButton.Text = ("{0}  Start prank" -f $script:G.Play)
        $startButton.FillColor = ToColor $script:Palette.Accent
        $startButton.HoverFill = ToColor $script:Palette.AccentHi
        $startButton.PressFill = ToColor $script:Palette.AccentLo
        $startButton.BorderColor = [System.Drawing.Color]::Transparent
        $startButton.ForeColor = [System.Drawing.Color]::White
    }
    $startButton.Invalidate()
}

function Update-PlanInfo {
    $plan = New-RickrollPlan -Windows $script:Opts.Windows -Desktops $script:Opts.Desktops -DelayMs 800
    if ($plan.NewDesktops -gt 0) {
        $script:UI.PlanValue.Text = ("{0} windows across {1} desktops ({2} new)" -f $plan.Windows, $plan.TotalDesktops, $plan.NewDesktops)
    }
    else {
        $script:UI.PlanValue.Text = ("{0} windows on the desktop you are on" -f $plan.Windows)
    }
    $script:UI.VideoValue.Text = $plan.Url
    $script:UI.ProfileValue.Text = $plan.ProfileDir
    if ($script:Opts.Hotkey -eq 'None') {
        $script:UI.HotkeyValue.Text = 'off'
        $hotkeyLabel.Text = 'hotkey: off'
    }
    else {
        $script:UI.HotkeyValue.Text = ("{0} {1} works on every desktop" -f $script:Opts.Hotkey, $script:G.Dot)
        $hotkeyLabel.Text = ("hotkey: {0}" -f $script:Opts.Hotkey)
    }
}

function Show-Page {
    param([string]$Key)
    if (-not $script:UI.Pages.ContainsKey($Key)) { return }

    foreach ($name in @($script:UI.Pages.Keys)) {
        $script:UI.Pages[$name].Visible = ($name -eq $Key)
    }
    $script:UI.CurrentPage = $Key

    foreach ($name in @($script:UI.NavButtons.Keys)) {
        $button = $script:UI.NavButtons[$name]
        if ($name -eq $Key) {
            $button.FillColor = ToColor $script:Palette.Inner
            $button.HoverFill = ToColor $script:Palette.Inner
            $button.PressFill = ToColor $script:Palette.Inner
            $button.ForeColor = ToColor $script:Palette.Text
        }
        else {
            $button.FillColor = ToColor $script:Palette.Sidebar
            $button.HoverFill = ToColor $script:Palette.Hover
            $button.PressFill = ToColor $script:Palette.Hover
            $button.ForeColor = ToColor $script:Palette.Muted
        }
        $button.Invalidate()
    }

    $active = $script:UI.NavButtons[$Key]
    if ($active -and $script:UI.NavBar) {
        $script:UI.NavBar.Top = $active.Top + (U 10)
        $script:UI.NavBar.Visible = $true
    }

    if ($Key -eq 'Logs') { Update-LogView }
}

# ------------------------------------------------------------------- timers

$script:StepTimer = New-Object System.Windows.Forms.Timer
$script:StepTimer.Interval = 120

$script:LogHandler = {
    param($message, $level)
    Add-Log -Message $message -Level $level -Channel 'Prank'
}

# ------------------------------------------------------------- prank control

function Start-Prank {
    if ($script:State.Running) { return }

    $plan = New-RickrollPlan -Windows $script:Opts.Windows -Desktops $script:Opts.Desktops -DelayMs 800
    $steps = @(Get-RickrollStep -Plan $plan)
    if ($steps.Count -eq 0) {
        Add-Log 'Nothing to do - raise the window count first.' 'warn'
        return
    }

    $queue = New-Object System.Collections.Queue
    foreach ($step in $steps) { $queue.Enqueue($step) }

    $script:State.Plan = $plan
    $script:State.Queue = $queue
    $script:State.DesktopsCreated = 0
    $script:State.StartedAt = Get-Date
    $script:State.Running = $true

    Set-UiRunning $true
    Set-Status 'Starting' $script:Palette.Accent
    Add-Log ("Starting: {0} window(s) across {1} desktop(s)" -f $plan.Windows, $plan.TotalDesktops) 'ok' 'App'
    if (-not $plan.BrowserPath) {
        Add-Log 'No Chromium browser found - using the default browser, which cannot be closed automatically.' 'warn' 'App'
    }

    $script:StepTimer.Interval = 120
    $script:StepTimer.Start()
}

function Stop-Prank {
    param([switch]$Force)

    $wasRunning = $script:State.Running
    $desktops = $script:State.DesktopsCreated
    $profileDir = if ($script:State.Plan) { $script:State.Plan.ProfileDir } else { Get-RickrollProfileDir }

    $script:State.Running = $false
    if ($script:State.Queue) { $script:State.Queue.Clear() }
    $script:State.Queue = $null
    $script:StepTimer.Stop()

    if (-not $wasRunning) {
        $strays = 0
        try { $strays = Stop-RickrollPrank -ProfileDir $profileDir -DesktopsToClose (Get-RickrollDesktopCount) } catch { }
        if ($strays -gt 0) { Add-Log ("Force stop: swept {0} stray window(s)" -f $strays) 'warn' 'App' }
        else { Add-Log 'Force stop: nothing was running.' 'quiet' 'App' }
        $script:State.DesktopsCreated = 0
        Set-UiRunning $false
        Set-Status 'Idle'
        return
    }

    if ($Force) { Add-Log 'Force stop - killing windows now.' 'warn' 'App' }

    $closed = 0
    try {
        $closed = Stop-RickrollPrank -ProfileDir $profileDir -DesktopsToClose $desktops -KeepDesktops:([bool]$script:Opts.KeepDesktops)
    }
    catch {
        Add-Log ("Cleanup problem: {0}" -f $_.Exception.Message) 'err' 'App'
    }

    $summary = "Closed {0} window(s)" -f $closed
    if ($desktops -gt 0) {
        if ($script:Opts.KeepDesktops) { $summary += (" and kept {0} desktop(s)" -f $desktops) }
        else { $summary += (" and {0} desktop(s)" -f $desktops) }
    }
    Add-Log $summary 'ok' 'App'

    $elapsed = 0
    if ($script:State.StartedAt) { $elapsed = [int][Math]::Round(((Get-Date) - $script:State.StartedAt).TotalSeconds) }
    $opened = 0
    if ($script:State.Plan) { $opened = [int]$script:State.Plan.Windows }
    Add-BoardRun -Windows $opened -Seconds $elapsed -Desktops $desktops -Forced:([bool]$Force)
    Add-Log ("Leaderboard: run #{0} - {1} window(s) in {2}" -f $script:Board.Runs.Count, $opened, (Format-BoardDuration $elapsed)) 'quiet' 'App'

    $script:State.DesktopsCreated = 0
    $script:State.Plan = $null
    $script:State.StartedAt = $null
    Set-UiRunning $false
    Set-Status 'Idle'
}

$script:StepTimer.add_Tick({
    try {
        if (-not $script:State.Running -or $null -eq $script:State.Queue) {
            $script:StepTimer.Stop()
            return
        }

        if ($script:State.Queue.Count -eq 0) {
            $script:StepTimer.Stop()
            Add-Log ("Prank live - {0} window(s) on {1} desktop(s)" -f $script:State.Plan.Windows, ($script:State.DesktopsCreated + 1)) 'ok' 'Prank'
            Set-Status ("Live {0} until you stop it" -f $script:G.Dot) $script:Palette.Accent
            return
        }

        $step = $script:State.Queue.Dequeue()
        $result = Invoke-RickrollStep -Step $step -Plan $script:State.Plan -OnLog $script:LogHandler
        if ($result.DesktopCreated) { $script:State.DesktopsCreated++ }

        if ($step.Kind -eq 'window') {
            Set-Status ("Starting {0} {1} of {2} windows" -f $script:G.Dot, $step.Number, $step.Total) $script:Palette.Accent
        }

        $script:StepTimer.Interval = [Math]::Max(60, [int]$step.DelayMs)
    }
    catch {
        Add-Log ("Step failed: {0}" -f $_.Exception.Message) 'err' 'Prank'
        $script:StepTimer.Stop()
        Stop-Prank
    }
})

# ------------------------------------------------------------------ hotkey

$script:UI.HotkeyWindow = New-Object Rickroll.UI.HotkeyWindow
$script:UI.HotkeyWindow.add_HotkeyPressed({
    Add-Log 'Panic hotkey pressed.' 'warn' 'App'
    Stop-Prank -Force
})

function Register-PanicHotkey {
    if (-not $script:UI.HotkeyWindow) { return }

    if ($script:UI.HotkeyRegistered) {
        try { $script:UI.HotkeyWindow.Unregister(1) } catch { }
        $script:UI.HotkeyRegistered = $false
    }

    $name = $script:Opts.Hotkey
    if ($name -eq 'None' -or -not $script:HotkeyMap.Contains($name)) {
        Add-Log 'Panic hotkey is off.' 'quiet' 'App'
        Update-PlanInfo
        return
    }

    $spec = $script:HotkeyMap[$name]
    $ok = $false
    try {
        $ok = $script:UI.HotkeyWindow.Register(1, [uint32]($spec.Mod -bor 0x4000), [uint32]$spec.Vk)
    }
    catch {
        $ok = $false
    }

    if ($ok) {
        $script:UI.HotkeyRegistered = $true
        Add-Log ("Panic hotkey armed: {0}" -f $name) 'ok' 'App'
    }
    else {
        Add-Log ("Could not register {0} - another app is using it." -f $name) 'warn' 'App'
    }
    Update-PlanInfo
}

function Set-Hotkey {
    param([string]$Name)
    if (-not $script:HotkeyMap.Contains($Name)) { return }
    $script:Opts.Hotkey = $Name
    Save-Settings
    Register-PanicHotkey
}

# ------------------------------------------------------------- "..." menu

$script:MenuRenderer = New-Object Rickroll.UI.DarkMenuRenderer
[System.Windows.Forms.ToolStripManager]::Renderer = $script:MenuRenderer

function New-MenuItem {
    param([string]$Text, [scriptblock]$OnClick, [string]$Tag = '')
    $item = New-Object System.Windows.Forms.ToolStripMenuItem
    $item.Text = $Text
    if ($Tag) { $item.Tag = $Tag }
    if ($OnClick) { $item.add_Click($OnClick) }
    return $item
}

function New-SettingsMenu {
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.BackColor = ToColor '#181A26'
    $menu.ForeColor = ToColor $script:Palette.Text
    $menu.ShowImageMargin = $false
    $menu.Padding = [System.Windows.Forms.Padding]::new((U 4))
    $menu.Renderer = $script:MenuRenderer
    $menu.Font = Get-UiFont -Size 9.5

    $hotkeyItem = New-MenuItem -Text 'Panic hotkey'
    $hotkeyItem.DropDown.BackColor = ToColor '#181A26'
    $hotkeyItem.DropDown.Renderer = $script:MenuRenderer

    foreach ($name in $script:HotkeyMap.Keys) {
        $mark = '    '
        if ($script:Opts.Hotkey -eq $name) { $mark = $script:G.Bullet + '  ' }
        $entry = New-MenuItem -Text ("$mark$name") -Tag $name -OnClick {
            param($sender, $e)
            Set-Hotkey -Name ([string]$sender.Tag)
        }
        [void]$hotkeyItem.DropDownItems.Add($entry)
    }
    [void]$menu.Items.Add($hotkeyItem)

    $keepMark = '    '
    if ($script:Opts.KeepDesktops) { $keepMark = $script:G.Check + '  ' }
    [void]$menu.Items.Add((New-MenuItem -Text ("{0}Keep desktops on stop" -f $keepMark) -OnClick {
        $script:Opts.KeepDesktops = (-not $script:Opts.KeepDesktops)
        Save-Settings
        Add-Log ("Keep desktops on stop: {0}" -f $script:Opts.KeepDesktops) 'quiet' 'App'
    }))

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    [void]$menu.Items.Add((New-MenuItem -Text 'Copy logs' -OnClick {
        try {
            [System.Windows.Forms.Clipboard]::SetText($logBox.Text)
            Add-Log 'Visible logs copied to clipboard.' 'quiet' 'App'
        }
        catch {
            Add-Log 'Could not reach the clipboard.' 'warn' 'App'
        }
    }))

    [void]$menu.Items.Add((New-MenuItem -Text 'About' -OnClick {
        [void][System.Windows.Forms.MessageBox]::Show(
            "Rickroll Launcher $($script:AppVersion)`r`n`r`nTabs: Prank, Logs, Leaderboard, Updates.`r`nThe panic hotkey works from any desktop.`r`n`r`nStop cleanup closes the prank browser windows and the desktops it created.",
            'About', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }))

    return $menu
}

function Show-SettingsMenu {
    $menu = New-SettingsMenu
    $menu.Show($menuButton, [System.Drawing.Point]::new(0, (U 24)))
}

# ----------------------------------------------------------------- updates

$script:UpdateCheck = @{
    Task        = $null
    Client      = $null
    State       = 'nosource'
    Available   = $false
    Version     = ''
    Url         = ''
    Notes       = ''
    LastChecked = $null
}

$script:UpdateCheckTimer = New-Object System.Windows.Forms.Timer
$script:UpdateCheckTimer.Interval = 300

function Set-UpdateState {
    param([string]$State)

    $script:UpdateCheck.State = $State

    switch ($State) {
        'checking' {
            $updateButton.Text = 'Checking...'
            $updateButton.Enabled = $false
            $updateArrow.Visible = $false
            $script:UI.UpdateStatus.Text = 'Contacting the update source...'
        }
        'available' {
            $updateButton.Enabled = $true
            $updateButton.Text = ('Update to {0}' -f $script:UpdateCheck.Version)
            $updateArrow.Visible = $true
            $script:UI.UpdateStatus.Text = ('Version {0} is available. Press the button to get it, or the arrow for release notes and other options.' -f $script:UpdateCheck.Version)
        }
        'current' {
            $updateButton.Enabled = $true
            $updateButton.Text = 'Check for updates'
            $updateArrow.Visible = $false
            $script:UI.UpdateStatus.Text = ('You are on the newest version ({0}).' -f $script:AppVersion)
        }
        'dismissed' {
            $updateButton.Enabled = $true
            $updateButton.Text = 'Check for updates'
            $updateArrow.Visible = $false
            $script:UI.UpdateStatus.Text = ('Update {0} dismissed. Press the button to check again.' -f $script:UpdateCheck.Version)
        }
        'error' {
            $updateButton.Enabled = $true
            $updateButton.Text = 'Check for updates'
            $updateArrow.Visible = $false
            $script:UI.UpdateStatus.Text = 'The last check failed. Press the button to try again.'
        }
        default {
            $updateButton.Enabled = $true
            $updateButton.Text = 'Check for updates'
            $updateArrow.Visible = $false
            $script:UI.UpdateStatus.Text = 'No update source yet: set "UpdateUrl" in settings.json to an https URL or a local .json manifest.'
        }
    }

    $script:UI.LatestValue.Text = $(if ($script:UpdateCheck.Version) { $script:UpdateCheck.Version } else { 'not checked' })
    $script:UI.LastCheckedValue.Text = $(if ($script:UpdateCheck.LastChecked) { $script:UpdateCheck.LastChecked.ToString('HH:mm:ss') } else { 'never' })
}

function Complete-UpdateCheck {
    param([string]$Json)

    $script:UpdateCheck.LastChecked = Get-Date

    try {
        $payload = $Json | ConvertFrom-Json
    }
    catch {
        Add-Log 'Update check: the source did not return valid JSON.' 'warn' 'App'
        Set-UpdateState 'error'
        return
    }

    if ($payload -is [System.Array]) {
        # GitHub releases API: pick the newest published release, prereleases included
        # so a beta channel still reports new builds.
        $release = $payload |
            Where-Object { $_.draft -ne $true -and $_.published_at } |
            Sort-Object -Property published_at -Descending |
            Select-Object -First 1

        if (-not $release) {
            Add-Log 'Update check: the repository has no published releases yet.' 'quiet' 'App'
            Set-UpdateState 'current'
            return
        }

        $kind = 'release'
        if ($release.prerelease) { $kind = 'prerelease' }
        Add-Log ("Newest on GitHub: {0} ({1})" -f $release.tag_name, $kind) 'quiet' 'App'

        $manifest = [pscustomobject]@{
            version = $release.tag_name
            url     = $release.html_url
            notes   = $release.body
        }
    }
    else {
        $manifest = $payload
    }

    $latestText = [string]$manifest.version
    $latestText = $latestText -replace '^[vV]', ''
    $latestText = ($latestText -split '-')[0]
    if (-not $latestText) {
        Add-Log 'Update manifest has no "version" field.' 'warn' 'App'
        Set-UpdateState 'error'
        return
    }

    try {
        $remote = [version]$latestText
        $current = [version]$script:AppVersion
    }
    catch {
        Add-Log ("Manifest version '{0}' is not a version number." -f $latestText) 'warn' 'App'
        Set-UpdateState 'error'
        return
    }

    if ($remote -gt $current) {
        $script:UpdateCheck.Available = $true
        $script:UpdateCheck.Version = $latestText
        $script:UpdateCheck.Url = [string]$manifest.url
        $script:UpdateCheck.Notes = [string]$manifest.notes
        Add-Log ("Update available: {0} (this build is {1})" -f $latestText, $script:AppVersion) 'ok' 'App'
        Set-UpdateState 'available'
    }
    else {
        $script:UpdateCheck.Available = $false
        # Keep the newest version around even when it is not newer: it is what the
        # self-test prints to prove the check really reached the source.
        $script:UpdateCheck.Version = $latestText
        $script:UpdateCheck.Url = ''
        $script:UpdateCheck.Notes = ''
        Add-Log ("Update check: up to date ({0})" -f $script:AppVersion) 'quiet' 'App'
        Set-UpdateState 'current'
    }
}

function Start-UpdateCheck {
    $source = [string]$script:Opts.UpdateUrl

    $script:UpdateCheck.Task = $null
    try { if ($script:UpdateCheck.Client) { $script:UpdateCheck.Client.Dispose() } } catch { }
    $script:UpdateCheck.Client = $null

    if (-not $source) {
        Add-Log 'Update check skipped: no "UpdateUrl" configured in settings.json.' 'quiet' 'App'
        Set-UpdateState 'nosource'
        return
    }

    Set-UpdateState 'checking'

    if ($source -match '^(?i)https?://') {
        try {
            # System.Net.Http is not loaded by default in PowerShell 5.1, so without this
            # the client could never be constructed and every http check failed.
            Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
            $client = New-Object System.Net.Http.HttpClient
            $client.Timeout = [TimeSpan]::FromSeconds(10)
            # GitHub's API rejects requests with no User-Agent.
            [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', "RickrollLauncher/$($script:AppVersion)")
            [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('Accept', 'application/vnd.github+json')
            $script:UpdateCheck.Client = $client
            $script:UpdateCheck.Task = $client.GetStringAsync($source)
            $script:UpdateCheckTimer.Start()
        }
        catch {
            Add-Log ("Update check failed: {0}" -f $_.Exception.Message) 'warn' 'App'
            Set-UpdateState 'error'
        }
        return
    }

    try {
        $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($source)
        if (-not (Test-Path -LiteralPath $path)) { throw ("Manifest not found: {0}" -f $path) }
        Add-Log ("Checking manifest {0}" -f $path) 'quiet' 'App'
        Complete-UpdateCheck -Json (Get-Content -Raw -LiteralPath $path)
    }
    catch {
        Add-Log ("Update check failed: {0}" -f $_.Exception.Message) 'warn' 'App'
        Set-UpdateState 'error'
    }
}

function Install-Update {
    $url = $script:UpdateCheck.Url
    if (-not $url) {
        Add-Log ("Version {0} is available, but the manifest has no download url." -f $script:UpdateCheck.Version) 'warn' 'App'
        return
    }
    try {
        Start-Process -FilePath $url
        Add-Log ("Opened the download page for {0}." -f $script:UpdateCheck.Version) 'ok' 'App'
        Set-Status ("Update {0} ready to install" -f $script:UpdateCheck.Version) $script:Palette.Accent
    }
    catch {
        Add-Log ("Could not open the download page: {0}" -f $_.Exception.Message) 'err' 'App'
    }
}

function Show-UpdateMenu {
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.BackColor = ToColor '#181A26'
    $menu.ForeColor = ToColor $script:Palette.Text
    $menu.ShowImageMargin = $false
    $menu.Padding = [System.Windows.Forms.Padding]::new((U 4))
    $menu.Renderer = $script:MenuRenderer
    $menu.Font = Get-UiFont -Size 9.5

    [void]$menu.Items.Add((New-MenuItem -Text 'Release notes' -OnClick {
        if ($script:UpdateCheck.Notes) {
            [void][System.Windows.Forms.MessageBox]::Show(
                $script:UpdateCheck.Notes,
                ("What's new in {0}" -f $script:UpdateCheck.Version),
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information)
        }
        else {
            Add-Log 'The update manifest has no release notes.' 'quiet' 'App'
        }
    }))

    [void]$menu.Items.Add((New-MenuItem -Text 'Open download page' -OnClick { Install-Update }))
    [void]$menu.Items.Add((New-MenuItem -Text 'Check again' -OnClick { Start-UpdateCheck }))
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$menu.Items.Add((New-MenuItem -Text 'Dismiss this update' -OnClick {
        Add-Log ("Update {0} dismissed." -f $script:UpdateCheck.Version) 'quiet' 'App'
        Set-UpdateState 'dismissed'
    }))

    $menu.Show($updateArrow, [System.Drawing.Point]::new(0, (U 48)))
}

$script:UpdateCheckTimer.add_Tick({
    $task = $script:UpdateCheck.Task
    if (-not $task) { $script:UpdateCheckTimer.Stop(); return }
    if (-not $task.IsCompleted) { return }

    $script:UpdateCheckTimer.Stop()
    $script:UpdateCheck.Task = $null
    $client = $script:UpdateCheck.Client
    $script:UpdateCheck.Client = $null

    try {
        $json = $task.GetAwaiter().GetResult()
        if ($client) { $client.Dispose() }
        Complete-UpdateCheck -Json $json
    }
    catch {
        if ($client) { try { $client.Dispose() } catch { } }
        Add-Log ("Update check failed: {0}" -f $_.Exception.GetBaseException().Message) 'warn' 'App'
        Set-UpdateState 'error'
    }
})

# --------------------------------------------------------------- wiring up

$startButton.add_Click({
    try {
        if ($script:State.Running) { Stop-Prank } else { Start-Prank }
    }
    catch { Add-Log ("Error: {0}" -f $_.Exception.Message) 'err' 'App' }
})

$forceButton.add_Click({
    try { Stop-Prank -Force }
    catch { Add-Log ("Error: {0}" -f $_.Exception.Message) 'err' 'App' }
})

$clearButton.add_Click({
    $channel = $script:SelectedLog
    $script:LogChannels[$channel].Clear()
    if ($channel -eq 'All') {
        foreach ($name in @('App', 'Prank', 'Errors')) { $script:LogChannels[$name].Clear() }
    }
    Update-LogView
})

$copyButton.add_Click({
    try {
        [System.Windows.Forms.Clipboard]::SetText($logBox.Text)
        Add-Log 'Visible logs copied to clipboard.' 'quiet' 'App'
    }
    catch {
        Add-Log 'Could not reach the clipboard.' 'warn' 'App'
    }
})

$logSelect.add_SelectedIndexChanged({
    $map = @('All', 'App', 'Prank', 'Errors')
    $script:SelectedLog = $map[$logSelect.SelectedIndex]
    Update-LogView
})

$updateButton.add_Click({
    try {
        if ($script:UpdateCheck.Available) { Install-Update }
        else { Start-UpdateCheck }
    }
    catch { Add-Log ("Update error: {0}" -f $_.Exception.Message) 'err' 'App' }
})

$updateArrow.add_Click({
    try { Show-UpdateMenu } catch { Add-Log ("Update menu error: {0}" -f $_.Exception.Message) 'err' 'App' }
})

$menuButton.add_Click({
    try { Show-SettingsMenu } catch { Add-Log ("Menu error: {0}" -f $_.Exception.Message) 'err' 'App' }
})

$minButton.add_Click({ $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized })
$maxButton.add_Click({
    if ($script:IsMaximized) { Set-Maximized } else { Set-Maximized -On }
})
$closeButton.add_Click({ $form.Close() })

$form.add_Resize({
    Update-FormRegion
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { return }
    Update-NavRail
    if ($logBox -and $script:UI.Pages['Logs'].Visible) { Update-LogView }
})

# ------------------------------------------------------------ start it up

Import-Settings
foreach ($key in @('Windows', 'Desktops')) {
    $script:UI.Values[$key].Text = [string]$script:Opts[$key]
}
Update-PlanInfo
Register-PanicHotkey
Show-Page -Key 'Prank'

$form.add_Shown({
    Update-NavRail
    Add-Log 'Launcher ready.' 'quiet' 'App'
    Add-Log ("Prank profile: {0}" -f (Get-RickrollProfileDir)) 'quiet' 'App'
    Set-Status 'Idle'
    try { Start-UpdateCheck } catch { Add-Log ("Update check error: {0}" -f $_.Exception.Message) 'warn' 'App' }
})

$form.add_FormClosing({
    Save-Settings
    try { $script:NavWatch.Stop() } catch { }
    try {
        if ($script:State.Running) { Stop-Prank -Force }
        else { [void](Stop-RickrollPrank -DesktopsToClose (Get-RickrollDesktopCount)) }
    }
    catch { }
    try { if ($script:UI.HotkeyWindow) { $script:UI.HotkeyWindow.Dispose() } } catch { }
})

if ($SelfTest) {
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()

    $testMenu = New-SettingsMenu
    Write-Host ("SelfTest: menu items: {0}" -f $testMenu.Items.Count)
    Write-Host ("SelfTest: pages: {0}, nav buttons: {1}" -f $script:UI.Pages.Count, $script:UI.NavButtons.Count)
    Write-Host ("SelfTest: hotkey registered: {0} ({1})" -f $script:UI.HotkeyRegistered, $script:Opts.Hotkey)

    Update-NavRail
    [System.Windows.Forms.Application]::DoEvents()
    $railNarrow = $sidebar.Width
    $iconText = $script:UI.NavButtons['Leaderboard'].Text
    Set-NavExpanded -On
    [System.Windows.Forms.Application]::DoEvents()
    $railWide = $sidebar.Width
    $wordText = $script:UI.NavButtons['Leaderboard'].Text
        $railOverPage = $sidebar.Right -gt $contentHost.Left
    Set-NavExpanded -On:$false
    [System.Windows.Forms.Application]::DoEvents()
    Write-Host ("SelfTest: nav rail collapsed={0} expanded={1} icons='{2}' words='{3}' overlapsPage={4}" -f $railNarrow, $railWide, $iconText, $wordText, $railOverPage)

    Show-Page -Key 'Logs'
    [System.Windows.Forms.Application]::DoEvents()
    Write-Host ("SelfTest: host {0}x{1}, logs page {2}x{3}, viewer {4}x{5}" -f $contentHost.Width, $contentHost.Height, $logsPage.Width, $logsPage.Height, $logBox.Width, $logBox.Height)
    Write-Host ("SelfTest: log lines visible after tab switch: {0}" -f $logBox.Lines.Count)

    $logSelect.SelectedIndex = 1
    [System.Windows.Forms.Application]::DoEvents()
    Write-Host ("SelfTest: 'App' channel lines: {0}" -f $logBox.Lines.Count)
    $logSelect.SelectedIndex = 2
    [System.Windows.Forms.Application]::DoEvents()
    Write-Host ("SelfTest: 'Prank' channel lines: {0}" -f $logBox.Lines.Count)
    $logSelect.SelectedIndex = 0
    [System.Windows.Forms.Application]::DoEvents()
    Set-Maximized -On
    [System.Windows.Forms.Application]::DoEvents()
    Write-Host ("SelfTest: maximised {0}x{1}, viewer {2}x{3}" -f $form.Width, $form.Height, $logBox.Width, $logBox.Height)
    Set-Maximized
    Show-Page -Key 'Updates'

    $tempManifest = Join-Path $env:TEMP 'rickroll-update-selftest.json'
    @{ version = '9.9.9'; url = 'https://example.com/rickroll'; notes = 'Self-test manifest' } |
        ConvertTo-Json | Set-Content -LiteralPath $tempManifest -Encoding UTF8
    $script:Opts.UpdateUrl = $tempManifest
    Start-UpdateCheck
    [System.Windows.Forms.Application]::DoEvents()
    Write-Host ("SelfTest: newer manifest -> state={0} latest={1} arrowVisible={2} button='{3}'" -f $script:UpdateCheck.State, $script:UpdateCheck.Version, $updateArrow.Visible, $updateButton.Text)

    @{ version = '0.0.1'; url = ''; notes = '' } | ConvertTo-Json | Set-Content -LiteralPath $tempManifest -Encoding UTF8
    Start-UpdateCheck
    [System.Windows.Forms.Application]::DoEvents()
    Write-Host ("SelfTest: older manifest -> state={0} arrowVisible={1} button='{2}'" -f $script:UpdateCheck.State, $updateArrow.Visible, $updateButton.Text)

    # Visible is only meaningful once the page itself is shown.
    Show-Page -Key 'Leaderboard'
    $hadBoardFile = Test-Path -LiteralPath $script:BoardPath
    $savedBoardRuns = @($script:Board.Runs)

    $script:Board.Runs = @()
    Update-Board
    Write-Host ("SelfTest: empty board -> runs={0} emptyVisible={1} row0Hidden={2}" -f $script:UI.BoardStatValues['Runs'].Text, $script:UI.BoardEmpty.Visible, (-not $script:UI.BoardRows[0]['Back'].Visible))

    Add-BoardRun -Windows 12 -Seconds 95 -Desktops 3 -Forced $false
    Add-BoardRun -Windows 8 -Seconds 300 -Desktops 2 -Forced $true
    Write-Host ("SelfTest: board -> runs={0} best={1} longest={2} totalWindows={3}" -f $script:UI.BoardStatValues['Runs'].Text, $script:UI.BoardStatValues['Best'].Text, $script:UI.BoardStatValues['Longest'].Text, $script:UI.BoardStatValues['Windows'].Text)
    Write-Host ("SelfTest: board row0='{0}' shown={1} unusedRowHidden={2} emptyHidden={3}" -f $script:UI.BoardRows[0]['When'].Text, $script:UI.BoardRows[0]['Back'].Visible, (-not $script:UI.BoardRows[2]['Back'].Visible), (-not $script:UI.BoardEmpty.Visible))

    $script:Board.Runs = @()
    Import-Board
    Write-Host ("SelfTest: board saved to disk -> runs={0} newestWindows={1} newestForced={2}" -f @($script:Board.Runs).Count, @($script:Board.Runs)[0].Windows, @($script:Board.Runs)[0].Forced)

    Clear-Board
    Write-Host ("SelfTest: board reset -> runs={0} emptyVisible={1} fileRuns={2}" -f $script:UI.BoardStatValues['Runs'].Text, $script:UI.BoardEmpty.Visible, @((Get-Content -Raw -LiteralPath $script:BoardPath | ConvertFrom-Json).Runs).Count)

    $script:Board.Runs = $savedBoardRuns
    if ($hadBoardFile) { Save-Board } else { Remove-Item -LiteralPath $script:BoardPath -Force -ErrorAction SilentlyContinue }
    Update-Board

    $script:Opts.UpdateUrl = 'https://api.github.com/repos/dnbdj/rickroll-launcher/releases'
    Start-UpdateCheck
    $waited = 0
    while ($script:UpdateCheck.State -eq 'checking' -and $waited -lt 15000) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
        $waited += 100
    }
    Write-Host ("SelfTest: live github check -> state={0} latest='{1}' checkedAt={2} waited={3}ms" -f $script:UpdateCheck.State, $script:UpdateCheck.Version, $script:UI.LastCheckedValue.Text, $waited)

    Remove-Item -LiteralPath $tempManifest -Force -ErrorAction SilentlyContinue
    $script:Opts.UpdateUrl = ''
    $script:UpdateCheck.Version = ''
    $script:UpdateCheck.Available = $false
    Set-UpdateState 'nosource'

    $testMenu.Dispose()

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.ElapsedMilliseconds -lt $SelfTestMs) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 25
    }
    $form.Close()
    [System.Windows.Forms.Application]::DoEvents()
    Write-Host 'SelfTest: launcher built, shown, resized and painted with no errors.'
    return
}

[void]$form.ShowDialog()

