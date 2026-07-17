[CmdletBinding()]
param(
    [string]$Branch = "",
    [string]$Repository = "shinnpuru/VoiceTransl"
)

$ErrorActionPreference = "Stop"
$artifactName = "VoiceTransl-Windows-x64"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$runtimeRoot = Join-Path $repoRoot "runtime"
$target = Join-Path $runtimeRoot "flutter-windows"
$pending = Join-Path $runtimeRoot "flutter-windows.next"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) is required. Install it and run 'gh auth login'."
}

if ([string]::IsNullOrWhiteSpace($Branch)) {
    $Branch = (& git -C $repoRoot branch --show-current).Trim()
}
if ([string]::IsNullOrWhiteSpace($Branch)) {
    throw "Cannot determine the current Git branch. Pass -Branch explicitly."
}

$runJson = & gh run list `
    --repo $Repository `
    --workflow flutter-windows.yaml `
    --branch $Branch `
    --status success `
    --limit 1 `
    --json databaseId,headSha,createdAt
if ($LASTEXITCODE -ne 0) {
    throw "Failed to query GitHub Actions. Check 'gh auth status' and network access."
}

$runs = @($runJson | ConvertFrom-Json)
if ($runs.Count -eq 0) {
    throw "No successful Flutter Windows workflow run was found for branch '$Branch'."
}
$run = $runs[0]

New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
if (Test-Path -LiteralPath $pending) {
    Remove-Item -LiteralPath $pending -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $pending | Out-Null

Write-Host "Downloading $artifactName from run $($run.databaseId)..."
& gh run download $run.databaseId `
    --repo $Repository `
    --name $artifactName `
    --dir $pending
if ($LASTEXITCODE -ne 0) {
    throw "Artifact download failed."
}

$executable = Join-Path $pending "voicetransl_flutter.exe"
if (-not (Test-Path -LiteralPath $executable)) {
    throw "The downloaded artifact does not contain voicetransl_flutter.exe."
}

if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
}
Move-Item -LiteralPath $pending -Destination $target

Write-Host "Flutter GUI updated from commit $($run.headSha)."
Write-Host "Run start_gui.cmd from the repository root."
