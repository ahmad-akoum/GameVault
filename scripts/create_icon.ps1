# A small geometric vault mark, drawn as a native Windows icon.
Add-Type -AssemblyName System.Drawing
$bitmap = New-Object System.Drawing.Bitmap 64,64
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::FromArgb(255,23,25,29))
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255,184,217,110)),4
$graphics.DrawRectangle($pen,13,15,38,36)
$graphics.DrawLine($pen,13,25,51,25)
$graphics.DrawLine($pen,25,31,32,42)
$graphics.DrawLine($pen,32,42,40,31)
$icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
$stream = [System.IO.File]::Create((Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\runner\resources\app_icon.ico'))
$icon.Save($stream)
$stream.Close()
$icon.Dispose()
$pen.Dispose()
$graphics.Dispose()
$bitmap.Dispose()
