# Prepare plugin junctions inside this project only. Windows directory junctions
# avoid requiring Developer Mode for directory symbolic links.
$projectRoot = Split-Path -Parent $PSScriptRoot
$pluginData = Get-Content -LiteralPath (Join-Path $projectRoot '.flutter-plugins-dependencies') -Raw | ConvertFrom-Json
$linkRoot = Join-Path $projectRoot 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Path $linkRoot -Force | Out-Null
foreach ($plugin in $pluginData.plugins.windows) {
  $linkPath = Join-Path $linkRoot $plugin.name
  if (-not (Test-Path -LiteralPath $linkPath)) {
    New-Item -ItemType Junction -Path $linkPath -Target $plugin.path | Out-Null
  }
}
