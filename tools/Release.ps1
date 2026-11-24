# Publishes the current state of the addon to GitHub (run on the main PC).
#   .\tools\Release.ps1 -Message "new guides"              # 2.11.0 -> 2.11.1
#   .\tools\Release.ps1 -Bump minor -Message "new feature" # 2.11.1 -> 2.12.0
#   .\tools\Release.ps1 -Version 3.0.0
param(
	[ValidateSet("patch", "minor", "major")][string]$Bump = "patch",
	[string]$Version,
	[string]$Message = "update"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$toc = Join-Path $root "ForeverRoute.toc"
$text = [System.IO.File]::ReadAllText($toc)
if ($text -notmatch '(?m)^## Version:\s*(\d+)\.(\d+)\.(\d+)\s*$') { throw "No '## Version: x.y.z' line in ForeverRoute.toc" }
$old = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
$major = [int]$Matches[1]; $minor = [int]$Matches[2]; $patch = [int]$Matches[3]

if ($Version) {
	if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "-Version must look like 2.11.0" }
	$new = $Version
} else {
	switch ($Bump) {
		"major" { $major++; $minor = 0; $patch = 0 }
		"minor" { $minor++; $patch = 0 }
		"patch" { $patch++ }
	}
	$new = "$major.$minor.$patch"
}

if (git tag --list "v$new") { throw "Tag v$new exists already. Pick another version." }

# Rewrite the version line, keeping the file's line endings and encoding (no BOM).
$text = $text -replace '(?m)^## Version:.*?(\r?)$', "## Version: $new`$1"
[System.IO.File]::WriteAllText($toc, $text, (New-Object System.Text.UTF8Encoding($false)))

git add -A
git commit -m "v${new}: $Message"
if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
git tag "v$new"
git push --follow-tags
if ($LASTEXITCODE -ne 0) { throw "git push failed (is the 'origin' remote set?)" }

Write-Host "Released $old -> $new" -ForegroundColor Green
