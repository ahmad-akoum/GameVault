param([Parameter(Mandatory=$true)][string]$Executable, [Parameter(Mandatory=$true)][string]$DataDirectory)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $DataDirectory) { throw 'Use a new isolated test data directory' }
$oldData = $env:GAMEVAULT_DATA_DIR
try {
    $env:GAMEVAULT_DATA_DIR = [IO.Path]::GetFullPath($DataDirectory)
    $app = Start-Process -FilePath ([IO.Path]::GetFullPath($Executable)) -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 4
    $app.Refresh()
    if ($app.HasExited -or $app.MainWindowHandle -eq 0) { throw 'Release did not create a window' }
    if (-not $app.CloseMainWindow() -or -not $app.WaitForExit(15000)) { throw 'Release did not close' }
    if ($app.ExitCode -ne 0) { throw "Release close failed with exit code $($app.ExitCode)" }
    Write-Output 'Release startup and graceful close passed (exit 0), using isolated data.'
} finally { $env:GAMEVAULT_DATA_DIR = $oldData }
