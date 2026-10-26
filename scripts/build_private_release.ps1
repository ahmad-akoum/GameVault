param(
    [Parameter(Mandatory=$true)][string]$Version,
    [string]$BuildDirectory = 'build',
    [string]$SymbolDirectory = '',
    [switch]$Candidate
)
$ErrorActionPreference = 'Stop'
[string[]]$defineArgs = if ($Candidate) { @('--dart-define=GAMEVAULT_CANDIDATE=true') } else { @() }
[string[]]$assembleDefines = if ($Candidate) { @('-dDartDefines=' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('GAMEVAULT_CANDIDATE=true'))) } else { @() }
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Expected semantic version' }
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    $packageVersion = (Select-String -LiteralPath pubspec.yaml -Pattern '^version: (.+)$').Matches.Groups[1].Value
    if ($packageVersion.Split('+')[0] -ne $Version) { throw 'Source version differs from requested release' }
    $buildRoot = if ([IO.Path]::IsPathRooted($BuildDirectory)) { [IO.Path]::GetFullPath($BuildDirectory) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot $BuildDirectory)) }
    $symbolRoot = if ($SymbolDirectory) {
        if ([IO.Path]::IsPathRooted($SymbolDirectory)) { [IO.Path]::GetFullPath($SymbolDirectory) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot $SymbolDirectory)) }
    } else { [IO.Path]::GetFullPath((Join-Path $projectRoot "release_artifacts/private-symbols/v$Version-portable")) }
    $buildRelative = [IO.Path]::GetRelativePath($projectRoot, $buildRoot)
    if ([IO.Path]::IsPathRooted($buildRelative)) { throw 'Flutter isolated build directory must be on the project drive.' }
    $flutterSettingsPath = Join-Path $env:APPDATA '.flutter_settings'
    $settingsExisted = Test-Path -LiteralPath $flutterSettingsPath
    $settingsBytes = if ($settingsExisted) { [IO.File]::ReadAllBytes($flutterSettingsPath) } else { $null }
    New-Item -ItemType Directory -Path $symbolRoot -Force | Out-Null
    if (Test-Path -LiteralPath (Join-Path $buildRoot 'windows/x64/runner/Release/vault_data')) {
        throw 'Refusing to build over a portable vault directory; select a clean isolated BuildDirectory.'
    }
    try {
        # Flutter accepts only a project-relative build-dir setting. Temporarily
        # point it outside the checkout so existing portable vault data is safe.
        & flutter config --build-dir $buildRelative | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not configure the isolated Flutter build directory' }
        & flutter build windows --release --no-pub -t lib/main.dart "--split-debug-info=$symbolRoot" @defineArgs
        if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
    } finally {
        if ($settingsExisted) {
            [IO.File]::WriteAllBytes($flutterSettingsPath, $settingsBytes)
        } elseif (Test-Path -LiteralPath $flutterSettingsPath) {
            Remove-Item -LiteralPath $flutterSettingsPath
        }
    }
    # Give the generated registrant a neutral package URI during compilation.
    # This changes only generated build metadata, adds no dependency, and is
    # restored byte-for-byte even on failure. Do not run concurrent builds.
    $configPath = Join-Path $projectRoot '.dart_tool/package_config.json'
    $originalConfig = [IO.File]::ReadAllBytes($configPath)
    try {
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        if ($config.packages.name -contains 'gamevault_build') { throw 'Generated package alias already exists' }
        $config.packages += [pscustomobject]@{name='gamevault_build'; rootUri='../.dart_tool/flutter_build/'; packageUri='./'; languageVersion='3.10'}
        [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
        & flutter assemble --no-version-check "--output=$buildRoot" '-dTargetPlatform=windows-x64' '-dBuildMode=release' '-dTargetFile=lib/main.dart' '-dDartObfuscation=false' "-dSplitDebugInfo=$symbolRoot" @assembleDefines release_bundle_windows-x64_assets
        if ($LASTEXITCODE -ne 0) { throw 'Portable release bundle failed' }
        Copy-Item -LiteralPath (Join-Path $buildRoot 'windows/app.so') -Destination (Join-Path $buildRoot 'windows/x64/runner/Release/data/app.so')
    } finally { [IO.File]::WriteAllBytes($configPath, $originalConfig) }
    Write-Output 'Release built. Run the packaging privacy guard before distribution. Keep symbols private.'
} finally { Pop-Location }
