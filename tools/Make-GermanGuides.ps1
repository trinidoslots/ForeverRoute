<#
.SYNOPSIS
  Builds Guides\deDE\forever\RestedXP-Skyborne.lua (German guides for the levels RestedXP has no German for).

.DESCRIPTION
  RestedXP only translates the guides up to about level 23 (and the first two Zephras Isle guides of the
  Skyborne file). The English Skyborne file has 223 guides up to level 60. This script puts the machine
  translation of the rest behind RestedXP's own German guides:

    1. Run the translator (https://github.com/eygelias/RestedXP-Traslation, MIT) on
       Guides\enUS\forever\RestedXP-Skyborne.lua as its only input file:  python translate_guides.py deDE
       Apply tools\translate_guides-deDE.patch to the translator first (git apply, or patch -p1): without it
       the German output would contain Spanish zone names and fallback phrases. The patch also leaves guide
       names and macro targets in English and translates with 8 threads. Install: pip install deep-translator.
    2. Run this script with the folder that holds the translated file:
         .\tools\Make-GermanGuides.ps1 -Translated "C:\...\RestedXP-Traslation\output"

  The result keeps the same guides in the same order as the English file, so ForeverRoute pairs every
  German guide with its English twin (FR.PairGuides): steps the translation lacks show in English.
  Guide names (#name, #next, #include) stay as RestedXP wrote them; they identify the guides.

  After tools\Update-Guides.ps1 has overwritten the German file with RestedXP's two guides, run this
  script again (it reads the two official guides from whatever is in the German file now).

.PARAMETER Translated
  Folder with the translator's output; it must contain RestedXP-Skyborne.lua (or forever\RestedXP-Skyborne.lua).

.PARAMETER WhatIf
  Only report.
#>
param(
	[Parameter(Mandatory)] [string] $Translated,
	[switch] $WhatIf
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)

$en = Join-Path $root "Guides\enUS\forever\RestedXP-Skyborne.lua"
$de = Join-Path $root "Guides\deDE\forever\RestedXP-Skyborne.lua"
$tr = @((Join-Path $Translated "RestedXP-Skyborne.lua"), (Join-Path $Translated "forever\RestedXP-Skyborne.lua")) |
	Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $tr) { throw "No RestedXP-Skyborne.lua in $Translated" }

# The text in front of each ForeverRoute.RegisterGuide([[ ... ]]) call: element 0 is the file header.
function Split-Guides([string] $text) {
	return , [regex]::Split($text, '(?m)(?=^ForeverRoute\.RegisterGuide\(\[\[)')
}
function Read-Utf8([string] $path) { return $utf8.GetString([IO.File]::ReadAllBytes($path)) }

$enParts = Split-Guides (Read-Utf8 $en)
$deParts = Split-Guides (Read-Utf8 $de)
$trParts = Split-Guides (Read-Utf8 $tr)
$official = 2   # RestedXP's own German guides at the start of the file (1-9 and 9-13 Zephras Isle)

if ($enParts.Count -ne $trParts.Count) {
	throw "The translation has $($trParts.Count - 1) guides, the English file $($enParts.Count - 1). Translate the current English file."
}
if ($deParts.Count -le $official) { throw "The German file has fewer than $official guides." }

# Steps and command lines must be the same as in the English twin: only the text may differ.
function Command-Lines([string] $guide) {
	$lines = foreach ($l in ($guide -split "\r?\n")) {
		$t = $l.Trim()
		if ($t -match '^(step\b|\.[A-Za-z]|#(?!name|next|include|displayname))') {
			(($t -split '>>', 2)[0]).Trim() -replace '\s+', ' '
		}
	}
	return @($lines)
}
$bad = @()
for ($i = $official + 1; $i -lt $enParts.Count; $i++) {
	$a = Command-Lines $enParts[$i]
	$b = Command-Lines $trParts[$i]
	# .target / .mob names are not translated in the output either way; compare the rest.
	$skip = '^\.(target|mob|unitscan)\b'
	$a = @($a | Where-Object { $_ -notmatch $skip })
	$b = @($b | Where-Object { $_ -notmatch $skip })
	if (($a -join "`n") -ne ($b -join "`n")) {
		$name = ([regex]::Match($enParts[$i], '(?m)^#name (.+)$')).Groups[1].Value.Trim()
		$bad += "$i  $name"
	}
}
if ($bad.Count -gt 0) {
	Write-Warning "$($bad.Count) guides differ from the English twin in their commands (the translator changed something it must not):"
	$bad | Select-Object -First 20 | ForEach-Object { Write-Warning "  $_" }
	throw "Not written. Fix the translator output first."
}

# Header and the official guides from the German file, the rest from the translation (LF -> CRLF like the other guide files).
$out = New-Object System.Text.StringBuilder
[void]$out.Append($deParts[0])
for ($i = 1; $i -le $official; $i++) { [void]$out.Append($deParts[$i]) }
for ($i = $official + 1; $i -lt $trParts.Count; $i++) {
	[void]$out.Append(($trParts[$i] -replace "(?<!`r)`n", "`r`n"))
}
$bytes = $utf8.GetBytes($out.ToString())

Write-Host "$($enParts.Count - 1) guides: $official official German + $($enParts.Count - 1 - $official) translated; $($bytes.Length) bytes."
if (-not $WhatIf) {
	[IO.File]::WriteAllBytes($de, $bytes)
	Write-Host "Wrote $de"
}
