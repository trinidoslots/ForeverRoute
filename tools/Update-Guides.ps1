<#
.SYNOPSIS
  Copies the Forever / survival guides from an RXPGuides release into ForeverRoute.

.DESCRIPTION
  The bundled guides are the RestedXP files with three mechanical edits:
    1. The locale check line ("is a localized guide loaded?") becomes
       ForeverRoute.loadingLocale = "enUS" (or "deDE", "esES", ...).
    2. A line ForeverRoute.guideFile = "forever/Horde-01-14_Undead" follows it:
       the same id in the English file and the translated files of a guide, so a
       translated guide can be paired with its English twin (see FR.PairGuides).
    3. RXPGuides.RegisterGuide( becomes ForeverRoute.RegisterGuide(
  Everything else (line endings, text) is kept byte for byte.

  Languages: English (Guides\forever, Guides\SurvivalGuide) and the translations RestedXP
  ships in lang\Guides-<locale> (deDE, esES, frFR, ptBR, zhCN).

.PARAMETER Source
  The unpacked RXPGuides folder (the one that contains Guides\ and lang\).

.PARAMETER WhatIf
  Only report what would change.

.EXAMPLE
  .\tools\Update-Guides.ps1 -Source "C:\Users\Me\Downloads\RXPGuides-v4.11.36\RXPGuides"
#>
param(
	[Parameter(Mandatory)] [string] $Source,
	[switch] $WhatIf
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)

# source folder -> target folder (relative to Guides\), locale written into line 1
$maps = @(
	@{ From = "Guides\forever";       To = "enUS\forever";  Locale = "enUS" },
	@{ From = "Guides\SurvivalGuide"; To = "enUS\survival"; Locale = "enUS" }
)
foreach ($loc in @("deDE", "esES", "frFR", "ptBR", "zhCN")) {
	$maps += @{ From = "lang\Guides-$loc\forever";       To = "$loc\forever";  Locale = $loc }
	$maps += @{ From = "lang\Guides-$loc\SurvivalGuide"; To = "$loc\survival"; Locale = $loc }
}

$enHeader = 'local L = GetLocale() if L and RXP.enabledLocale[L] then return end'
# if GetLocale() ~= "deDE" then return end        (esES also allows esMX)
$trHeader = [regex]'if GetLocale\(\) ~= "[A-Za-z]{4}"( and GetLocale\(\) ~= "[A-Za-z]{4}")* then return end'

$changed = 0; $same = 0; $new = 0
foreach ($m in $maps) {
	$srcDir = Join-Path $Source $m.From
	if (-not (Test-Path $srcDir)) { throw "Missing source folder: $srcDir" }
	foreach ($f in Get-ChildItem $srcDir -Recurse -File -Filter *.lua) {
		$rel = $f.FullName.Substring($srcDir.Length).TrimStart('\')
		# "RestedXP-Skyborne V2.lua" is an #internal test version: RestedXP's Forever bundle does not load it.
		if ($f.BaseName -match ' V2$') { continue }
		$dst =Join-Path (Join-Path $root "Guides\$($m.To)") $rel
		$text = $utf8.GetString([IO.File]::ReadAllBytes($f.FullName))

		# Same id for the enUS file and its translations: "forever/dungeon/Horde-01-14_Undead".
		$id = ($m.To -replace '^(enUS|deDE|esES|frFR|ptBR|zhCN)\\', '')
		$sub = [IO.Path]::GetDirectoryName($rel)
		if ($sub) { $id = $id + "\" + $sub }
		$id = ($id + "\" + [IO.Path]::GetFileNameWithoutExtension($rel)).Replace("\", "/")
		$eol = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
		$want = "ForeverRoute.loadingLocale = `"$($m.Locale)`"" + $eol + "ForeverRoute.guideFile = `"$id`""
		# The check line is usually line 1, but some files have comment lines before it.
		$head = $text.Substring(0, [Math]::Min(400, $text.Length))
		if ($m.Locale -eq "enUS") {
			$at = $text.IndexOf($enHeader); $len = $enHeader.Length
			if ($at -lt 0 -or $at -ge 400) { $at = -1 }
		} else {
			$hit = $trHeader.Match($head)
			if ($hit.Success) { $at = $hit.Index; $len = $hit.Length } else { $at = -1 }
		}
		if ($at -ge 0) {
			$text = $text.Substring(0, $at) + $want + $text.Substring($at + $len)
		} else {
			Write-Warning "$rel : locale check line not found, header not rewritten"
		}
		$text = $text.Replace("RXPGuides.RegisterGuide(", "ForeverRoute.RegisterGuide(")
		# RestedXP's Guides\forever\RestedXP-Skyborne.lua only holds the two Zephras Isle guides (1-13).
		# Everything from level 13 to 60 (and Hyjal, Riverglades, the dungeon quests) is in
		# Forever\Forever.lua, one file of RegisterGuide calls: it goes behind them in the enUS file.
		if ($m.To -eq "enUS\forever" -and $rel -eq "RestedXP-Skyborne.lua") {
			$bundle = Join-Path $Source "Forever\Forever.lua"
			if (-not (Test-Path $bundle)) { throw "Missing $bundle (the guides for levels 13-60)" }
			$more = $utf8.GetString([IO.File]::ReadAllBytes($bundle)).Replace("RXPGuides.RegisterGuide(", "ForeverRoute.RegisterGuide(")
			if (-not $text.EndsWith("`n")) { $text += $eol }
			$text += $more
			if (-not $text.EndsWith("`n")) { $text += $eol }
		}
		$bytes =$utf8.GetBytes($text)

		if (Test-Path $dst) {
			$old = [IO.File]::ReadAllBytes($dst)
			if ([System.Linq.Enumerable]::SequenceEqual([byte[]]$old, [byte[]]$bytes)) { $same++; continue }
			$changed++; Write-Host "changed  $($m.To)\$rel"
		} else {
			$new++; Write-Host "NEW      $($m.To)\$rel (add it to Guides\Guides.xml)"
		}
		if (-not $WhatIf) {
			New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
			[IO.File]::WriteAllBytes($dst, $bytes)
		}
	}
}
Write-Host "`n$changed changed, $new new, $same unchanged."
