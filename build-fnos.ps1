param(
    [string]$BinaryPath = "bin/cosmomail-linux-amd64",
    [string]$FnpackPath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$packageDir = Join-Path $projectRoot "fnapp"
$binary = Resolve-Path (Join-Path $projectRoot $BinaryPath)
$serverDir = Join-Path $packageDir "app/server"
$uiImagesDir = Join-Path $packageDir "app/ui/images"

New-Item -ItemType Directory -Force -Path $serverDir, $uiImagesDir | Out-Null
Copy-Item -LiteralPath $binary -Destination (Join-Path $serverDir "cosmomail") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "public/images/icon_64.png") -Destination (Join-Path $uiImagesDir "icon-64.png") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "public/images/icon_256.png") -Destination (Join-Path $uiImagesDir "icon-256.png") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "public/images/icon_64.png") -Destination (Join-Path $packageDir "ICON.PNG") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "public/images/icon_256.png") -Destination (Join-Path $packageDir "ICON_256.PNG") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "LICENSE") -Destination (Join-Path $packageDir "LICENSE") -Force

if (-not $FnpackPath) {
    $FnpackPath = Join-Path $env:TEMP "fnpack-1.2.1-windows-amd64.exe"
    if (-not (Test-Path -LiteralPath $FnpackPath)) {
        Invoke-WebRequest -Uri "https://static2.fnnas.com/fnpack/fnpack-1.2.1-windows-amd64" -OutFile $FnpackPath
    }
}

Push-Location $packageDir
try {
    & $FnpackPath build
    if ($LASTEXITCODE -ne 0) {
        throw "fnpack build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$rawPackage = Join-Path $packageDir "com.qwernot.cosmomail.fpk"
if (-not (Test-Path -LiteralPath $rawPackage)) {
    throw "fnpack did not produce an fpk file"
}
$version = ((Get-Content -Raw (Join-Path $projectRoot "version.json")) | ConvertFrom-Json).latest
$outputPackage = Join-Path $packageDir "CosmoMail-fnOS-x86_64-$version.fpk"
Move-Item -LiteralPath $rawPackage -Destination $outputPackage -Force
Write-Output $outputPackage
