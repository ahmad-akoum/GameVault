param([string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) {
    $base = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { Join-Path $env:LOCALAPPDATA 'GameVaultNativeTests' }
    $OutputDirectory = Join-Path $base ("ci-" + [Guid]::NewGuid().ToString('N'))
}
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
if ($outputRoot -match '["%\r\n]' -or $outputRoot -match '(?i)[\\/]vault_data([\\/]|$)' -or $outputRoot.StartsWith((Join-Path $projectRoot 'build'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Choose a new isolated output directory outside personal build/vault locations.'
}
if ((Test-Path -LiteralPath $outputRoot) -and @(Get-ChildItem -LiteralPath $outputRoot -Force).Count) { throw 'Refusing to overwrite existing native test output.' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio C++ tooling is required.' }
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'No Visual Studio installation with x64 C++ tools was found.' }
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$lines = @('@echo off', ('call "' + (Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat') + '" >nul'), 'if errorlevel 1 exit /b 1')
foreach ($test in @('dualsense_activity_test', 'input_activity_test')) {
    $source = Join-Path $projectRoot "test\$test.cpp"
    $exe = Join-Path $outputRoot "$test.exe"
    $obj = Join-Path $outputRoot "$test.obj"
    # Assertions deliberately remain enabled; never define NDEBUG here.
    $lines += 'cl.exe /nologo /EHsc /std:c++17 "' + $source + '" /Fe:"' + $exe + '" /Fo:"' + $obj + '"'
    $lines += @('if errorlevel 1 exit /b 1', ('"' + $exe + '"'), 'if errorlevel 1 exit /b 1')
}
$lines += 'exit /b 0'
$batch = Join-Path $outputRoot 'run.cmd'
[IO.File]::WriteAllLines($batch, $lines, [Text.Encoding]::ASCII)
& cmd.exe /d /c $batch
if ($LASTEXITCODE -ne 0) { throw 'Native inactivity verification failed.' }
Write-Output 'Both native inactivity suites passed with assertions enabled.'
