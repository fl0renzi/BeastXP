-- BeastXP - BeastXP.lua
-- One borderless bar for the hunter pet's experience, in the purple the game
-- draws experience in. Drag the bar to move it, drag the grip in its corner
-- to resize it, and right-click it for the lock, the texture, the font, the
-- font size and the outline. Textures and fonts come from LibSharedMedia as
-- well as the client. /beastxp, or /petxp for short, offers the same options
-- as slash commands.
--
-- Cost: the bar is built the first time there is something to show, and it is
-- refreshed from the pet events only, never from OnUpdate. A character that is
-- not a hunter unregisters everything at login and pays nothing after that.

local addonName, ns = ...

--------------------------------------------------------------------------------
-- Client gate
--------------------------------------------------------------------------------
-- BeastXP targets World of Warcraft: Forever, whose toc is 16001. On any other
-- client it stays inert and never reads or writes BeastXPDB, so the saved
-- settings round-trip untouched. It fails open when the interface number
-- cannot be read, so a healthy client is never blocked.

local FOREVER_INTERFACE = 16001

local iface = select(4, GetBuildInfo())
if type(iface) == "number" and iface ~= FOREVER_INTERFACE then
    ns.Allowed = false
    print(("BeastXP targets WoW Forever (interface %d) and is disabled on this client (interface %d).")
        :format(FOREVER_INTERFACE, iface))
    return
end
ns.Allowed = true

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local DEFAULT_WIDTH  = 240
local DEFAULT_HEIGHT = 18
local MIN_WIDTH      = 80
local MIN_HEIGHT     = 6
local MAX_HEIGHT     = 64

-- A resize may never make the bar wider than the screen. SetClampedToScreen
-- only stops it being dragged off an edge; it does not limit a resize.
local SCREEN_MARGIN = 40

-- Where a bar that has never been moved sits: centred, below the character.
local DEFAULT_POINT, DEFAULT_X, DEFAULT_Y = "CENTER", 0, -180

-- No border: a dark backing one pixel wider than the bar on every side, which
-- is enough edge to read against any background.
local BAR_INSET = 1
local BACKING_COLOR = { 0, 0, 0, 0.6 }

local GRIP_TEXTURE = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber"

-- The purple the classic client draws experience in, on the main bar and on
-- the pet tab's bar alike. The default bar colour.
local XP_COLOR = { 0.58, 0.0, 0.55 }

-- Ready-made bar colours, all from the classic client. The key is the slash
-- command word. Any other colour comes from the colour picker or a hex code.
local COLOR_PRESETS = {
    { key = "purple", name = "Experience purple", color = XP_COLOR },
    { key = "blue",   name = "Rested blue",       color = { 0.0, 0.39, 0.88 } },
    { key = "green",  name = "Reputation green",  color = { 0.0, 0.6, 0.1 } },
}

-- The empty part of the bar is the bar colour at this opacity.
local TRACK_ALPHA = 0.25

-- The colours the game's own tooltips use for a label and for a hint line.
local LABEL_COLOR = { 1.0, 0.82, 0.0 }
local HINT_COLOR  = { 0.5, 0.5, 0.5 }

-- The media every client ships. LibSharedMedia (embedded under Libs) adds
-- whatever other addons register with it. A choice is saved by its path, not
-- by its LibSharedMedia name, so it keeps working whichever addon registered
-- it and whenever it did.
local BUILTIN_FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { name = "Skurri",        path = "Fonts\\SKURRI.TTF" },
    { name = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
}

local BUILTIN_TEXTURES = {
    { name = "Blizzard",                      path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { name = "Blizzard Character Skills Bar", path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
    { name = "Solid",                         path = "Interface\\Buttons\\WHITE8X8" },
}

local FONT_SIZES = { 8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 22, 24 }
local MIN_FONT_SIZE, MAX_FONT_SIZE = 6, 32

-- The flag is what SetFont takes and what is saved; the key is the slash
-- command word.
local OUTLINES = {
    { key = "none",    name = "None",          flag = "" },
    { key = "outline", name = "Outline",       flag = "OUTLINE" },
    { key = "thick",   name = "Thick outline", flag = "THICKOUTLINE" },
}

-- How much the bar says. The key is what is saved and the slash command word;
-- the name is an example, so the menu explains itself. The examples are the
-- settings page's sample pet (ns.API.PreviewPet).
local TEXT_STYLES = {
    { key = "full",    name = "Level 14   1290 / 2150  (60%)" },
    { key = "short",   name = "14  1290/2150  60%" },
    { key = "level",   name = "14  60%" },
    { key = "percent", name = "60%" },
    { key = "none",    name = "No text" },
}

local DEFAULTS = {
    width       = DEFAULT_WIDTH,
    height      = DEFAULT_HEIGHT,
    locked      = false,
    showTooltip = true,
    texturePath = "Interface\\TargetingFrame\\UI-StatusBar",
    fontPath    = "Fonts\\FRIZQT__.TTF",
    fontSize    = 11,
    outline     = "",
    textStyle   = "full",
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local db            -- BeastXPDB, set at PLAYER_LOGIN
local bar           -- built on first use
local active = false -- a hunter, on a client that reports pet experience
local isHunter = false
local moving = false -- a drag or a resize is in progress

-- The pet as last read. One table, refilled in place, so a refresh allocates
-- nothing.
local pet = { present = false, current = 0, max = 0, level = nil }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Secret values (the patch 12.0 security model) raise a Lua error on any
-- comparison, boolean test, length or arithmetic. Everything read from the
-- game passes through here first; a secret becomes nil, read as "unknown".
local issecretvalue = issecretvalue
local function SafeValue(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function Print(text)
    print("|cffffd200BeastXP:|r " .. text)
end

local function Clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function Round(value)
    return math.floor(value + 0.5)
end

local function SamePath(a, b)
    return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

local function MaxWidth()
    local screen = UIParent:GetWidth() or DEFAULT_WIDTH
    return math.max(MIN_WIDTH, screen - SCREEN_MARGIN)
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------
-- Account-wide: the Forever client writes a per-character SavedVariables file
-- but never loads it back. Everything applies live, since the beta client does
-- not reliably keep a write across a reload either.

local function InitDB()
    if type(BeastXPDB) ~= "table" then BeastXPDB = {} end
    db = BeastXPDB

    for key, value in pairs(DEFAULTS) do
        if type(db[key]) ~= type(value) then db[key] = value end
    end

    db.fontSize = Clamp(Round(db.fontSize), MIN_FONT_SIZE, MAX_FONT_SIZE)

    local outlineKnown = false
    for _, outline in ipairs(OUTLINES) do
        if db.outline == outline.flag then outlineKnown = true end
    end
    if not outlineKnown then db.outline = DEFAULTS.outline end

    local styleKnown = false
    for _, style in ipairs(TEXT_STYLES) do
        if db.textStyle == style.key then styleKnown = true end
    end
    if not styleKnown then db.textStyle = DEFAULTS.textStyle end

    -- The bar colour is three numbers from 0 to 1. Anything else goes back to
    -- the experience purple, as a fresh table: a colour change writes into
    -- the saved table, and must never write into XP_COLOR.
    local color = db.barColor
    local colorValid = type(color) == "table"
    if colorValid then
        for i = 1, 3 do
            local channel = color[i]
            if type(channel) ~= "number" or channel ~= channel or channel < 0 or channel > 1 then
                colorValid = false
            end
        end
    end
    if not colorValid then
        db.barColor = { XP_COLOR[1], XP_COLOR[2], XP_COLOR[3] }
    end

    -- A position is saved once the bar has been moved. A broken one is dropped
    -- so the bar falls back to its default spot.
    if type(db.point) ~= "string" or type(db.x) ~= "number" or type(db.y) ~= "number" then
        db.point, db.relativePoint, db.x, db.y = nil, nil, nil, nil
    elseif type(db.relativePoint) ~= "string" then
        db.relativePoint = db.point
    end
end

--------------------------------------------------------------------------------
-- Reading the pet
--------------------------------------------------------------------------------

-- Fills `pet` from the game. Only a hunter pet earns experience, which is the
-- same test the character frame uses before it shows the pet's bar.
local function ReadPet()
    local hasUI, isHunterPet = HasPetUI()
    hasUI, isHunterPet = SafeValue(hasUI), SafeValue(isHunterPet)
    pet.present = (hasUI and isHunterPet) and true or false
    if not pet.present then
        pet.current, pet.max, pet.level = 0, 0, nil
        return
    end

    local current, max = GetPetExperience()
    current, max = SafeValue(current), SafeValue(max)
    pet.current = type(current) == "number" and math.floor(current) or 0
    pet.max = type(max) == "number" and math.floor(max) or 0

    local level = SafeValue(UnitLevel("pet"))
    pet.level = (type(level) == "number" and level > 0) and math.floor(level) or nil
end

-- A number for the short style: 12345 becomes 12.3k.
local function ShortNumber(value)
    if value >= 10000 then return ("%.1fk"):format(value / 1000) end
    return ("%d"):format(value)
end

-- A pet's text in the given style (see TEXT_STYLES). Any part the game did not
-- report, the level or the experience, is left out rather than shown as 0.
-- The settings preview formats its sample pet through here too.
local function FormatText(style, present, level, current, max)
    if style == "none" then return "" end
    if not present then return "No pet" end

    local percent = max > 0 and math.floor(current / max * 100) or nil

    if style == "percent" then
        return percent and ("%d%%"):format(percent) or ""
    elseif style == "level" then
        if level and percent then return ("%d  %d%%"):format(level, percent) end
        return (level and ("%d"):format(level)) or (percent and ("%d%%"):format(percent)) or ""
    elseif style == "short" then
        local values = percent and ("%s/%s  %d%%"):format(ShortNumber(current), ShortNumber(max), percent)
        if level and values then return ("%d  %s"):format(level, values) end
        return values or (level and ("%d"):format(level)) or ""
    end

    local text = level and ("Level %d"):format(level) or "Pet"
    if percent then
        text = ("%s   %d / %d  (%d%%)"):format(text, current, max, percent)
    end
    return text
end

local function BarText()
    return FormatText(db.textStyle, pet.present, pet.level, pet.current, pet.max)
end

-- With Show tooltip off, hovering the bar or its grip shows nothing.
local function ShowTooltip(owner)
    if not db.showTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")

    if pet.present then
        GameTooltip:AddLine(SafeValue(UnitName("pet")) or "Your pet", 1, 1, 1)
        if pet.level then
            GameTooltip:AddLine(("Level %d"):format(pet.level), 1, 1, 1)
        end
        if pet.max > 0 then
            GameTooltip:AddDoubleLine("Experience", ("%d / %d"):format(pet.current, pet.max),
                LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], 1, 1, 1)
            GameTooltip:AddDoubleLine("To next level", ("%d"):format(pet.max - pet.current),
                LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], 1, 1, 1)
        end
    else
        GameTooltip:AddLine("Pet experience", 1, 1, 1)
        GameTooltip:AddLine("No hunter pet is out.", unpack(LABEL_COLOR))
    end

    GameTooltip:AddLine(" ")
    if db.locked then
        GameTooltip:AddLine("Locked. Right-click to unlock.", unpack(HINT_COLOR))
    else
        GameTooltip:AddLine("Drag to move, drag the corner to resize.", unpack(HINT_COLOR))
        GameTooltip:AddLine("Right-click for font and lock options.", unpack(HINT_COLOR))
    end
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------

local ShowMenu -- defined with the menu, below

-- Tells the settings page (BeastXP_Options.lua) that a setting changed, from
-- wherever it was changed: the page, the right-click menu, a slash command or
-- a drag. The page only redraws while it is open.
local function NotifyChanged()
    if ns.OnSettingsChanged then ns.OnSettingsChanged() end
end

local function SaveLayout()
    local point, _, relativePoint, x, y = bar:GetPoint()
    if point then
        db.point, db.relativePoint, db.x, db.y = point, relativePoint or point, x, y
    end
    db.width, db.height = Round(bar:GetWidth()), Round(bar:GetHeight())
    NotifyChanged()
end

-- Puts the bar where the settings say, at the size they say, inside bounds
-- taken from the current screen.
local function ApplyLayout()
    local maxWidth = MaxWidth()
    bar:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, maxWidth, MAX_HEIGHT)

    bar:ClearAllPoints()
    if db.point then
        bar:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
    else
        bar:SetPoint(DEFAULT_POINT, UIParent, DEFAULT_POINT, DEFAULT_X, DEFAULT_Y)
    end
    bar:SetSize(Clamp(db.width, MIN_WIDTH, maxWidth), Clamp(db.height, MIN_HEIGHT, MAX_HEIGHT))
end

-- The look of the bar: a dark backing, the status bar one pixel inside it,
-- the dim track behind the fill, and the text. Built on the real bar and on
-- the settings page's preview, so the two cannot drift apart. The Apply
-- functions below take either.
local function BuildBarVisuals(frame)
    local backing = frame:CreateTexture(nil, "BACKGROUND")
    backing:SetAllPoints(frame)
    backing:SetColorTexture(unpack(BACKING_COLOR))

    local status = CreateFrame("StatusBar", nil, frame)
    status:SetPoint("TOPLEFT", BAR_INSET, -BAR_INSET)
    status:SetPoint("BOTTOMRIGHT", -BAR_INSET, BAR_INSET)
    status:SetMinMaxValues(0, 1)
    status:SetValue(0)
    frame.status = status

    -- The empty part of the bar: a dim wash of the same texture and colour,
    -- so the bar reads at its full length even with no experience in it.
    local track = status:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(status)
    frame.track = track

    -- Anchored on both sides, so a narrow bar truncates the text instead of
    -- spilling it past the ends.
    local text = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", 2, 0)
    text:SetPoint("RIGHT", -2, 0)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)
    frame.text = text
end

-- SetFont returns false when the file cannot be loaded. The chosen font falls
-- back to the default one, and that to the game's own font object, so the
-- string always has a font: SetText errors on a font string without one.
local function ApplyFont(frame)
    local text = frame.text
    if text:SetFont(db.fontPath, db.fontSize, db.outline) == false
        and text:SetFont(DEFAULTS.fontPath, db.fontSize, db.outline) == false then
        text:SetFontObject(GameFontHighlightSmall)
    end
end

-- The bar colour, on the fill and, dimmed, on the track behind it.
local function ApplyColor(frame)
    local r, g, b = db.barColor[1], db.barColor[2], db.barColor[3]
    frame.status:SetStatusBarColor(r, g, b)
    frame.track:SetVertexColor(r, g, b, TRACK_ALPHA)
end

-- The same fallback for the texture, on the fill and on the dim track behind
-- it. The colour goes back on afterwards, since it belongs to the texture.
local function ApplyTexture(frame)
    local status, track = frame.status, frame.track
    if status:SetStatusBarTexture(db.texturePath) == false then
        status:SetStatusBarTexture(DEFAULTS.texturePath)
    end
    if track:SetTexture(db.texturePath) == false then
        track:SetTexture(DEFAULTS.texturePath)
    end
    ApplyColor(frame)
end

local function ApplyLock()
    bar.grip:SetShown(not db.locked)
end

-- Ends a drag or a resize and remembers where the bar ended up. Also runs on
-- hide, since a bar hidden mid-drag would otherwise stay stuck to the cursor.
local function StopMoving()
    if not moving then return end
    moving = false
    bar:StopMovingOrSizing()
    SaveLayout()
end

local function EnsureBar()
    if bar then return bar end

    bar = CreateFrame("Frame", "BeastXPBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:SetResizable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    BuildBarVisuals(bar)

    -- The chat frame's own resize grip, in the bottom-right corner, above the
    -- status bar. Hidden while the bar is locked.
    local grip = CreateFrame("Button", nil, bar)
    grip:SetSize(12, 12)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(bar.status:GetFrameLevel() + 2)
    grip:SetNormalTexture(GRIP_TEXTURE .. "-Up")
    grip:SetHighlightTexture(GRIP_TEXTURE .. "-Highlight")
    grip:SetPushedTexture(GRIP_TEXTURE .. "-Down")
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or db.locked then return end
        moving = true
        bar:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", StopMoving)
    grip:SetScript("OnEnter", function(self)
        if not db.showTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Drag to resize", 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.grip = grip

    bar:SetScript("OnDragStart", function(self)
        if db.locked then return end
        moving = true
        self:StartMoving()
    end)
    bar:SetScript("OnDragStop", StopMoving)
    bar:SetScript("OnHide", StopMoving)
    bar:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ShowMenu(self) end
    end)
    bar:SetScript("OnEnter", ShowTooltip)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ApplyLayout()
    ApplyTexture(bar)
    ApplyFont(bar)
    ApplyLock()
    return bar
end

-- The one place the bar is updated. It shows while a hunter pet is out, and
-- also while the bar is unlocked, so it can be placed before there is a pet.
local function Refresh()
    if not active then return end
    ReadPet()

    if not pet.present and db.locked then
        if bar then bar:Hide() end
        return
    end

    local frame = EnsureBar()
    if pet.present and pet.max > 0 then
        frame.status:SetMinMaxValues(0, pet.max)
        frame.status:SetValue(math.min(pet.current, pet.max))
    else
        frame.status:SetMinMaxValues(0, 1)
        frame.status:SetValue(0)
    end
    frame.text:SetText(BarText())
    frame:Show()

    if GameTooltip:IsShown() and GameTooltip:GetOwner() == frame then
        ShowTooltip(frame)
    end
end

--------------------------------------------------------------------------------
-- Changing settings
--------------------------------------------------------------------------------

-- Every setter changes the saved value, applies it to the bar if the bar has
-- been built, and tells the settings page.

local function SetLocked(locked)
    db.locked = locked and true or false
    if bar then ApplyLock() end
    Refresh()
    NotifyChanged()
end

-- Turning the tooltip off also puts away one that is up, say when the command
-- is typed with the mouse over the bar.
local function SetShowTooltip(show)
    db.showTooltip = show and true or false
    if not db.showTooltip and bar and GameTooltip:IsShown() then
        local owner = GameTooltip:GetOwner()
        if owner == bar or owner == bar.grip then GameTooltip:Hide() end
    end
    NotifyChanged()
end

local function SetTexturePath(path)
    db.texturePath = path
    if bar then ApplyTexture(bar) end
    NotifyChanged()
end

-- Writes into the saved table rather than replacing it, so the picker's live
-- preview allocates nothing while it is dragged.
local function SetBarColor(r, g, b)
    local color = db.barColor
    color[1], color[2], color[3] = Clamp(r, 0, 1), Clamp(g, 0, 1), Clamp(b, 0, 1)
    if bar then ApplyColor(bar) end
    NotifyChanged()
end

local function SameColor(color, other)
    return math.abs(color[1] - other[1]) < 0.005
        and math.abs(color[2] - other[2]) < 0.005
        and math.abs(color[3] - other[3]) < 0.005
end

-- The client's own colour picker, previewing on the bar as it is dragged.
-- Cancel puts back the colour the bar had when the picker opened.
local function OpenColorPicker()
    if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
        Print("the color picker is not available on this client; give a hex code instead, for example /petxp color 33aaff.")
        return
    end

    local oldR, oldG, oldB = db.barColor[1], db.barColor[2], db.barColor[3]
    ColorPickerFrame:SetupColorPickerAndShow({
        r = oldR, g = oldG, b = oldB,
        hasOpacity = false,
        swatchFunc = function() SetBarColor(ColorPickerFrame:GetColorRGB()) end,
        cancelFunc = function() SetBarColor(oldR, oldG, oldB) end,
    })
end

local function SetFontPath(path)
    db.fontPath = path
    if bar then ApplyFont(bar) end
    NotifyChanged()
end

local function SetFontSize(size)
    db.fontSize = Clamp(Round(size), MIN_FONT_SIZE, MAX_FONT_SIZE)
    if bar then ApplyFont(bar) end
    NotifyChanged()
end

local function SetOutline(flag)
    db.outline = flag
    if bar then ApplyFont(bar) end
    NotifyChanged()
end

local function SetTextStyle(key)
    db.textStyle = key
    Refresh()
    NotifyChanged()
end

-- The size from the settings page's sliders. The bar keeps its place.
local function SetBarSize(width, height)
    db.width = Clamp(Round(width), MIN_WIDTH, MaxWidth())
    db.height = Clamp(Round(height), MIN_HEIGHT, MAX_HEIGHT)
    if bar then bar:SetSize(db.width, db.height) end
    NotifyChanged()
end

local function ResetLayout()
    db.point, db.relativePoint, db.x, db.y = nil, nil, nil, nil
    db.width, db.height = DEFAULTS.width, DEFAULTS.height
    if bar then ApplyLayout() end
    NotifyChanged()
end

-- The settings page's Defaults: every setting back to how a fresh install has
-- it, except where the bar sits, which only Reset position touches.
local function ResetDefaults()
    for key, value in pairs(DEFAULTS) do db[key] = value end
    db.barColor = { XP_COLOR[1], XP_COLOR[2], XP_COLOR[3] }
    if bar then
        ApplyLayout()
        ApplyTexture(bar)
        ApplyFont(bar)
        ApplyLock()
    end
    Refresh()
    NotifyChanged()
end

--------------------------------------------------------------------------------
-- Right-click menu
--------------------------------------------------------------------------------

-- Every choice of one kind of media ("font" or "statusbar"): the built-in
-- ones first, then whatever LibSharedMedia knows that is not one of them by
-- file or by name (it has its own Morpheus, in another file). Built when the
-- menu opens or a slash command asks, so media another addon registers late
-- is still there, and the list costs nothing until it is wanted.
local function MediaChoices(mediaType, builtins)
    local choices, seenPath, seenName = {}, {}, {}
    for _, entry in ipairs(builtins) do
        choices[#choices + 1] = entry
        seenPath[entry.path:lower()] = true
        seenName[entry.name:lower()] = true
    end

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local names = LSM and LSM:List(mediaType)
    local paths = LSM and LSM:HashTable(mediaType)
    if names and paths then
        for _, name in ipairs(names) do
            local path = paths[name]
            if type(path) == "string" and path ~= ""
                and not seenPath[path:lower()] and not seenName[name:lower()] then
                choices[#choices + 1] = { name = name, path = path }
                seenPath[path:lower()] = true
                seenName[name:lower()] = true
            end
        end
    end
    return choices
end

local function FontChoices() return MediaChoices("font", BUILTIN_FONTS) end
local function TextureChoices() return MediaChoices("statusbar", BUILTIN_TEXTURES) end

-- A submenu with one radio per choice, checked against the saved path.
local function AddMediaMenu(root, title, choices, key, apply)
    local submenu = root:CreateButton(title)
    for _, entry in ipairs(choices) do
        local path = entry.path
        submenu:CreateRadio(entry.name,
            function() return SamePath(db[key], path) end,
            function() apply(path) end)
    end
    -- A large LibSharedMedia collection would run off the screen.
    if #choices > 20 and submenu.SetScrollMode then
        submenu:SetScrollMode(400)
    end
end

-- The settings page lives in BeastXP_Options.lua, which sets ns.OpenSettings.
local function OpenSettings()
    if not (ns.OpenSettings and ns.OpenSettings()) then
        Print("the settings page is not available on this client; /petxp help lists the commands.")
    end
end

-- The client's own context menu, so it looks like every other menu in the
-- game.
function ShowMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        Print("the right-click menu is not available on this client; type /petxp help for the commands.")
        return
    end

    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("BeastXP")
        root:CreateCheckbox("Lock bar",
            function() return db.locked end,
            function() SetLocked(not db.locked) end)
        root:CreateCheckbox("Show tooltip",
            function() return db.showTooltip end,
            function() SetShowTooltip(not db.showTooltip) end)

        AddMediaMenu(root, "Texture", TextureChoices(), "texturePath", SetTexturePath)

        local colorMenu = root:CreateButton("Bar color")
        for _, preset in ipairs(COLOR_PRESETS) do
            local color = preset.color
            colorMenu:CreateRadio(preset.name,
                function() return SameColor(db.barColor, color) end,
                function() SetBarColor(color[1], color[2], color[3]) end)
        end
        colorMenu:CreateButton("Custom color...", function() OpenColorPicker() end)

        local textMenu = root:CreateButton("Text")
        for _, style in ipairs(TEXT_STYLES) do
            local key = style.key
            textMenu:CreateRadio(style.name,
                function() return db.textStyle == key end,
                function() SetTextStyle(key) end)
        end

        AddMediaMenu(root, "Font", FontChoices(), "fontPath", SetFontPath)

        local sizeMenu = root:CreateButton("Font size")
        for _, size in ipairs(FONT_SIZES) do
            sizeMenu:CreateRadio(tostring(size),
                function() return db.fontSize == size end,
                function() SetFontSize(size) end)
        end

        local outlineMenu = root:CreateButton("Outline")
        for _, outline in ipairs(OUTLINES) do
            local flag = outline.flag
            outlineMenu:CreateRadio(outline.name,
                function() return db.outline == flag end,
                function() SetOutline(flag) end)
        end

        root:CreateDivider()
        root:CreateButton("Reset position and size", function() ResetLayout() end)
        root:CreateButton("Settings...", function() OpenSettings() end)
    end)
end

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

local HELP = {
    "/petxp - open the settings page (also under Options, AddOns)",
    "/petxp lock - lock the bar (it hides while no pet is out)",
    "/petxp unlock - unlock it to move and resize it",
    "/petxp tooltip on | off - the tooltip when you hover over the bar",
    "/petxp texture <name> - for example blizzard, solid or a LibSharedMedia texture",
    "/petxp color - pick the bar color, or give purple | blue | green | a hex code like 33aaff",
    "/petxp text full | short | level | percent | none - how much the bar says",
    "/petxp font <name> - for example friz, arial or a LibSharedMedia font",
    "/petxp size " .. MIN_FONT_SIZE .. "-" .. MAX_FONT_SIZE .. " - font size",
    "/petxp outline none | outline | thick",
    "/petxp reset - put the bar back where it started",
    "Right-click the bar for the same options.",
}

-- Commands that only show something, so they need no hunter to make sense.
local SHOW_COMMANDS = { [""] = true, help = true, options = true, config = true, settings = true }

-- The choice a typed name means: an exact name first, then the first name
-- that contains the word, so "skills" finds "Blizzard Character Skills Bar".
-- word is already lowercase.
local function FindMedia(choices, word)
    if word == "" then return nil end
    for _, entry in ipairs(choices) do
        if entry.name:lower() == word then return entry end
    end
    for _, entry in ipairs(choices) do
        if entry.name:lower():find(word, 1, true) then return entry end
    end
end

local function FindOutline(word)
    for _, outline in ipairs(OUTLINES) do
        if outline.key == word then return outline end
    end
end

local function FindTextStyle(word)
    for _, style in ipairs(TEXT_STYLES) do
        if style.key == word then return style end
    end
end

local function FindColorPreset(word)
    for _, preset in ipairs(COLOR_PRESETS) do
        if preset.key == word then return preset end
    end
end

-- "33aaff" or "#33aaff" as three channels from 0 to 1, or nil.
local function ParseHex(word)
    local r, g, b = word:match("^#?(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

SLASH_BEASTXP1 = "/beastxp"
SLASH_BEASTXP2 = "/petxp"
SlashCmdList["BEASTXP"] = function(msg)
    if not db then return end -- before PLAYER_LOGIN

    local command, word = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")

    if not SHOW_COMMANDS[command] and not active then
        Print(isHunter and "this client reports no pet experience, so there is no bar to show."
            or "only hunter pets earn experience, so there is no bar on this character.")
    end

    if command == "" or command == "options" or command == "config" or command == "settings" then
        OpenSettings()
    elseif command == "lock" or command == "unlock" then
        SetLocked(command == "lock")
        Print(db.locked and "bar locked." or "bar unlocked: drag it to move it, drag its corner to resize it.")
    elseif command == "tooltip" then
        if word == "on" or word == "off" then
            SetShowTooltip(word == "on")
            Print(db.showTooltip and "tooltip on: hover over the bar for your pet's details."
                or "tooltip off: hovering over the bar shows nothing.")
        else
            Print("use /petxp tooltip on or /petxp tooltip off.")
        end
    elseif command == "texture" then
        local texture = FindMedia(TextureChoices(), word)
        if texture then
            SetTexturePath(texture.path)
            Print("texture set to " .. texture.name .. ".")
        else
            Print("no texture by that name; right-click the bar to see every texture.")
        end
    elseif command == "color" or command == "colour" then
        local preset = FindColorPreset(word)
        local r, g, b = ParseHex(word)
        if word == "" then
            OpenColorPicker()
        elseif word == "reset" then
            SetBarColor(XP_COLOR[1], XP_COLOR[2], XP_COLOR[3])
            Print("bar color reset.")
        elseif preset then
            SetBarColor(preset.color[1], preset.color[2], preset.color[3])
            Print("bar color set to " .. preset.name:lower() .. ".")
        elseif r then
            SetBarColor(r, g, b)
            Print("bar color set to " .. word .. ".")
        else
            Print("use purple, blue, green or a hex code like 33aaff; /petxp color on its own opens the color picker.")
        end
    elseif command == "text" then
        local style = FindTextStyle(word)
        if style then
            SetTextStyle(style.key)
            Print("text set to " .. style.key .. ".")
        else
            Print("use full, short, level, percent or none.")
        end
    elseif command == "font" then
        local font = FindMedia(FontChoices(), word)
        if font then
            SetFontPath(font.path)
            Print("font set to " .. font.name .. ".")
        else
            Print("no font by that name; right-click the bar to see every font.")
        end
    elseif command == "size" then
        local size = tonumber(word:match("^%d+$") or "")
        if size then
            SetFontSize(size)
            Print(("font size set to %d."):format(db.fontSize))
        else
            Print(("give a size from %d to %d, for example /petxp size 12."):format(MIN_FONT_SIZE, MAX_FONT_SIZE))
        end
    elseif command == "outline" then
        local outline = FindOutline(word)
        if outline then
            SetOutline(outline.flag)
            Print("outline set to " .. outline.name:lower() .. ".")
        else
            Print("use none, outline or thick.")
        end
    elseif command == "reset" then
        ResetLayout()
        Print("bar position and size reset.")
    else
        Print("a bar for your hunter pet's experience.")
        for _, line in ipairs(HELP) do print("  " .. line) end
    end
end

--------------------------------------------------------------------------------
-- For the settings page
--------------------------------------------------------------------------------
-- BeastXP_Options.lua builds its page from these, so the page, the right-click
-- menu and the slash commands all change a setting through the same setter.

ns.API = {
    GetDB = function() return db end,
    Print = Print,

    BuildBarVisuals = BuildBarVisuals,
    ApplyTexture = ApplyTexture,
    ApplyFont = ApplyFont,
    FormatText = FormatText,
    -- The preview shows the real pet when one is out and reports its
    -- experience, and the sample pet of the Text menu's examples otherwise.
    PreviewPet = function()
        if pet.present and pet.max > 0 then return pet.level, pet.current, pet.max end
        return 14, 1290, 2150
    end,

    SetLocked = SetLocked,
    SetShowTooltip = SetShowTooltip,
    SetBarSize = SetBarSize,
    SetTexturePath = SetTexturePath,
    SetBarColor = SetBarColor,
    OpenColorPicker = OpenColorPicker,
    SetTextStyle = SetTextStyle,
    SetFontPath = SetFontPath,
    SetFontSize = SetFontSize,
    SetOutline = SetOutline,
    ResetLayout = ResetLayout,
    ResetDefaults = ResetDefaults,

    TextureChoices = TextureChoices,
    FontChoices = FontChoices,
    SamePath = SamePath,
    SameColor = SameColor,
    COLOR_PRESETS = COLOR_PRESETS,
    TEXT_STYLES = TEXT_STYLES,
    OUTLINES = OUTLINES,

    MIN_WIDTH = MIN_WIDTH,
    MaxWidth = MaxWidth,
    MIN_HEIGHT = MIN_HEIGHT,
    MAX_HEIGHT = MAX_HEIGHT,
    MIN_FONT_SIZE = MIN_FONT_SIZE,
    MAX_FONT_SIZE = MAX_FONT_SIZE,
}

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

-- What can change the bar. UNIT_PET_EXPERIENCE is the real signal;
-- PLAYER_XP_UPDATE backs it up, since a pet's experience comes from the same
-- kills. Each is registered through pcall: registering an event the client
-- does not have raises an error, and one missing event must not stop the rest.
local PET_EVENTS = {
    "UNIT_PET",
    "UNIT_PET_EXPERIENCE",
    "UNIT_LEVEL",
    "PET_UI_UPDATE",
    "PLAYER_XP_UPDATE",
    "PLAYER_ENTERING_WORLD",
}

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        InitDB()

        -- The settings page, for every character: the settings are account
        -- wide, so they can be set up from any of them.
        if ns.InstallSettings then ns.InstallSettings() end

        local _, classFile = UnitClass("player")
        isHunter = SafeValue(classFile) == "HUNTER"
        if not isHunter then return end

        if type(HasPetUI) ~= "function" or type(GetPetExperience) ~= "function" then
            Print("this client reports no pet experience, so the bar stays off.")
            return
        end

        active = true
        for _, name in ipairs(PET_EVENTS) do
            pcall(self.RegisterEvent, self, name)
        end
        Refresh()
        return
    end

    unit = SafeValue(unit)
    if event == "UNIT_PET" and unit ~= "player" then return end
    if event == "UNIT_LEVEL" and unit ~= "pet" then return end
    Refresh()
end)
