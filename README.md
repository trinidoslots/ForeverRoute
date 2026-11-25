# ForeverRoute

A step-by-step leveling guide addon for **WoW Forever**. It shows the next step in a small window, points an arrow at where to go, and tracks your quests as you play.

## Features

- Guide window with the current step, quest objectives and progress
- Missing quests: when a step needs a quest that is not in your log (or whose pre-quest is missing), a card offers a route to get it (a detour that returns to the guide) or to skip it, and lists the later quests you may miss. Uses Questie's database when installed; `/fr missed` lists skipped quests
- Waypoint arrow, world map pins and minimap pins
- Name plate icons for the enemies and NPCs the current step needs
- Optional quest automation (accept, turn in, gossip) and an inventory/junk manager
- Party step sharing, hardcore mode, gold mode, leveling report and step history
- Guides in English, German, Spanish, French, Portuguese and Chinese (menus in English and German)
- A chat notice when another ForeverRoute user runs a newer version

## Install

Copy the `ForeverRoute` folder into `Interface\AddOns`, or install it with the CurseForge app. Type `/fr` in game to open the window and `/fr help` for all commands.

## Update notice

An addon cannot look up the newest version on the internet, so ForeverRoute users tell each other: after login the version is shared with your guild, your group and a hidden chat channel (`FRVersion`, switch it off under Settings > General > "Check for new versions"). Nothing but the version number is sent. If someone runs a newer version, you get a chat line on login, and again on every login until you update. `/fr version` shows the state, `/fr update` explains how to update. This works between players who run a version that has this check.

## Releasing (for the author)

`.\tools\Release.ps1 -Message "what changed"` bumps the version in `ForeverRoute.toc`, commits, tags and pushes. Pushing a `v*` tag runs the GitHub Action that packages the addon and uploads it to CurseForge (needs the `CF_API_KEY` repository secret and `## X-Curse-Project-ID` in the TOC).

## Credits and license

The guides are by **RestedXP** and are used under the [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-nc-sa/4.0/) license. They were modified for ForeverRoute. This project is free and non-commercial. See `Guides\LICENSE.txt`.
