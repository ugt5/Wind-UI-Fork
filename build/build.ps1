param (
    [string]$Mode = "build",
    [string]$InputFile = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir

Set-Location $rootDir

# Ensure dist folder exists
if (-not (Test-Path "dist")) {
    New-Item -ItemType Directory -Path "dist" | Out-Null
}

# 1. Generate build/package.lua
$packageJsonContent = Get-Content -Raw -Path "package.json"
$packageLuaContent = "-- Generated from package.json | build/build.ps1`n`nreturn [[`n$packageJsonContent`n]]"
Set-Content -Path "build\package.lua" -Value $packageLuaContent -NoNewline

# 2. Determine input file and config
if ($Mode -eq "dev") {
    if (-not $InputFile) { $InputFile = "main.lua" }
    $prefix = "[ DEV ]"
} else {
    $InputFile = "src/Init.lua"
    $prefix = "[ BUILD ]"
}

$outputFile = "dist\main.lua"
$tempFile = "dist\temp.lua"
$configFile = "build\darklua.dev.config.json"

# 3. Read metadata from package.json
$pkg = Get-Content -Raw -Path "package.json" | ConvertFrom-Json
$version = $pkg.version
$date = Get-Date -Format "yyyy-MM-dd"

# 4. Generate header
$header = (Get-Content -Raw -Path "build\header.lua").
    Replace("{{VERSION}}", [string]$version).
    Replace("{{BUILD_DATE}}", [string]$date).
    Replace("{{DESCRIPTION}}", [string]$pkg.description).
    Replace("{{REPOSITORY}}", [string]$pkg.repository).
    Replace("{{DISCORD}}", [string]$pkg.discord).
    Replace("{{LICENSE}}", [string]$pkg.license)

# 5. Check darklua executable
$darklua = Get-Command darklua -ErrorAction SilentlyContinue
if (-not $darklua) {
    Write-Host "[!] Darklua executable not found in PATH." -ForegroundColor Yellow
    Write-Host "[!] Please install darklua via Aftman ('aftman install') or download it from https://github.com/seaofvoices/darklua/releases" -ForegroundColor Yellow
    exit 1
}

# 6. Run Darklua
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
Write-Host "$prefix Processing '$InputFile' with Darklua..." -ForegroundColor Cyan

& darklua process "$InputFile" "$tempFile" --config "$configFile"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[-] Darklua processing failed." -ForegroundColor Red
    if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
    exit 1
}

$stopwatch.Stop()
$elapsedMs = $stopwatch.ElapsedMilliseconds

# 7. Assemble final bundle
$tempContent = Get-Content -Raw -Path $tempFile
$finalOutput = $header + "`n`n" + $tempContent
Set-Content -Path $outputFile -Value $finalOutput -NoNewline

if (Test-Path $tempFile) {
    Remove-Item $tempFile -Force
}

$sizeKb = [math]::Round((Get-Item $outputFile).Length / 1024, 2)

Write-Host ""
Write-Host "[ $(Get-Date -Format 'HH:mm:ss') ]"
Write-Host "[+] $prefix" -ForegroundColor Green
Write-Host "[+] WindUI Build completed successfully" -ForegroundColor Green
Write-Host "[+] Version: $version" -ForegroundColor Green
Write-Host "[+] Time taken: ${elapsedMs}ms" -ForegroundColor Green
Write-Host "[+] Size: ${sizeKb}KB" -ForegroundColor Green
Write-Host "[+] Output file: $outputFile" -ForegroundColor Green
Write-Host ""
