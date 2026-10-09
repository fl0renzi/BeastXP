-- BeastXP - tests/spec.lua
-- Behaviour tests for the addon, run on top of tests/wow_stub.lua. Every test
-- boots a fresh session with __boot, so no test depends on another.

local passed, failed = 0, 0

local function test(name, body)
    local ok, err = pcall(body)
    if ok then
        passed = passed + 1
        __print("ok   " .. name)
    else
        failed = failed + 1
        __print("FAIL " .. name .. "\n     " .. tostring(err))
    end
end

local function assert_eq(actual, expected, label)
    if actual ~= expected then
        error((label and (label .. ": ") or "") .. "expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local function assert_true(value, label)
    if not value then error(label or "expected a true value", 2) end
end

local function assert_false(value, label)
    if value then error(label or "expected a false value", 2) end
end

local function has_line(lines, wanted)
    for _, line in ipairs(lines) do
        if line == wanted then return true end
    end
    return false
end

-- A hunter pet at level 14, 340 of 2150 into the level.
local function hunterPet(overrides)
    local pet = { current = 340, max = 2150, level = 14, name = "Grimtooth" }
    for key, value in pairs(overrides or {}) do pet[key] = value end
    return pet
end

--------------------------------------------------------------------------------
-- Showing the pet's experience
--------------------------------------------------------------------------------

test("a hunter with a pet out sees its level and experience", function()
    __boot({ pet = hunterPet() })
    local bar = BeastXPBar
    assert_true(bar, "no bar was built")
    assert_true(bar:IsShown(), "bar hidden")
    assert_eq(bar.text:GetText(), "Level 14   340 / 2150  (15%)")
    local minimum, maximum = bar.status:GetMinMaxValues()
    assert_eq(minimum, 0)
    assert_eq(maximum, 2150)
    assert_eq(bar.status:GetValue(), 340)
end)

test("the bar has no border, only a dark backing behind the stock texture", function()
    __boot({ pet = hunterPet() })
    local bar = BeastXPBar
    assert_eq(bar.__template, nil, "built from a template")
    assert_eq(bar.status.__barTexture, "Interface\\TargetingFrame\\UI-StatusBar")
    assert_eq(bar.track.__texture, "Interface\\TargetingFrame\\UI-StatusBar")
    assert_eq(bar.status.__barColor[1], 0.58)
    local topLeft, bottomRight = bar.status.__points[1], bar.status.__points[2]
    assert_eq(topLeft[2], 1, "the bar is not one pixel inside the backing")
    assert_eq(topLeft[3], -1, "the bar is not one pixel inside the backing")
    assert_eq(bottomRight[2], -1, "the bar is not one pixel inside the backing")
    assert_eq(bottomRight[3], 1, "the bar is not one pixel inside the backing")
    assert_eq(bar.grip.__normal, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    assert_true(#bar.__points > 0, "the bar has no anchor and would never be drawn")
end)

test("a first install starts unlocked, so the bar can be placed straight away", function()
    __boot({ pet = hunterPet() })
    assert_eq(BeastXPDB.locked, false)
    assert_true(BeastXPBar.grip:IsShown(), "no resize grip on a first install")
    __script(BeastXPBar, "OnDragStart")
    assert_true(BeastXPBar.__moving, "a first install cannot be dragged")
    __script(BeastXPBar, "OnDragStop")

    -- Without a pet too: the bar shows so it can be put where it belongs.
    __boot({})
    assert_true(BeastXPBar and BeastXPBar:IsShown(), "no bar to place before a pet is out")
end)

test("UNIT_PET_EXPERIENCE moves the bar", function()
    __boot({ pet = hunterPet() })
    __pet.current = 2000
    __fire("UNIT_PET_EXPERIENCE", "pet")
    assert_eq(BeastXPBar.text:GetText(), "Level 14   2000 / 2150  (93%)")
    assert_eq(BeastXPBar.status:GetValue(), 2000)
end)

test("UNIT_LEVEL refreshes for the pet and ignores other units", function()
    __boot({ pet = hunterPet() })
    __pet.level = 15
    __fire("UNIT_LEVEL", "target")
    assert_eq(BeastXPBar.text:GetText(), "Level 14   340 / 2150  (15%)")
    __fire("UNIT_LEVEL", "pet")
    assert_eq(BeastXPBar.text:GetText(), "Level 15   340 / 2150  (15%)")
end)

test("a pet with no experience to report shows its level alone", function()
    __boot({ pet = hunterPet({ current = 0, max = 0, level = 60 }) })
    assert_eq(BeastXPBar.text:GetText(), "Level 60")
    local _, maximum = BeastXPBar.status:GetMinMaxValues()
    assert_eq(maximum, 1)
    assert_eq(BeastXPBar.status:GetValue(), 0)
end)

test("the tooltip names the pet and the experience to the next level", function()
    __boot({ pet = hunterPet() })
    __script(BeastXPBar, "OnEnter")
    local lines = GameTooltip.__lines
    assert_true(has_line(lines, "Grimtooth"), "no pet name")
    assert_true(has_line(lines, "Level 14"), "no level")
    assert_true(has_line(lines, "Experience | 340 / 2150"), "no experience line")
    assert_true(has_line(lines, "To next level | 1810"), "no remaining line")

    -- A change while the tooltip is up redraws it.
    __pet.current = 400
    __fire("UNIT_PET_EXPERIENCE", "pet")
    assert_true(has_line(GameTooltip.__lines, "To next level | 1750"), "tooltip not refreshed")

    __script(BeastXPBar, "OnLeave")
    assert_false(GameTooltip:IsShown(), "tooltip still up")
end)

test("with the tooltip off, hovering the bar or its grip shows nothing", function()
    __boot({ pet = hunterPet() })
    assert_eq(BeastXPDB.showTooltip, true, "a fresh install has no tooltip")

    -- Turning it off while the tooltip is up puts it away.
    __script(BeastXPBar, "OnEnter")
    assert_true(GameTooltip:IsShown(), "no tooltip while on")
    SlashCmdList.BEASTXP("tooltip off")
    assert_eq(BeastXPDB.showTooltip, false)
    assert_false(GameTooltip:IsShown(), "tooltip left up after turning it off")
    assert_true(__printed("tooltip off"), "no confirmation")

    __script(BeastXPBar, "OnEnter")
    assert_false(GameTooltip:IsShown(), "bar tooltip shown while off")
    __fire("UNIT_PET_EXPERIENCE", "pet")
    assert_false(GameTooltip:IsShown(), "a refresh brought the tooltip back")
    __script(BeastXPBar.grip, "OnEnter")
    assert_false(GameTooltip:IsShown(), "grip tooltip shown while off")

    SlashCmdList.BEASTXP("tooltip maybe")
    assert_eq(BeastXPDB.showTooltip, false, "a bad word changed the setting")
    assert_true(__printed("use /petxp tooltip on"), "no usage for a bad word")

    SlashCmdList.BEASTXP("tooltip on")
    __script(BeastXPBar, "OnEnter")
    assert_true(has_line(GameTooltip.__lines, "Grimtooth"), "tooltip not back after turning it on")

    -- The choice is saved.
    __boot({ pet = hunterPet(), db = { showTooltip = false } })
    __script(BeastXPBar, "OnEnter")
    assert_false(GameTooltip:IsShown(), "saved choice not kept")
end)

--------------------------------------------------------------------------------
-- When the bar shows at all
--------------------------------------------------------------------------------

test("a character that is not a hunter builds nothing and listens to nothing", function()
    __boot({ class = "MAGE", pet = hunterPet() })
    assert_eq(BeastXPBar, nil, "a bar was built")
    assert_false(__registered("PLAYER_LOGIN"), "still listening for login")
    assert_false(__registered("UNIT_PET_EXPERIENCE"), "listening for pet experience")
end)

test("a hunter without a pet sees a placeholder while unlocked, nothing once locked", function()
    __boot({})
    assert_true(BeastXPBar and BeastXPBar:IsShown(), "unlocked bar not shown for placing")
    assert_eq(BeastXPBar.text:GetText(), "No pet")

    SlashCmdList.BEASTXP("lock")
    assert_false(BeastXPBar:IsShown(), "locked bar shown with no pet")

    __pet = hunterPet()
    __fire("UNIT_PET", "player")
    assert_true(BeastXPBar:IsShown(), "bar not shown when the pet came out")

    __pet = nil
    __fire("UNIT_PET", "player")
    assert_false(BeastXPBar:IsShown(), "bar still shown after the pet left")
end)

test("a locked hunter with no pet out builds nothing at login", function()
    __boot({ db = { locked = true } })
    assert_eq(BeastXPBar, nil, "a bar was built with nothing to show")
end)

test("a pet that is not a hunter pet counts as no pet", function()
    __boot({ pet = hunterPet({ hunter = false }), db = { locked = true } })
    assert_eq(BeastXPBar, nil, "a bar was built for a non-hunter pet")
end)

test("UNIT_PET for another unit is ignored", function()
    __boot({ db = { locked = true } })
    __pet = hunterPet()
    __fire("UNIT_PET", "party1")
    assert_eq(BeastXPBar, nil, "refreshed on a party member's pet")
end)

--------------------------------------------------------------------------------
-- Moving and resizing
--------------------------------------------------------------------------------

test("dragging moves the bar and saves where it went", function()
    __boot({ pet = hunterPet() })
    local bar = BeastXPBar
    __script(bar, "OnDragStart")
    assert_true(bar.__moving, "drag did not start moving")
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 100, 200)
    __script(bar, "OnDragStop")
    assert_eq(bar.__moving, nil, "still moving")
    assert_eq(BeastXPDB.point, "BOTTOMLEFT")
    assert_eq(BeastXPDB.relativePoint, "BOTTOMLEFT")
    assert_eq(BeastXPDB.x, 100)
    assert_eq(BeastXPDB.y, 200)
end)

test("the corner grip resizes the bar and saves the size", function()
    __boot({ pet = hunterPet() })
    local bar, grip = BeastXPBar, BeastXPBar.grip
    assert_true(bar.__resizable, "bar not resizable")
    assert_eq(bar.__bounds[1], 80)
    assert_eq(bar.__bounds[2], 6)
    assert_eq(bar.__bounds[3], 1880, "max width not taken from the screen")
    assert_eq(bar.__bounds[4], 64)

    __script(grip, "OnMouseDown", "LeftButton")
    assert_eq(bar.__sizing, "BOTTOMRIGHT")
    bar:SetSize(400.4, 30.6)
    __script(grip, "OnMouseUp", "LeftButton")
    assert_eq(bar.__sizing, nil, "still sizing")
    assert_eq(BeastXPDB.width, 400)
    assert_eq(BeastXPDB.height, 31)
end)

test("the grip ignores the right mouse button", function()
    __boot({ pet = hunterPet() })
    __script(BeastXPBar.grip, "OnMouseDown", "RightButton")
    assert_eq(BeastXPBar.__sizing, nil)
end)

test("a locked bar cannot be dragged or resized, and hides its grip", function()
    __boot({ pet = hunterPet() })
    local bar = BeastXPBar
    SlashCmdList.BEASTXP("lock")
    assert_false(bar.grip:IsShown(), "grip shown while locked")
    __script(bar, "OnDragStart")
    assert_eq(bar.__moving, nil, "locked bar moved")
    __script(bar.grip, "OnMouseDown", "LeftButton")
    assert_eq(bar.__sizing, nil, "locked bar resized")

    SlashCmdList.BEASTXP("unlock")
    assert_true(bar.grip:IsShown(), "grip not back after unlocking")
end)

test("hiding the bar mid-drag lets go of it", function()
    __boot({ pet = hunterPet() })
    local bar = BeastXPBar
    __script(bar, "OnDragStart")
    bar:Hide()
    assert_eq(bar.__moving, nil, "bar still stuck to the cursor")
    assert_eq(bar.__stopped, 1)
end)

test("the saved position and size come back next session", function()
    __boot({
        pet = hunterPet(),
        db = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 50, y = -60, width = 300, height = 30 },
    })
    local point, relativeTo, relativePoint, x, y = BeastXPBar:GetPoint()
    assert_eq(point, "TOPLEFT")
    assert_eq(relativeTo, UIParent)
    assert_eq(relativePoint, "TOPLEFT")
    assert_eq(x, 50)
    assert_eq(y, -60)
    assert_eq(BeastXPBar:GetWidth(), 300)
    assert_eq(BeastXPBar:GetHeight(), 30)
end)

test("a saved size larger than the screen is pulled back in", function()
    __boot({ pet = hunterPet(), db = { width = 5000, height = 500 } })
    assert_eq(BeastXPBar:GetWidth(), 1880)
    assert_eq(BeastXPBar:GetHeight(), 64)
end)

test("reset puts the bar back in its first spot at its first size", function()
    __boot({
        pet = hunterPet(),
        db = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 50, y = -60, width = 300, height = 30 },
    })
    SlashCmdList.BEASTXP("reset")
    assert_eq(BeastXPDB.point, nil)
    local point, _, _, x, y = BeastXPBar:GetPoint()
    assert_eq(point, "CENTER")
    assert_eq(x, 0)
    assert_eq(y, -180)
    assert_eq(BeastXPBar:GetWidth(), 240)
    assert_eq(BeastXPBar:GetHeight(), 18)
end)

--------------------------------------------------------------------------------
-- The right-click menu and fonts
--------------------------------------------------------------------------------

test("right-click opens the client's menu with lock, font, size and outline", function()
    __boot({ pet = hunterPet() })
    __script(BeastXPBar, "OnMouseUp", "LeftButton")
    assert_eq(__menu, nil, "left click opened the menu")
    __script(BeastXPBar, "OnMouseUp", "RightButton")
    assert_true(__menu, "no menu")
    assert_eq(__menu.children[1].kind, "title")
    assert_true(__menu_item("Lock bar"), "no lock entry")
    assert_true(__menu_item("Font", "Friz Quadrata"), "no Friz Quadrata")
    assert_true(__menu_item("Font", "Morpheus"), "no Morpheus")
    assert_true(__menu_item("Font size", "12"), "no size 12")
    assert_true(__menu_item("Outline", "Thick outline"), "no thick outline")
    assert_true(__menu_item("Reset position and size"), "no reset")
end)

test("picking a font, a size and an outline restyles the text at once", function()
    __boot({ pet = hunterPet() })
    __script(BeastXPBar, "OnMouseUp", "RightButton")

    local arial = __menu_item("Font", "Arial Narrow")
    assert_false(__menu_selected(arial), "Arial selected before the click")
    assert_true(__menu_selected(__menu_item("Font", "Friz Quadrata")), "default font not selected")
    __menu_click(arial)
    assert_true(__menu_selected(arial), "Arial not selected after the click")

    __menu_click(__menu_item("Font size", "16"))
    __menu_click(__menu_item("Outline", "Thick outline"))

    local path, size, flags = BeastXPBar.text:GetFont()
    assert_eq(path, "Fonts\\ARIALN.TTF")
    assert_eq(size, 16)
    assert_eq(flags, "THICKOUTLINE")
    assert_eq(BeastXPDB.fontPath, "Fonts\\ARIALN.TTF")
    assert_eq(BeastXPDB.fontSize, 16)
    assert_eq(BeastXPDB.outline, "THICKOUTLINE")
end)

test("the menu's lock entry and reset entry work", function()
    __boot({ pet = hunterPet(), db = { width = 300 } })
    __script(BeastXPBar, "OnMouseUp", "RightButton")
    local lock = __menu_item("Lock bar")
    assert_false(__menu_selected(lock))
    __menu_click(lock)
    assert_true(BeastXPDB.locked, "not locked")
    assert_true(__menu_selected(lock))
    assert_false(BeastXPBar.grip:IsShown(), "grip still shown")

    __menu_click(__menu_item("Reset position and size"))
    assert_eq(BeastXPBar:GetWidth(), 240)
end)

test("the menu's Show tooltip entry turns the tooltip off and on", function()
    __boot({ pet = hunterPet() })
    __script(BeastXPBar, "OnMouseUp", "RightButton")
    local item = __menu_item("Show tooltip")
    assert_true(item, "no tooltip entry")
    assert_true(__menu_selected(item), "not ticked on a fresh install")
    __menu_click(item)
    assert_false(BeastXPDB.showTooltip, "not turned off")
    assert_false(__menu_selected(item))
    __menu_click(item)
    assert_true(BeastXPDB.showTooltip, "not turned back on")
end)

test("a font file that fails to load falls back to the default font", function()
    __boot({ pet = hunterPet() })
    __badFonts["fonts\\skurri.ttf"] = true
    SlashCmdList.BEASTXP("font skurri")
    local path, size = BeastXPBar.text:GetFont()
    assert_eq(path, "Fonts\\FRIZQT__.TTF")
    assert_eq(size, 11)

    -- Even with no file loading at all the text keeps a font, so it can be set.
    __badFonts["fonts\\frizqt__.ttf"] = true
    SlashCmdList.BEASTXP("size 13")
    __pet.current = 500
    __fire("UNIT_PET_EXPERIENCE", "pet")
    assert_eq(BeastXPBar.text:GetText(), "Level 14   500 / 2150  (23%)")
end)

-- The embedded LibSharedMedia, as the .toc loaded it.
local function LSM()
    return LibStub("LibSharedMedia-3.0")
end

local function count_named(items, name)
    local count = 0
    for _, item in ipairs(items) do
        if item.text == name then count = count + 1 end
    end
    return count
end

test("the embedded LibSharedMedia loads ahead of the addon", function()
    __boot({ pet = hunterPet() })
    assert_true(LibStub and LibStub("LibSharedMedia-3.0", true), "LibSharedMedia not loaded")
    assert_eq(LSM():Fetch("statusbar", "Blizzard"), "Interface\\TargetingFrame\\UI-StatusBar")
end)

test("LibSharedMedia fonts join the font menu without duplicates", function()
    __boot({ pet = hunterPet() })
    LSM():Register("font", "Expressway", "Interface\\AddOns\\Media\\Expressway.ttf")

    __script(BeastXPBar, "OnMouseUp", "RightButton")
    local fonts = __menu_item("Font").children
    assert_eq(fonts[1].text, "Friz Quadrata", "built-in fonts not first")
    assert_true(__menu_item("Font", "Expressway"), "registered font missing")
    assert_true(__menu_item("Font", "Nimrod MT"), "LibSharedMedia's own fonts missing")
    assert_eq(__menu_item("Font", "Friz Quadrata TT"), nil, "same file listed twice")
    assert_eq(count_named(fonts, "Arial Narrow"), 1, "same name listed twice")
    assert_eq(count_named(fonts, "Morpheus"), 1, "same name listed twice")

    __menu_click(__menu_item("Font", "Expressway"))
    assert_eq(BeastXPDB.fontPath, "Interface\\AddOns\\Media\\Expressway.ttf")
    assert_eq((BeastXPBar.text:GetFont()), "Interface\\AddOns\\Media\\Expressway.ttf")
end)

test("a long font list scrolls instead of running off the screen", function()
    __boot({ pet = hunterPet() })
    for i = 1, 30 do
        LSM():Register("font", ("Font %02d"):format(i), ("Interface\\AddOns\\Media\\Font%02d.ttf"):format(i))
    end
    __script(BeastXPBar, "OnMouseUp", "RightButton")
    assert_eq(__menu_item("Font").scroll, 400)
end)

--------------------------------------------------------------------------------
-- Textures
--------------------------------------------------------------------------------

test("picking a texture retextures the fill and the track at once", function()
    __boot({ pet = hunterPet() })
    __script(BeastXPBar, "OnMouseUp", "RightButton")
    assert_true(__menu_selected(__menu_item("Texture", "Blizzard")), "default texture not selected")

    local solid = __menu_item("Texture", "Solid")
    __menu_click(solid)
    assert_true(__menu_selected(solid), "Solid not selected after the click")
    assert_eq(BeastXPDB.texturePath, "Interface\\Buttons\\WHITE8X8")
    assert_eq(BeastXPBar.status.__barTexture, "Interface\\Buttons\\WHITE8X8")
    assert_eq(BeastXPBar.track.__texture, "Interface\\Buttons\\WHITE8X8")
    assert_eq(BeastXPBar.status.__barColor[1], 0.58, "colour lost with the texture")
    assert_eq(BeastXPBar.track.__vertexColor[4], 0.25, "track no longer dim")
end)

test("textures another addon registers, even after login, are listed", function()
    __boot({ pet = hunterPet() })
    LSM():Register("statusbar", "Skullflower", "Interface\\AddOns\\FlorenziMedia\\textures\\Skullflower.tga")

    __script(BeastXPBar, "OnMouseUp", "RightButton")
    local textures = __menu_item("Texture").children
    assert_true(__menu_item("Texture", "Skullflower"), "late texture missing")
    assert_true(__menu_item("Texture", "Blizzard Raid Bar"), "LibSharedMedia's own textures missing")
    assert_eq(count_named(textures, "Blizzard"), 1, "Blizzard listed twice")
    assert_eq(count_named(textures, "Solid"), 1, "Solid listed twice")

    __menu_click(__menu_item("Texture", "Skullflower"))
    assert_eq(BeastXPBar.status.__barTexture, "Interface\\AddOns\\FlorenziMedia\\textures\\Skullflower.tga")
end)

test("a saved texture that no longer loads falls back to Blizzard", function()
    local gone = "Interface\\AddOns\\Removed\\Bar.tga"
    __boot({ pet = hunterPet(), db = { texturePath = gone }, badTextures = { gone } })
    assert_eq(BeastXPBar.status.__barTexture, "Interface\\TargetingFrame\\UI-StatusBar")
    assert_eq(BeastXPBar.track.__texture, "Interface\\TargetingFrame\\UI-StatusBar")
    assert_eq(BeastXPDB.texturePath, gone, "the saved choice was rewritten")
end)

test("the menu still works without LibSharedMedia", function()
    __boot({ pet = hunterPet(), noLibs = true })
    assert_eq(LibStub, nil)
    __script(BeastXPBar, "OnMouseUp", "RightButton")
    assert_eq(#__menu_item("Texture").children, 3)
    assert_eq(#__menu_item("Font").children, 4)
    SlashCmdList.BEASTXP("texture solid")
    assert_eq(BeastXPDB.texturePath, "Interface\\Buttons\\WHITE8X8")
end)

--------------------------------------------------------------------------------
-- Slash commands and saved settings
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Colour
--------------------------------------------------------------------------------

local function assert_color(widget, r, g, b, label)
    local color = widget.__barColor or widget.__vertexColor
    assert_true(math.abs(color[1] - r) < 0.001 and math.abs(color[2] - g) < 0.001
        and math.abs(color[3] - b) < 0.001,
        (label or "colour") .. (": expected %.3f %.3f %.3f, got %.3f %.3f %.3f"):format(
            r, g, b, color[1], color[2], color[3]))
end

test("a fresh bar is experience purple, with a dim track", function()
    __boot({ pet = hunterPet() })
    assert_color(BeastXPBar.status, 0.58, 0.0, 0.55, "fill")
    assert_color(BeastXPBar.track, 0.58, 0.0, 0.55, "track")
    assert_eq(BeastXPBar.track.__vertexColor[4], 0.25)
    __script(BeastXPBar, "OnMouseUp", "RightButton")
    assert_true(__menu_selected(__menu_item("Bar color", "Experience purple")), "purple not selected")
end)

test("a preset colour recolours the fill and the track", function()
    __boot({ pet = hunterPet() })
    __script(BeastXPBar, "OnMouseUp", "RightButton")
    local blue = __menu_item("Bar color", "Rested blue")
    __menu_click(blue)
    assert_true(__menu_selected(blue), "blue not selected")
    assert_false(__menu_selected(__menu_item("Bar color", "Experience purple")), "purple still selected")
    assert_color(BeastXPBar.status, 0.0, 0.39, 0.88, "fill")
    assert_color(BeastXPBar.track, 0.0, 0.39, 0.88, "track")
    assert_eq(BeastXPBar.track.__vertexColor[4], 0.25, "track no longer dim")
end)

test("the colour picker previews on the bar and cancel puts the old colour back", function()
    __boot({ pet = hunterPet() })
    __script(BeastXPBar, "OnMouseUp", "RightButton")
    __menu_click(__menu_item("Bar color", "Custom color..."))
    assert_true(__picker, "picker not opened")
    assert_eq(__picker.r, 0.58, "picker not opened on the current colour")
    assert_false(__picker.hasOpacity)

    __picker_drag(1, 0.5, 0)
    assert_color(BeastXPBar.status, 1, 0.5, 0, "preview")
    assert_eq(BeastXPDB.barColor[1], 1)

    __picker_cancel()
    assert_color(BeastXPBar.status, 0.58, 0.0, 0.55, "after cancel")
    assert_eq(BeastXPDB.barColor[1], 0.58)
end)

test("changing the texture keeps the chosen colour", function()
    __boot({ pet = hunterPet() })
    SlashCmdList.BEASTXP("color green")
    SlashCmdList.BEASTXP("texture solid")
    assert_color(BeastXPBar.status, 0.0, 0.6, 0.1, "fill")
    assert_color(BeastXPBar.track, 0.0, 0.6, 0.1, "track")
end)

test("/petxp color takes a preset, a hex code, reset, or opens the picker", function()
    __boot({ pet = hunterPet() })
    SlashCmdList.BEASTXP("color #33AAFF")
    assert_color(BeastXPBar.status, 0x33 / 255, 0xaa / 255, 1, "hex with #")
    SlashCmdList.BEASTXP("color ff0000")
    assert_color(BeastXPBar.status, 1, 0, 0, "hex")
    SlashCmdList.BEASTXP("color blue")
    assert_color(BeastXPBar.status, 0.0, 0.39, 0.88, "preset")
    SlashCmdList.BEASTXP("color reset")
    assert_color(BeastXPBar.status, 0.58, 0.0, 0.55, "reset")
    SlashCmdList.BEASTXP("color mauve")
    assert_true(__printed("use purple, blue, green or a hex code"), "no message for a bad colour")
    assert_color(BeastXPBar.status, 0.58, 0.0, 0.55, "bad input changed the colour")

    assert_eq(__picker, nil)
    SlashCmdList.BEASTXP("colour")
    assert_true(__picker, "/petxp colour did not open the picker")
end)

test("a colour change never touches the default", function()
    __boot({ pet = hunterPet() })
    SlashCmdList.BEASTXP("color ff0000")
    __boot({ pet = hunterPet() })
    assert_color(BeastXPBar.status, 0.58, 0.0, 0.55, "fresh session")
end)

test("a saved colour comes back, a broken one falls back to purple", function()
    __boot({ pet = hunterPet(), db = { barColor = { 0.1, 0.2, 0.3 } } })
    assert_color(BeastXPBar.status, 0.1, 0.2, 0.3, "saved")

    __boot({ pet = hunterPet(), db = { barColor = { 2, "x" } } })
    assert_color(BeastXPBar.status, 0.58, 0.0, 0.55, "broken")
    __boot({ pet = hunterPet(), db = { barColor = { 0 / 0, 0, 0 } } })
    assert_color(BeastXPBar.status, 0.58, 0.0, 0.55, "NaN")
end)

test("without the colour picker the player is told to use a hex code", function()
    __boot({ pet = hunterPet() })
    ColorPickerFrame = nil
    SlashCmdList.BEASTXP("color")
    assert_true(__printed("give a hex code instead"), "no explanation")
end)

--------------------------------------------------------------------------------
-- Text styles
--------------------------------------------------------------------------------

test("each text style says less", function()
    __boot({ pet = hunterPet() })
    local expected = {
        full    = "Level 14   340 / 2150  (15%)",
        short   = "14  340/2150  15%",
        level   = "14  15%",
        percent = "15%",
        none    = "",
    }
    for _, key in ipairs({ "full", "short", "level", "percent", "none" }) do
        SlashCmdList.BEASTXP("text " .. key)
        assert_eq(BeastXPDB.textStyle, key)
        assert_eq(BeastXPBar.text:GetText(), expected[key], key)
    end
end)

test("the short style shortens large numbers", function()
    __boot({ pet = hunterPet({ current = 12345, max = 98000, level = 52 }), db = { textStyle = "short" } })
    assert_eq(BeastXPBar.text:GetText(), "52  12.3k/98.0k  12%")
end)

test("a text style leaves out what the game did not report", function()
    __boot({ pet = hunterPet({ current = 0, max = 0, level = 60 }), db = { textStyle = "short" } })
    assert_eq(BeastXPBar.text:GetText(), "60")
    SlashCmdList.BEASTXP("text percent")
    assert_eq(BeastXPBar.text:GetText(), "")
    SlashCmdList.BEASTXP("text level")
    assert_eq(BeastXPBar.text:GetText(), "60")
end)

test("the menu's text entries show an example and switch the style", function()
    __boot({ pet = hunterPet() })
    __script(BeastXPBar, "OnMouseUp", "RightButton")
    assert_true(__menu_selected(__menu_item("Text", "Level 14   1290 / 2150  (60%)")), "full not selected")
    __menu_click(__menu_item("Text", "60%"))
    assert_eq(BeastXPBar.text:GetText(), "15%", "the bar shows the real pet, not the example")
    assert_eq(BeastXPDB.textStyle, "percent")
end)

test("an unknown text style is refused, and a broken saved one falls back to full", function()
    __boot({ pet = hunterPet() })
    SlashCmdList.BEASTXP("text tiny")
    assert_true(__printed("use full, short, level, percent or none"), "no message")
    assert_eq(BeastXPDB.textStyle, "full")

    __boot({ pet = hunterPet(), db = { textStyle = "huge" } })
    assert_eq(BeastXPDB.textStyle, "full")
    assert_eq(BeastXPBar.text:GetText(), "Level 14   340 / 2150  (15%)")
end)

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------

local function open_page()
    SlashCmdList.BEASTXP("")
    assert_true(__settings_page():IsVisible(), "settings page not open")
end

test("the settings page is registered under AddOns at login, for every class", function()
    __boot({ pet = hunterPet() })
    assert_eq(__settingsCategory.name, "BeastXP")
    assert_eq(__settingsAddOn, __settingsCategory, "not listed under AddOns")
    assert_false(__settings_page():IsShown(), "page built visible")

    __boot({ class = "MAGE" })
    assert_eq(__settingsCategory and __settingsCategory.name, "BeastXP", "no page for a non-hunter")
end)

test("/petxp opens the settings page, as does the right-click menu", function()
    __boot({ pet = hunterPet() })
    SlashCmdList.BEASTXP("")
    assert_eq(__settingsOpened, "BeastXP")
    assert_true(__settings_page():IsShown(), "page not shown")
    assert_false(__printed("only hunter pets"), "a hunter was told off")

    __boot({ pet = hunterPet() })
    __script(BeastXPBar, "OnMouseUp", "RightButton")
    __menu_click(__menu_item("Settings..."))
    assert_eq(__settingsOpened, "BeastXP")

    __boot({ class = "WARRIOR" })
    SlashCmdList.BEASTXP("options")
    assert_eq(__settingsOpened, "BeastXP", "a non-hunter cannot open the page")
    assert_false(__printed("only hunter pets"), "opening the page warned about the class")
end)

test("in combat the settings page waits for combat to end", function()
    __boot({ pet = hunterPet() })
    __inCombat = true
    SlashCmdList.BEASTXP("")
    assert_eq(__settingsOpened, nil, "opened in combat")
    assert_true(__printed("opens when combat ends"), "no word about combat")

    __inCombat = false
    __fire("PLAYER_REGEN_ENABLED")
    assert_eq(__settingsOpened, "BeastXP", "not opened after combat")
    assert_false(__registered("PLAYER_REGEN_ENABLED"), "still waiting for combat to end")
end)

test("the page shows the current settings when it opens", function()
    __boot({
        pet = hunterPet(),
        db = {
            locked = true, width = 300, height = 20, fontSize = 14, outline = "OUTLINE",
            texturePath = "Interface\\Buttons\\WHITE8X8", barColor = { 0.0, 0.39, 0.88 }, textStyle = "short",
            showTooltip = false,
        },
    })
    open_page()
    assert_true(__control("Lock bar", "UICheckButtonTemplate"):GetChecked(), "lock not ticked")
    assert_false(__control("Show tooltip", "UICheckButtonTemplate"):GetChecked(), "tooltip ticked")
    assert_eq(__control("Width", "MinimalSliderWithSteppersTemplate"):GetValue(), 300)
    assert_eq(__control("Height", "MinimalSliderWithSteppersTemplate"):GetValue(), 20)
    assert_eq(__control("Font size", "MinimalSliderWithSteppersTemplate"):GetValue(), 14)
    assert_eq(__dropdown_text(__control("Texture", "WowStyle1DropdownTemplate")), "Solid")
    assert_eq(__dropdown_text(__control("Color", "WowStyle1DropdownTemplate")), "Rested blue")
    assert_eq(__control("Color", "ColorSwatchTemplate").__swatch[3], 0.88)
    assert_eq(__dropdown_text(__control("Text", "WowStyle1DropdownTemplate")), "14  1290/2150  60%")
    assert_eq(__dropdown_text(__control("Font", "WowStyle1DropdownTemplate")), "Friz Quadrata")
    assert_eq(__dropdown_text(__control("Outline", "WowStyle1DropdownTemplate")), "Outline")
end)

test("every control on the page changes the bar at once", function()
    __boot({ pet = hunterPet() })
    open_page()

    -- A click ticks the box before OnClick runs.
    local lock = __control("Lock bar", "UICheckButtonTemplate")
    lock:SetChecked(true)
    __script(lock, "OnClick")
    assert_true(BeastXPDB.locked, "lock box did not lock")
    assert_false(BeastXPBar.grip:IsShown(), "grip still shown")

    local tooltip = __control("Show tooltip", "UICheckButtonTemplate")
    assert_true(tooltip:GetChecked(), "tooltip box not ticked on a fresh install")
    tooltip:SetChecked(false)
    __script(tooltip, "OnClick")
    assert_false(BeastXPDB.showTooltip, "tooltip box did not turn it off")
    __script(BeastXPBar, "OnEnter")
    assert_false(GameTooltip:IsShown(), "tooltip shown after the box turned it off")

    __control("Width", "MinimalSliderWithSteppersTemplate"):SetValue(320)
    assert_eq(BeastXPDB.width, 320)
    assert_eq(BeastXPBar:GetWidth(), 320)
    __control("Height", "MinimalSliderWithSteppersTemplate"):SetValue(24)
    assert_eq(BeastXPBar:GetHeight(), 24)
    assert_eq(BeastXPBar:GetWidth(), 320, "height slider changed the width")

    __dropdown_pick(__control("Texture", "WowStyle1DropdownTemplate"), "Solid")
    assert_eq(BeastXPBar.status.__barTexture, "Interface\\Buttons\\WHITE8X8")

    __dropdown_pick(__control("Color", "WowStyle1DropdownTemplate"), "Reputation green")
    assert_color(BeastXPBar.status, 0.0, 0.6, 0.1, "preset from the page")
    assert_eq(__control("Color", "ColorSwatchTemplate").__swatch[2], 0.6, "swatch not updated")
    __script(__control("Color", "ColorSwatchTemplate"), "OnClick")
    assert_true(__picker, "swatch did not open the picker")
    __picker_drag(1, 1, 0)
    assert_eq(__dropdown_text(__control("Color", "WowStyle1DropdownTemplate")), "Custom...")

    __dropdown_pick(__control("Text", "WowStyle1DropdownTemplate"), "60%")
    assert_eq(BeastXPBar.text:GetText(), "15%")

    __dropdown_pick(__control("Font", "WowStyle1DropdownTemplate"), "Arial Narrow")
    __control("Font size", "MinimalSliderWithSteppersTemplate"):SetValue(16)
    __dropdown_pick(__control("Outline", "WowStyle1DropdownTemplate"), "Thick outline")
    local path, size, flags = BeastXPBar.text:GetFont()
    assert_eq(path, "Fonts\\ARIALN.TTF")
    assert_eq(size, 16)
    assert_eq(flags, "THICKOUTLINE")
end)

test("a change made elsewhere shows on the open page, without calling back", function()
    local ns = __boot({ pet = hunterPet() })
    open_page()
    local notified = 0
    local original = ns.OnSettingsChanged
    ns.OnSettingsChanged = function() notified = notified + 1; original() end

    SlashCmdList.BEASTXP("size 18")
    assert_eq(__control("Font size", "MinimalSliderWithSteppersTemplate"):GetValue(), 18)
    assert_eq(notified, 1, "refreshing the page changed a setting again")

    SlashCmdList.BEASTXP("texture solid")
    assert_eq(__dropdown_text(__control("Texture", "WowStyle1DropdownTemplate")), "Solid")

    SlashCmdList.BEASTXP("tooltip off")
    assert_false(__control("Show tooltip", "UICheckButtonTemplate"):GetChecked(), "tooltip box still ticked")
    assert_eq(BeastXPDB.showTooltip, false, "the box's refresh turned the tooltip back on")

    -- Dragging the bar's corner moves the sliders too.
    __script(BeastXPBar.grip, "OnMouseDown", "LeftButton")
    BeastXPBar:SetSize(410, 30)
    __script(BeastXPBar.grip, "OnMouseUp", "LeftButton")
    assert_eq(__control("Width", "MinimalSliderWithSteppersTemplate"):GetValue(), 410)
    assert_eq(__control("Height", "MinimalSliderWithSteppersTemplate"):GetValue(), 30)
end)

test("the preview copies the bar, with a sample pet when none is out", function()
    __boot({ db = { texturePath = "Interface\\Buttons\\WHITE8X8", width = 500, height = 40 } })
    open_page()
    local preview = __control("Preview", nil, "Frame")
    assert_eq(preview.text:GetText(), "Level 14   1290 / 2150  (60%)")
    assert_eq(preview.status:GetValue(), 1290)
    assert_eq(preview.status.__barTexture, "Interface\\Buttons\\WHITE8X8")
    assert_eq(preview:GetWidth(), 300, "preview not capped to its row")
    assert_eq(preview:GetHeight(), 30, "preview not capped to its row")

    SlashCmdList.BEASTXP("color ff0000")
    assert_color(preview.status, 1, 0, 0, "preview colour")
    SlashCmdList.BEASTXP("text percent")
    assert_eq(preview.text:GetText(), "60%")

    __boot({ pet = hunterPet() })
    open_page()
    assert_eq(__control("Preview", nil, "Frame").text:GetText(), "Level 14   340 / 2150  (15%)", "real pet not shown")
end)

test("Defaults takes two clicks and leaves the bar where it is", function()
    __boot({
        pet = hunterPet(),
        db = { point = "TOP", relativePoint = "TOP", x = 10, y = -50, width = 400, fontSize = 20,
            textStyle = "percent", barColor = { 1, 0, 0 }, locked = true, showTooltip = false },
    })
    open_page()
    local defaults = __page_button("Defaults")
    __script(defaults, "OnClick")
    assert_eq(defaults:GetText(), "Click again")
    assert_eq(BeastXPDB.fontSize, 20, "reset on the first click")

    -- Leaving the page puts the question away.
    __settings_page():Hide()
    assert_eq(defaults:GetText(), "Defaults")
    open_page()
    __script(defaults, "OnClick")
    assert_eq(BeastXPDB.fontSize, 20, "a click after leaving the page reset at once")

    __script(defaults, "OnClick")
    assert_eq(defaults:GetText(), "Defaults")
    assert_eq(BeastXPDB.fontSize, 11)
    assert_eq(BeastXPDB.width, 240)
    assert_eq(BeastXPDB.textStyle, "full")
    assert_eq(BeastXPDB.locked, false)
    assert_eq(BeastXPDB.showTooltip, true)
    assert_color(BeastXPBar.status, 0.58, 0.0, 0.55, "colour")
    assert_eq(BeastXPDB.point, "TOP", "Defaults moved the bar")
    assert_eq(BeastXPDB.y, -50)
end)

test("the page's Reset position puts the bar back", function()
    __boot({ pet = hunterPet(), db = { point = "TOP", relativePoint = "TOP", x = 10, y = -50, width = 400 } })
    open_page()
    __script(__page_button("Reset position"), "OnClick")
    assert_eq(BeastXPDB.point, nil)
    assert_eq(BeastXPBar:GetWidth(), 240)
    assert_eq(__control("Width", "MinimalSliderWithSteppersTemplate"):GetValue(), 240)
end)

test("without the client's settings window, /petxp says so", function()
    __boot({ pet = hunterPet(), noSettings = true })
    SlashCmdList.BEASTXP("")
    assert_true(__printed("settings page is not available"), "no explanation")
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

test("slash commands change the same settings", function()
    __boot({ pet = hunterPet() })
    SlashCmdList.BEASTXP("size 14")
    assert_eq(BeastXPDB.fontSize, 14)
    SlashCmdList.BEASTXP("size 99")
    assert_eq(BeastXPDB.fontSize, 32, "size not capped")
    SlashCmdList.BEASTXP("size big")
    assert_eq(BeastXPDB.fontSize, 32)
    assert_true(__printed("give a size from 6 to 32"), "no usage for a bad size")

    SlashCmdList.BEASTXP("font arial")
    assert_eq(BeastXPDB.fontPath, "Fonts\\ARIALN.TTF")
    SlashCmdList.BEASTXP("font comic")
    assert_eq(BeastXPDB.fontPath, "Fonts\\ARIALN.TTF")
    assert_true(__printed("no font by that name"), "no message for a bad font")
    SlashCmdList.BEASTXP("font nimrod")
    assert_eq(BeastXPDB.fontPath, "Fonts\\NIM_____.ttf", "LibSharedMedia font not found by name")

    SlashCmdList.BEASTXP("texture solid")
    assert_eq(BeastXPDB.texturePath, "Interface\\Buttons\\WHITE8X8")
    SlashCmdList.BEASTXP("texture skills")
    assert_eq(BeastXPDB.texturePath, "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
    SlashCmdList.BEASTXP("texture blizzard")
    assert_eq(BeastXPDB.texturePath, "Interface\\TargetingFrame\\UI-StatusBar", "exact name did not win")
    SlashCmdList.BEASTXP("texture plaid")
    assert_true(__printed("no texture by that name"), "no message for a bad texture")

    SlashCmdList.BEASTXP("outline thick")
    assert_eq(BeastXPDB.outline, "THICKOUTLINE")
    SlashCmdList.BEASTXP("outline none")
    assert_eq(BeastXPDB.outline, "")
    SlashCmdList.BEASTXP("outline glow")
    assert_true(__printed("use none, outline or thick"), "no usage for a bad outline")

    SlashCmdList.BEASTXP("  LOCK  ")
    assert_true(BeastXPDB.locked, "mixed case lock ignored")

    SlashCmdList.BEASTXP("help")
    assert_true(__printed("/petxp unlock"), "no help")
    assert_true(__printed("open the settings page"), "help does not mention the settings page")
end)

test("the slash command answers to /beastxp and /petxp", function()
    __boot({ pet = hunterPet() })
    assert_eq(SLASH_BEASTXP1, "/beastxp")
    assert_eq(SLASH_BEASTXP2, "/petxp")
    assert_eq(type(SlashCmdList.BEASTXP), "function")
end)

test("broken saved settings fall back to the defaults", function()
    __boot({
        pet = hunterPet(),
        db = { point = 5, x = "a", width = "wide", fontSize = 500, outline = "GLOW", locked = "yes", fontPath = 7,
            texturePath = false, showTooltip = "no" },
    })
    assert_eq(BeastXPDB.showTooltip, true)
    assert_eq(BeastXPDB.texturePath, "Interface\\TargetingFrame\\UI-StatusBar")
    assert_eq(BeastXPDB.point, nil)
    assert_eq(BeastXPDB.width, 240)
    assert_eq(BeastXPDB.fontSize, 32)
    assert_eq(BeastXPDB.outline, "")
    assert_eq(BeastXPDB.locked, false)
    assert_eq(BeastXPDB.fontPath, "Fonts\\FRIZQT__.TTF")
    local point, _, _, x, y = BeastXPBar:GetPoint()
    assert_eq(point, "CENTER")
    assert_eq(y, -180)
end)

test("a saved point without a relative point anchors to the same point", function()
    __boot({ pet = hunterPet(), db = { point = "TOP", x = 0, y = -100 } })
    local point, _, relativePoint = BeastXPBar:GetPoint()
    assert_eq(point, "TOP")
    assert_eq(relativePoint, "TOP")
end)

test("a slash command before login does nothing", function()
    __boot({ login = false })
    SlashCmdList.BEASTXP("lock")
    assert_eq(BeastXPDB, nil)
end)

test("a non-hunter is told why there is no bar", function()
    __boot({ class = "WARRIOR" })
    SlashCmdList.BEASTXP("unlock")
    assert_true(__printed("only hunter pets earn experience"), "no explanation")
    assert_eq(BeastXPBar, nil)
end)

--------------------------------------------------------------------------------
-- Safety
--------------------------------------------------------------------------------

test("secret values from the game never raise an error", function()
    __boot({ pet = { current = __secret(), max = __secret(), level = __secret(), name = __secret() } })
    assert_eq(BeastXPBar.text:GetText(), "Pet")
    __script(BeastXPBar, "OnEnter")
    assert_true(has_line(GameTooltip.__lines, "Your pet"), "secret name shown")
    __fire("UNIT_PET", __secret())
    __fire("UNIT_LEVEL", __secret())

    __boot({ class = __secret(), pet = hunterPet() })
    assert_eq(BeastXPBar, nil, "a secret class was read as a hunter")
end)

test("a pet event the client does not have does not stop the others", function()
    __boot({ pet = hunterPet(), missingEvents = { "UNIT_PET_EXPERIENCE" } })
    assert_true(BeastXPBar:IsShown(), "bar not shown")
    assert_true(__registered("UNIT_PET"), "UNIT_PET not registered")
    assert_true(__registered("PLAYER_XP_UPDATE"), "PLAYER_XP_UPDATE not registered")
    __pet.current = 500
    __fire("PLAYER_XP_UPDATE")
    assert_eq(BeastXPBar.text:GetText(), "Level 14   500 / 2150  (23%)")
end)

test("a client without the pet experience API stays off", function()
    local saved = GetPetExperience
    GetPetExperience = nil
    local ok, err = pcall(__boot, { pet = hunterPet() })
    GetPetExperience = saved
    assert_true(ok, tostring(err))
    assert_eq(BeastXPBar, nil)
    assert_true(__printed("reports no pet experience"), "no explanation")
end)

test("the gate leaves the addon inert on another client", function()
    local saved = { locked = true, fontSize = 99 }
    local ns = __boot({ interface = 11507, db = saved, pet = hunterPet() })
    assert_eq(ns.Allowed, false)
    assert_eq(BeastXPDB, saved, "saved table replaced")
    assert_eq(saved.fontSize, 99, "saved settings rewritten")
    assert_eq(BeastXPBar, nil)
    assert_eq(SlashCmdList.BEASTXP, nil, "slash command registered")
    assert_eq(__frame_count(), 2, "frames created beyond UIParent and GameTooltip")
    assert_true(__printed("disabled on this client"), "no message")
end)

test("the gate fails open when the interface cannot be read", function()
    local ns = __boot({ interface = "unknown", pet = hunterPet() })
    assert_eq(ns.Allowed, true)
    assert_true(BeastXPBar and BeastXPBar:IsShown(), "bar not shown")
end)

--------------------------------------------------------------------------------

__print(("\n%d passed, %d failed"):format(passed, failed))
__exit_code = failed == 0 and 0 or 1
