param([Parameter(Mandatory=$true)][string]$Version)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Expected semantic version' }
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    $packageVersion = (Select-String -LiteralPath pubspec.yaml -Pattern '^version: (.+)$').Matches.Groups[1].Value
    if ($packageVersion.Split('+')[0] -ne $Version) { throw 'Source version differs from requested release' }
    $symbolDirectory = "release_artifacts/private-symbols/v$Version-portable"
    & flutter build windows --release --no-pub -t lib/main.dart "--split-debug-info=$symbolDirectory"
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
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
        & flutter assemble --no-version-check --output=build '-dTargetPlatform=windows-x64' '-dBuildMode=release' '-dTargetFile=lib/main.dart' '-dDartObfuscation=false' "-dSplitDebugInfo=$symbolDirectory" release_bundle_windows-x64_assets
        if ($LASTEXITCODE -ne 0) { throw 'Portable release bundle failed' }
        Copy-Item -LiteralPath build/windows/app.so -Destination build/windows/x64/runner/Release/data/app.so
    } finally { [IO.File]::WriteAllBytes($configPath, $originalConfig) }
    Write-Output 'Release built. Run the packaging privacy guard before distribution. Keep symbols private.'
} finally { Pop-Location }
