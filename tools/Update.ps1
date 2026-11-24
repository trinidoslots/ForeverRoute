# Brings this PC's ForeverRoute up to date from GitHub (run on every PC except the main one).
# -Quiet: print nothing unless something was updated or went wrong (for the scheduled task).
param([switch]$Quiet)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Say($msg, $color = "Gray") { if (-not $Quiet) { Write-Host $msg -ForegroundColor $color } }

function TocVersion($toc) {
	if ($toc -match '(?m)^## Version:\s*(\S+)') { return $Matches[1] }
	return "?"
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is not installed (https://git-scm.com/download/win)" }
if (-not (Test-Path (Join-Path $root ".git"))) { throw "$root is not a git clone. See the setup steps." }

# Never touch a running game's files.
if (Get-Process -Name "Wow*" -ErrorAction SilentlyContinue) {
	Say "WoW is running. Close the game first, then update." "Yellow"
	exit 2
}

git fetch --quiet origin
if ($LASTEXITCODE -ne 0) { throw "git fetch failed (no internet or no access to the repo?)" }

$branch = (git rev-parse --abbrev-ref HEAD).Trim()
$local = TocVersion (Get-Content (Join-Path $root "ForeverRoute.toc") -Raw)
$remote = TocVersion ((git show "origin/${branch}:ForeverRoute.toc") -join "`n")

# Local changes: stop, never overwrite.
if (git status --porcelain) {
	Say "There are local changes in $root, not updating:" "Yellow"
	if (-not $Quiet) { git status --short }
	exit 3
}

$behind = [int](git rev-list --count "HEAD..origin/$branch")
if ($behind -eq 0) {
	Say "ForeverRoute $local is up to date." "Green"
	exit 0
}

git pull --ff-only --quiet origin $branch
if ($LASTEXITCODE -ne 0) { throw "git pull failed" }
$now = TocVersion (Get-Content (Join-Path $root "ForeverRoute.toc") -Raw)
Write-Host "ForeverRoute $local -> $now. Start (or restart) WoW." -ForegroundColor Green
