# BeastXP

A single bar for your hunter pet's experience, for World of Warcraft: Forever. Nothing else.

The bar has no border: just a thin dark backing behind the fill, in the purple the game draws
experience in. It shows the pet's level, its experience into the level and the percentage, for
example `Level 14   340 / 2150  (15%)`. Hover it for the pet's name, the experience it still
needs, its loyalty rank (and whether it is gaining or losing loyalty) and its unspent training
points, unless you turn the tooltip off.

## Settings page

Type `/petxp`, pick *Settings...* in the bar's right-click menu, or open the game's *Options* and
look under *AddOns*. The page is laid out like the game's own settings, the same way ItemTree and
QuestForever lay out theirs:

- **Preview**: a copy of the bar, since the settings window usually covers the real one. It shows
  your pet when one is out and a sample pet otherwise.
- **Bar**: *Lock bar*, *Show tooltip*, *Width* and *Height* sliders, *Texture*, *Color* (click the
  swatch for the color picker, or pick a preset), and *Reset position*.
- **Text**: the text style, *Loyalty* and *Training points*, *Font*, a *Font size* slider and
  *Outline*.
- **Defaults** (top right) puts every setting back to how a fresh install has it, but leaves the bar
  where it is. It asks for a second click first.

Every change shows on the bar at once. The page, the right-click menu and the slash commands all
change the same settings, so a change made in one shows in the others. In combat the game will not
open its settings window, so `/petxp` opens the page as soon as combat ends.

## Using it

The bar starts **unlocked** on a fresh install, so you can put it where you want straight away.

- **Move**: drag the bar.
- **Resize**: drag the grip in its bottom-right corner. It never grows wider than the screen.
- **Texture**: right-click the bar and pick from *Texture*. Blizzard, the character skills bar and a
  solid fill are always there, along with every status bar texture registered with LibSharedMedia.
- **Color**: right-click the bar and pick from *Bar color*: experience purple (the default), rested
  blue, reputation green, or *Custom color...* for the game's color picker. The bar previews the
  color as you drag, and Cancel puts the old one back.
- **Text**: right-click the bar and pick how much it says under *Text*. Each entry shows an example:
  `Level 14   1290 / 2150  (60%)`, `14  1290/2150  60%`, `14  60%`, `60%`, or no text at all. The
  short style writes large numbers as `12.3k`. Tick *Loyalty* or *Training points* in the same menu
  to add the pet's loyalty rank or its unspent training points after the text, for example
  `15%  Faithful  25 TP`. Both are off for a fresh install, and *No text* leaves them out too.
- **Font**: right-click the bar for the font, the font size and the outline. The four fonts the game
  ships are always listed, along with every LibSharedMedia font.
- **Lock**: right-click the bar and tick *Lock bar*. A locked bar cannot be moved or resized, hides
  its grip, and hides itself while no pet is out. While it is unlocked it stays on screen even without
  a pet, so you can place it.
- **Tooltip**: right-click the bar and untick *Show tooltip*, and hovering over the bar or its grip
  shows nothing. It is on for a fresh install.

The same options as slash commands, under `/beastxp` or `/petxp` for short. A texture or font is
found by its name or any part of it:

```
/petxp                    opens the settings page
/petxp help               lists these commands
/petxp lock | unlock
/petxp tooltip on | off
/petxp texture <name>     for example: blizzard, solid, skills
/petxp color              opens the color picker
/petxp color <color>      purple | blue | green | reset | a hex code like 33aaff
/petxp text <style>       full | short | level | percent | none
/petxp loyalty on | off   the loyalty rank after the text
/petxp training on | off  unspent training points after the text (tp works too)
/petxp font <name>        for example: friz, arial, morpheus
/petxp size 6-32
/petxp outline none | outline | thick
/petxp reset
```

On a character that is not a hunter the bar is never built and the addon stops listening after
login. The settings page is still there, since the settings are shared by every character.

## LibSharedMedia

BeastXP does not bundle LibSharedMedia-3.0. On its own it lists the textures and fonts the game ships.
For more, install any addon that registers media with LibSharedMedia, such as a SharedMedia pack or a
UI suite that brings its own, and its textures and fonts join the lists. BeastXP looks the library up
only when you open a list, so it finds it whichever addon loaded it.

A texture or font is saved by its file path, not its LibSharedMedia name, so a choice keeps working
however late the addon that registered it loads. If the file is gone (that addon was removed), the
bar falls back to the Blizzard texture or the Friz Quadrata font until you pick another.

## Install

Install it from CurseForge, or copy `BeastXP.toc`, `BeastXP.lua` and `BeastXP_Options.lua` into
`Interface\AddOns\BeastXP` in the Forever client folder, then restart the game. The game reads the
`.toc` only at startup, so a new addon, or a new file in one, is not picked up by `/reload`.

## Notes

- Forever only. The toc is `16001`; on any other client the addon prints one line and stays inert,
  leaving `BeastXPDB` untouched.
- Settings live in the account-wide `BeastXPDB`. The Forever beta writes a per-character
  SavedVariables file but never loads it back. Every setting applies immediately, with no reload.
- Event-driven: the bar refreshes on `UNIT_PET`, `UNIT_PET_EXPERIENCE`, `UNIT_LEVEL`,
  `PET_UI_UPDATE`, `PLAYER_XP_UPDATE` and `PLAYER_ENTERING_WORLD`, never from `OnUpdate`.
  `UNIT_HAPPINESS` and `UNIT_PET_TRAINING_POINTS` keep loyalty and training points current, on the
  bar and in an open tooltip.
- Loyalty and training points come from `C_PetInfo`, read the way the game's own pet panel and
  trainer read them. Whatever the client does not report is left out, on the bar and in the tooltip.

## Tests

`npm install` once, then `npm test`. It loads every file the `.toc` lists into a Lua VM on a mocked
WoW API (`tests/wow_stub.lua`) and runs `tests/spec.lua`. The mock includes a small stand-in for a
LibSharedMedia loaded by another addon. The mock is not the game, so still check the bar in the
client.

## Releasing

Add the release's notes to `CHANGELOG.md`, which becomes the file's changelog on CurseForge, then
push a tag such as `v1.1.0`. Neither the changelog nor this readme goes into the zip. The release
workflow (`.github/workflows/release.yml`) runs the tests, then the BigWigs packager builds the zip
from `.pkgmeta`, writes the tag into the toc's `Version`, and publishes it as a GitHub release and
to CurseForge under the Forever flavor. A tag containing `alpha` or `beta` is uploaded as that
release type. CurseForge needs the `CF_API_TOKEN` repository secret and the toc's
`X-Curse-Project-ID`; without them the packager only makes the GitHub release.
