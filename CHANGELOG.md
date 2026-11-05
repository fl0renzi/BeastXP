# BeastXP

## 1.4.0

- The tooltip now shows your pet's experience per hour and the time to its next level. They count only while your pet is out and start over at each login and for a different pet. For the first minute the tooltip says it is gathering. Turn them off with *Experience rate in tooltip* in the right-click menu, on the settings page or with `/petxp rate off`. Start them over with *Reset session* or `/petxp session reset`, and see them in chat with `/petxp session`.
- A level-up alert: when your pet gains a level, the game's level up sound plays, the bar flashes, and chat says, in the same yellow as the game's line for your own level up, "Grimtooth has reached level 15!" and "Grimtooth has 5 training points to spend." A banner near the top of the screen shows the same for a few seconds: your pet's name over its new level in large gold letters, in the art of the game's own level-up banner. Turn each part off under *Level-up alert* in the right-click menu, on the settings page, or with `/petxp levelalert sound off`, `flash off`, `chat off` or `banner off`. *Test alert*, or `/petxp levelalert test`, plays it. Summoning, swapping or logging in never raises one.
- A feed reminder: when your pet's happiness drops, from Happy to Content or from Content to Unhappy, a short sound plays, the bar flashes in the new mood's color, and a line in chat says it is time to feed it. It is off until you turn it on: tick each part under *Feed reminder* in the right-click menu or on the settings page, or type `/petxp feedalert sound on`, `flash on` or `chat on`. *Test reminder*, or `/petxp feedalert test`, plays it.
- New *Fade out of combat* option: the bar fades while you are out of combat, to an opacity you set from 0 to 100% (40% to start), and comes back to full in combat, under the mouse, while you drag it, while an alert flashes and in Edit Mode. It is off until you tick it in the right-click menu or on the settings page, or type `/petxp fade on`. `/petxp fade 25` sets the opacity.
- New *Color by happiness* option: the bar turns green while your pet is happy, yellow while it is content and red while it is unhappy. It is off until you tick it under *Bar color* in the right-click menu, on the settings page, or with `/petxp happycolor on`. The settings page's *Preview mood* shows each color on the preview.
- The settings page has three new sections, *Tooltip and session*, *Alerts and colors* and *Fade*.
- While your pet is dead the bar says "Pet dead", and the tooltip says so too. The experience rate's clock stops until it is back.
- A bar shown with no pet out, unlocked or in Edit Mode, now says "No pet" even with the *No text* style, so it never sits there empty.

## 1.3.0

- The tooltip now shows your pet's happiness, in the words the game's pet panel uses: Happy, Content or Unhappy.
- A new Happiness text option adds it to the bar too, between the loyalty rank and the training points, for example "15%  Faithful  Happy  25 TP". It is off until you tick it, in the right-click Text menu, on the settings page, or with `/petxp happiness on`.
- The right-click menu and the settings page show which version of BeastXP you have.
- Fixed: with a font from another addon, the bar's text no longer stays blank after logging in until your pet gains experience.

## 1.2.0

- Type an exact width and height in the boxes beside the settings page's sliders, or use `/petxp width` and `/petxp height`.
- New X position and Y position settings place the bar exactly, measured from the center of the screen, with a slider and a box each, or `/petxp position <x> <y>`.
- The bar joins the game's Edit Mode: while Edit Mode is open it shows even without a pet, highlighted with its X and Y, and can be dragged and resized even when locked. Hover it and use the arrow keys to move it 1 at a time, or 10 with Shift. Closing Edit Mode puts it back the way it was.
- Fixed: the settings page no longer runs past the bottom of the settings window. When it doesn't fit, it scrolls.

## 1.1.0

- The tooltip now shows your pet's loyalty rank, whether it is gaining or losing loyalty, and its unspent training points.
- New Text options add the loyalty rank and the unspent training points to the bar itself, after any text style, for example "15%  Faithful  25 TP". Both are off until you tick them, in the right-click Text menu, on the settings page, or with `/petxp loyalty on` and `/petxp training on`.

## 1.0.1

- The download now holds only the addon's own files.

## 1.0.0

First release.

- A single bar for your hunter pet's experience: its level, its experience into the level and the percentage.
- Drag the bar to move it, drag its corner to resize it, and lock it in place. A locked bar hides while no pet is out.
- Choose the texture, color, font, font size, outline and how much text the bar shows. Textures and fonts from any SharedMedia addon are listed too.
- A tooltip with your pet's name and the experience it still needs, which you can turn off.
- A settings page under Options > AddOns with a live preview of the bar, and `/petxp` slash commands for every option.
