# Runs a Godot tool that needs a real window (contact sheets, thumbnails, previews) with that window hidden
# and never focused: Ted plays other games while Claude works, and pop-ups stole his focus (Nov 27).
#
#   tools\render_hidden.ps1 -s res://tools/contact_sheet.gd '--' --set=props:restaurant --out=kitchen
#   tools\render_hidden.ps1 --resolution 640x480 -s res://tools/make_thumbs.gd '--' --missing
#
# Quote the bare '--' : PowerShell swallows an unquoted one, and Godot then never sees the tool's own options.
# The tools draw into a SubViewport, so the window itself can be 64 x 64 and hidden (override.cfg, written here
# for the run and removed after; it's git-ignored). Prints the tool's own lines and any script errors.
# Never use this to run the game itself: in a round it captures the mouse, hidden or not.
$proj = Split-Path -Parent $PSScriptRoot
$godot = 'C:\devtools\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64.exe'
$cfg = Join-Path $proj 'override.cfg'
$made = $false
if (-not (Test-Path $cfg)) {
    "[display]`nwindow/size/viewport_width=64`nwindow/size/viewport_height=64`nwindow/size/no_focus=true`nwindow/size/borderless=true`n" | Out-File -Encoding ascii $cfg
    $made = $true
}
$log = Join-Path $env:TEMP ("hh_render_{0}.log" -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
$all = @('--path', $proj) + $args
$p = Start-Process -FilePath $godot -ArgumentList $all -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log + '.err')
if (-not $p.WaitForExit(300000)) { try { $p.Kill() } catch {} ; 'TIMED OUT after 5 minutes' }
Get-Content $log -ErrorAction SilentlyContinue | Where-Object { $_ -and $_ -notmatch '^Godot Engine|^Vulkan|^OpenGL|^$' } | Select-Object -First 40
Get-Content ($log + '.err') -ErrorAction SilentlyContinue | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|   at: .*\.gd' } | Select-Object -First 12
Remove-Item $log, ($log + '.err') -ErrorAction SilentlyContinue
if ($made) { Remove-Item $cfg -ErrorAction SilentlyContinue }
