-- BeastXP - BeastXP.lua
-- One borderless bar for the hunter pet's experience, in the purple the game
-- draws experience in. Drag the bar to move it, drag the grip in its corner
-- to resize it, and right-click it for the lock, the texture, the font, the
-- font size and the outline. Textures and fonts come from the client, and from
-- LibSharedMedia when another addon has loaded it. /beastxp, or /petxp for
-- short, offers the same options as slash commands.
--
-- Cost: the bar is built the first time there is something to show, and it is
-- refreshed from the pet events only, never from OnUpdate; only the second-long
-- level up flash runs on one, while it plays. A character that is
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

-- Where each anchor point sits on a frame, as a fraction of its width and
-- height from its centre. A saved position may use any of them, since a drag
-- leaves the bar on whichever point the client picks.
local POINT_OFFSETS = {
    TOPLEFT    = { -0.5,  0.5 }, TOP    = { 0,  0.5 }, TOPRIGHT    = { 0.5,  0.5 },
    LEFT       = { -0.5,  0   }, CENTER = { 0,  0   }, RIGHT       = { 0.5,  0   },
    BOTTOMLEFT = { -0.5, -0.5 }, BOTTOM = { 0, -0.5 }, BOTTOMRIGHT = { 0.5, -0.5 },
}

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

-- With Color by happiness on, the bar takes the pet's mood colour instead,
-- by the number GetPetHappiness reports: 1 unhappy, 2 content, 3 happy.
local HAPPINESS_COLORS = {
    { 0.8, 0.1, 0.1 },
    { 0.9, 0.75, 0.0 },
    { 0.1, 0.7, 0.1 },
}

-- The empty part of the bar is the bar colour at this opacity.
local TRACK_ALPHA = 0.25

-- A level up washes the bar in white: in over FLASH_IN seconds to FLASH_PEAK,
-- then out until FLASH_TIME.
local FLASH_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local FLASH_IN, FLASH_TIME, FLASH_PEAK = 0.25, 1.0, 0.6

-- The chat line waits ALERT_DELAY seconds for the training points, which the
-- game may update just after the level. Alerts closer together than
-- ALERT_COOLDOWN are one alert.
local ALERT_DELAY = 0.5
local ALERT_COOLDOWN = 2

-- The sound the game plays for the player's own level up.
local LEVEL_UP_SOUND = 888

-- The tooltip's experience rate waits for RATE_MIN_TIME seconds of the pet
-- being out, and at least one gain, before it guesses.
local RATE_MIN_TIME = 60

-- The colours the game's own tooltips use for a label, for a hint line, and
-- for good and bad news.
local LABEL_COLOR = { 1.0, 0.82, 0.0 }
local HINT_COLOR  = { 0.5, 0.5, 0.5 }

-- The version the toc names, which the packager writes from the release tag,
-- for example "v1.3.0". Run straight from the repository, the toc still holds
-- the packager's placeholder, and there is no version to show.
local VERSION
do
    local GetMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = type(GetMetadata) == "function" and GetMetadata(addonName, "Version")
    if type(version) == "string" and version ~= "" and not version:find("@", 1, true) then
        VERSION = version
    end
end
local GAIN_COLOR  = { 0.1, 1.0, 0.1 }
local LOSS_COLOR  = { 1.0, 0.1, 0.1 }

-- The light blue the game's Edit Mode lays over the frames it can move, and
-- the paler blue of the X and Y shown beside the bar's name there.
local EDIT_MODE_COLOR = { 0.3, 0.65, 1.0, 0.35 }
local READOUT_COLOR   = { 0.75, 0.88, 1.0 }

-- In Edit Mode the arrow keys move the bar one step, ten with Shift.
local NUDGE_KEYS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
local NUDGE_STEP, NUDGE_SHIFT_STEP = 1, 10

-- The media every client ships. LibSharedMedia, which BeastXP does not embed,
-- adds whatever other addons register with it. A choice is saved by its path,
-- not by its LibSharedMedia name, so it keeps working whichever addon
-- registered it and whenever it did.
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
    width        = DEFAULT_WIDTH,
    height       = DEFAULT_HEIGHT,
    locked       = false,
    showTooltip  = true,
    texturePath  = "Interface\\TargetingFrame\\UI-StatusBar",
    fontPath     = "Fonts\\FRIZQT__.TTF",
    fontSize     = 11,
    outline      = "",
    textStyle    = "full",
    -- What the bar's text adds after its style.
    textLoyalty   = false,
    textHappiness = false,
    textTraining  = false,
    -- The tooltip's experience per hour and time to the next level.
    tooltipRate  = true,
    -- The bar in the pet's mood colour rather than barColor.
    happyColor   = false,
    -- What a level up does.
    alertSound   = true,
    alertFlash   = true,
    alertChat    = true,
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local db            -- BeastXPDB, set at PLAYER_LOGIN
local bar           -- built on first use
local active = false -- a hunter, on a client that reports pet experience
local isHunter = false
local moving = false -- a drag or a resize is in progress
local editing = false -- the game's Edit Mode is open

-- The pet as last read. One table, refilled in place, so a refresh allocates
-- nothing.
local pet = { present = false, current = 0, max = 0, level = nil, dead = false }

-- The last reading of the pet that is out, kept so the next one can tell the
-- same pet gaining experience or a level from another pet being summoned. All
-- nil while no pet is out, so the first reading after a summon, a swap or a
-- login only sets the baseline.
local seen = { id = nil, level = nil, current = nil, max = nil }

-- This login's experience for the tooltip's rate: which pet it is for, the
-- experience gained, and how long that pet has been out. Kept in memory only.
-- The clock stops while the pet is away, so a dismissed pet does not drag the
-- rate down, and a different pet starts it over.
local session = { id = nil, gained = 0, elapsed = 0, since = nil }

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
    if not POINT_OFFSETS[db.point] or type(db.x) ~= "number" or type(db.y) ~= "number" then
        db.point, db.relativePoint, db.x, db.y = nil, nil, nil, nil
    elseif not POINT_OFFSETS[db.relativePoint] then
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
        pet.current, pet.max, pet.level, pet.dead = 0, 0, nil, false
        return
    end

    local current, max = GetPetExperience()
    current, max = SafeValue(current), SafeValue(max)
    pet.current = type(current) == "number" and math.floor(current) or 0
    pet.max = type(max) == "number" and math.floor(max) or 0

    local level = SafeValue(UnitLevel("pet"))
    pet.level = (type(level) == "number" and level > 0) and math.floor(level) or nil

    -- A dead pet the client still counts as out. One it stops counting reads
    -- as no pet at all.
    pet.dead = type(UnitIsDead) == "function" and SafeValue(UnitIsDead("pet")) == true
end

-- A number for the short style: 12345 becomes 12.3k.
local function ShortNumber(value)
    if value >= 10000 then return ("%.1fk"):format(value / 1000) end
    return ("%d"):format(value)
end

-- A pet's text in the given style (see TEXT_STYLES). Any part the game did not
-- report, the level or the experience, is left out rather than shown as 0.
local function StyleText(style, present, level, current, max)
    -- A bar shown with no pet out says so whatever the style, so an empty bar
    -- never looks broken.
    if not present then return "No pet" end
    if style == "none" then return "" end

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

-- The style's text with the loyalty rank, the happiness and the training
-- points after it, when they are given, spaced the way the style spaces its
-- own parts. No text stays no text. The settings preview formats its sample
-- pet through here too.
local function FormatText(style, present, level, current, max, loyalty, happiness, points)
    local text = StyleText(style, present, level, current, max)
    if style == "none" or not present then return text end

    local gap = style == "full" and "   " or "  "
    if loyalty then
        text = (text ~= "" and text .. gap or "") .. loyalty
    end
    if happiness then
        text = (text ~= "" and text .. gap or "") .. happiness
    end
    if points then
        text = (text ~= "" and text .. gap or "") .. ("%d TP"):format(points)
    end
    return text
end

-- Loyalty, happiness and training points, read the way the game's own pet
-- panel and trainer read them, when the tooltip is drawn or the bar's text
-- includes them. Each is nil when the client does not report it, and is left
-- out.

-- The loyalty rank as the character frame shows it, for example "Faithful".
local function PetLoyalty()
    local info = C_PetInfo
    if not (info and info.GetPetLoyalty) then return nil end
    local text = SafeValue(info.GetPetLoyalty())
    if type(text) ~= "string" or text == "" then return nil end
    return text
end

-- Above 0 while the pet is gaining loyalty, below 0 while it is losing it.
local function PetLoyaltyRate()
    local info = C_PetInfo
    if not (info and info.GetPetHappiness) then return nil end
    local rate = SafeValue(select(3, info.GetPetHappiness()))
    return type(rate) == "number" and rate or nil
end

-- The three moods the classic client gives a pet, by the number
-- GetPetHappiness reports: 1 unhappy, 2 content, 3 happy.
local HAPPINESS_TEXT = { "Unhappy", "Content", "Happy" }

-- The pet's mood as that number, or nil.
local function PetMood()
    local info = C_PetInfo
    if not (info and info.GetPetHappiness) then return nil end
    local happiness = SafeValue((info.GetPetHappiness()))
    if type(happiness) ~= "number" then return nil end
    -- A mood outside the three the client names is left out. The range check
    -- catches a not-a-number read too, which would be an invalid table index.
    local mood = math.floor(happiness)
    if not (mood >= 1 and mood <= 3) then return nil end
    return mood
end

-- The pet's mood as the game's own pet panel words it, for example "Happy".
local function PetHappiness()
    local mood = PetMood()
    return mood and HAPPINESS_TEXT[mood]
end

-- Unspent training points. The trainer never shows fewer than none.
local function PetTrainingPoints()
    local info = C_PetInfo
    if not (info and info.GetPetTrainingPoints) then return nil end
    local total, used = info.GetPetTrainingPoints()
    total, used = SafeValue(total), SafeValue(used)
    if type(total) ~= "number" or type(used) ~= "number" then return nil end
    return math.max(total - used, 0)
end

--------------------------------------------------------------------------------
-- Following the pet
--------------------------------------------------------------------------------

local function Now()
    return type(GetTime) == "function" and GetTime() or 0
end

-- Which pet is out: its GUID where the client gives one, its name otherwise.
-- nil when neither can be read, and the pet is then not followed.
local function PetIdentity()
    local guid = type(UnitGUID) == "function" and SafeValue(UnitGUID("pet")) or nil
    if type(guid) == "string" and guid ~= "" then return guid end
    local name = SafeValue(UnitName("pet"))
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

local function SessionTime()
    return session.elapsed + (session.since and (Now() - session.since) or 0)
end

local function StartSession(id)
    session.id, session.gained, session.elapsed = id, 0, 0
    session.since = id and Now() or nil
end

-- /petxp session reset and the settings page's button: the rate starts over
-- for the pet that is out now.
local function ResetSession()
    StartSession(session.since and session.id or nil)
end

-- Compares the reading ReadPet just took with the last one. Counts the
-- experience the same pet gained, across a level boundary too, and returns
-- true when that pet went up a level. A drop, a lower level or a different
-- pet counts nothing.
local function FollowPet()
    -- A dead pet is away: the clock stops, and its revival sets a baseline.
    local id = pet.present and not pet.dead and pet.level and PetIdentity() or nil
    if not id then
        if session.since then
            session.elapsed = session.elapsed + (Now() - session.since)
            session.since = nil
        end
        seen.id, seen.level, seen.current, seen.max = nil, nil, nil, nil
        return false
    end

    if id ~= session.id or (seen.id == id and pet.level < seen.level) then
        StartSession(id)
    elseif not session.since then
        session.since = Now()
    end

    -- The game may report the new level and the new experience in separate
    -- events, in either order. Experience that drops on the same level is the
    -- new level's arriving first: the old reading is kept until the level
    -- follows. A level whose experience still reads as the old level's counts
    -- the rest of the old level only, and the next reading counts from 0.
    local leveled = false
    local current = pet.current
    if seen.id == id then
        if pet.level > seen.level then
            leveled = true
            if seen.max > 0 then
                session.gained = session.gained + (seen.max - seen.current)
            end
            if pet.max == seen.max then
                current = 0
            else
                session.gained = session.gained + pet.current
            end
        elseif pet.level == seen.level then
            if pet.current < seen.current then return false end
            session.gained = session.gained + (pet.current - seen.current)
        end
    end
    seen.id, seen.level, seen.current, seen.max = id, pet.level, current, pet.max
    return leveled
end

-- Experience per hour and seconds to the next level, from this session. nil
-- until there is enough to go on, or at the level cap.
local function PetRate()
    if not (pet.present and pet.max > 0 and session.id) then return nil end
    local elapsed = SessionTime()
    if elapsed < RATE_MIN_TIME or session.gained <= 0 then return nil end
    local perSecond = session.gained / elapsed
    return perSecond * 3600, math.max(pet.max - pet.current, 0) / perSecond
end

-- 12345 becomes 12,345.
local function GroupedNumber(value)
    local text = ("%d"):format(Round(value))
    local count
    repeat
        text, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until count == 0
    return text
end

-- Seconds as hours and minutes: 5100 becomes 1h 25m.
local function Duration(seconds)
    local minutes = math.ceil(seconds / 60)
    if minutes < 60 then return ("%dm"):format(math.max(minutes, 1)) end
    return ("%dh %dm"):format(math.floor(minutes / 60), minutes % 60)
end

local function BarText()
    -- The fill keeps the pet's experience; the text says why it is not
    -- moving.
    if pet.present and pet.dead then return "Pet dead" end
    local loyalty = db.textLoyalty and pet.present and PetLoyalty() or nil
    local happiness = db.textHappiness and pet.present and PetHappiness() or nil
    local points = db.textTraining and pet.present and PetTrainingPoints() or nil
    return FormatText(db.textStyle, pet.present, pet.level, pet.current, pet.max,
        loyalty, happiness, points)
end

-- With Show tooltip off, hovering the bar or its grip shows nothing. While the
-- game's Edit Mode is open the bar is being placed, not read, so it says how
-- to move it instead, below the bar to keep its name and X and Y in sight.
local function ShowTooltip(owner)
    if not db.showTooltip then return end
    if editing then
        GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(addonName, 1, 1, 1)
        GameTooltip:AddLine("Drag to move, drag the corner to resize.", unpack(HINT_COLOR))
        GameTooltip:AddLine(("Arrow keys move it %d, or %d with Shift."):format(NUDGE_STEP, NUDGE_SHIFT_STEP),
            unpack(HINT_COLOR))
        GameTooltip:Show()
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")

    if pet.present then
        GameTooltip:AddLine(SafeValue(UnitName("pet")) or "Your pet", 1, 1, 1)
        if pet.dead then
            GameTooltip:AddLine("Dead", unpack(LOSS_COLOR))
        end
        if pet.level then
            GameTooltip:AddLine(("Level %d"):format(pet.level), 1, 1, 1)
        end
        if pet.max > 0 then
            GameTooltip:AddDoubleLine("Experience", ("%d / %d"):format(pet.current, pet.max),
                LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], 1, 1, 1)
            GameTooltip:AddDoubleLine("To next level", ("%d"):format(pet.max - pet.current),
                LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], 1, 1, 1)
            if db.tooltipRate then
                local perHour, toLevel = PetRate()
                if perHour then
                    GameTooltip:AddDoubleLine("Per hour", GroupedNumber(perHour),
                        LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], 1, 1, 1)
                    GameTooltip:AddDoubleLine("Time to level", Duration(toLevel),
                        LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], 1, 1, 1)
                else
                    GameTooltip:AddLine("Gathering experience rate...", unpack(HINT_COLOR))
                end
            end
        end

        local loyalty = PetLoyalty()
        if loyalty then
            GameTooltip:AddDoubleLine("Loyalty", loyalty,
                LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], 1, 1, 1)
            local rate = PetLoyaltyRate()
            if rate and rate > 0 then
                GameTooltip:AddLine("Gaining loyalty", unpack(GAIN_COLOR))
            elseif rate and rate < 0 then
                GameTooltip:AddLine("Losing loyalty", unpack(LOSS_COLOR))
            end
        end

        local happiness = PetHappiness()
        if happiness then
            GameTooltip:AddDoubleLine("Happiness", happiness,
                LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], 1, 1, 1)
        end

        local points = PetTrainingPoints()
        if points then
            GameTooltip:AddDoubleLine("Training points", ("%d"):format(points),
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
local UpdateReadout, NudgeBar -- defined with the Edit Mode code, below

-- Tells the settings page (BeastXP_Options.lua) and the X and Y shown in
-- Edit Mode that a setting changed, from wherever it was changed: the page,
-- the right-click menu, a slash command, a drag or an arrow key. Each only
-- redraws while it is showing.
local function NotifyChanged()
    if ns.OnSettingsChanged then ns.OnSettingsChanged() end
    UpdateReadout()
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

    -- The level up flash: a white wash over the fill, under the text, faded
    -- in and out by a frame that is only shown, and only runs, while it plays.
    local flash = status:CreateTexture(nil, "ARTWORK", nil, 7)
    flash:SetAllPoints(status)
    flash:SetTexture(FLASH_TEXTURE)
    flash:SetBlendMode("ADD")
    flash:SetAlpha(0)
    frame.flash = flash

    local flasher = CreateFrame("Frame", nil, frame)
    flasher:Hide()
    flasher:SetScript("OnUpdate", function(self, elapsed)
        self.time = self.time + elapsed
        local t = self.time
        if t >= FLASH_TIME then
            flash:SetAlpha(0)
            self:Hide()
        elseif t < FLASH_IN then
            flash:SetAlpha(FLASH_PEAK * t / FLASH_IN)
        else
            flash:SetAlpha(FLASH_PEAK * (1 - (t - FLASH_IN) / (FLASH_TIME - FLASH_IN)))
        end
    end)
    frame.flasher = flasher
end

-- Plays the flash on the bar or the settings preview, from the start.
local function FlashFrame(frame)
    frame.flasher.time = 0
    frame.flash:SetAlpha(0)
    frame.flasher:Show()
end

-- SetFont returns false when the file cannot be loaded. The chosen font falls
-- back to the default one, and that to the game's own font object, so the
-- string always has a font: SetText errors on a font string without one.
local function PutFont(text)
    if text:SetFont(db.fontPath, db.fontSize, db.outline) == false
        and text:SetFont(DEFAULTS.fontPath, db.fontSize, db.outline) == false then
        text:SetFontObject(GameFontHighlightSmall)
    end
end

-- A font file another addon ships loads in the background the first time
-- something asks for it, which for the bar is when the pet first shows up
-- after login. Until the file is in, SetFont returns false and the text is
-- drawn in the fallback font; once it is, the game switches the string to it
-- by itself, but does not always draw the text again, and the bar stayed
-- blank until its text next changed, when the pet gained experience. So
-- while the bar's text has not taken the chosen font, it is looked at again
-- every FONT_CHECK_INTERVAL, and once it has, or after FONT_CHECK_TRIES looks
-- for a file that never loads, the font goes back on and the text is drawn
-- afresh.
local FONT_CHECK_INTERVAL = 0.25 -- seconds
local FONT_CHECK_TRIES = 40      -- ten seconds in all

local fontCheck -- the ticker waiting for the bar's font, while it waits

local function WatchBarFont()
    if fontCheck then fontCheck:Cancel() end
    fontCheck = nil
    if SamePath((bar.text:GetFont()), db.fontPath) then return end
    if not (C_Timer and C_Timer.NewTicker) then return end

    local tries = 0
    fontCheck = C_Timer.NewTicker(FONT_CHECK_INTERVAL, function()
        tries = tries + 1
        if tries < FONT_CHECK_TRIES and not SamePath((bar.text:GetFont()), db.fontPath) then return end
        fontCheck:Cancel()
        fontCheck = nil
        PutFont(bar.text)
        local shown = bar.text:GetText()
        bar.text:SetText("")
        bar.text:SetText(shown)
    end)
end

-- The bar's font and the preview's. Only the bar waits for its file: the
-- preview is drawn again whenever the settings page shows.
local function ApplyFont(frame)
    PutFont(frame.text)
    if frame == bar then WatchBarFont() end
end

-- The bar colour, on the fill and, dimmed, on the track behind it. With Color
-- by happiness on, the colour of the mood the frame shows (frame.mood, set by
-- Refresh for the bar and by the settings page for its preview), and the bar
-- colour while the mood is unknown or no pet is out.
local function ApplyColor(frame)
    local color = db.happyColor and frame.mood and HAPPINESS_COLORS[frame.mood] or db.barColor
    local r, g, b = color[1], color[2], color[3]
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

-- The bar moves and resizes while it is unlocked, and while the game's Edit
-- Mode is open whatever the lock says.
local function CanMove()
    return editing or not db.locked
end

-- The grip shows while the bar can be resized, the highlight while Edit Mode
-- is open. The arrow keys listen only while Edit Mode is open, and step aside
-- for combat, where they could no longer pass keys on to the game.
local function ApplyLock()
    bar.grip:SetShown(CanMove())
    bar.highlight:SetShown(editing)
    local nudger = bar.nudger
    if editing then
        nudger:RegisterEvent("PLAYER_REGEN_DISABLED")
        nudger:RegisterEvent("PLAYER_REGEN_ENABLED")
        nudger:SetShown(not InCombatLockdown())
    else
        nudger:UnregisterAllEvents()
    end
end

-- Ends a drag or a resize and remembers where the bar ended up. Also runs on
-- hide, since a bar hidden mid-drag would otherwise stay stuck to the cursor.
local function StopMoving()
    if not moving then return end
    moving = false
    bar:StopMovingOrSizing()
    bar.highlight:SetScript("OnUpdate", nil)
    SaveLayout()
end

-- Starts a drag or a resize. In Edit Mode the X and Y follow the bar every
-- frame until it is let go, since the saved position only changes then.
local function StartMoving(resize)
    moving = true
    if resize then bar:StartSizing("BOTTOMRIGHT") else bar:StartMoving() end
    if editing then bar.highlight:SetScript("OnUpdate", UpdateReadout) end
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
        if button ~= "LeftButton" or not CanMove() then return end
        StartMoving(true)
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

    -- While the game's Edit Mode is open the bar is laid over in its light
    -- blue, with its name and its X and Y above it. Above the fill, below the
    -- grip, and taking no clicks, so the bar under it still drags.
    local highlight = CreateFrame("Frame", nil, bar)
    highlight:SetAllPoints(bar)
    highlight:SetFrameLevel(bar.status:GetFrameLevel() + 1)
    local wash = highlight:CreateTexture(nil, "OVERLAY")
    wash:SetAllPoints(highlight)
    wash:SetColorTexture(unpack(EDIT_MODE_COLOR))
    local name = highlight:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("BOTTOMLEFT", highlight, "TOPLEFT", 0, 3)
    name:SetText(addonName)
    local readout = highlight:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    readout:SetPoint("LEFT", name, "RIGHT", 8, 0)
    readout:SetTextColor(unpack(READOUT_COLOR))
    bar.readout = readout
    highlight:Hide()
    bar.highlight = highlight

    -- The arrow keys, the way EllesmereUI's unlock mode takes them: a frame
    -- above Edit Mode's own dialogs sees each key first, keeps an arrow while
    -- the mouse is over the bar, and passes every other key on to the game,
    -- Edit Mode's own arrow keys included. A child of the highlight, so it is
    -- only there while Edit Mode is open; ApplyLock hides it for combat.
    local nudger = CreateFrame("Frame", nil, highlight)
    nudger:SetFrameStrata("FULLSCREEN_DIALOG")
    nudger:EnableKeyboard(true)
    nudger:SetPropagateKeyboardInput(true)
    nudger:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        self:SetPropagateKeyboardInput(not (bar:IsMouseOver() and NudgeBar(key)))
    end)
    nudger:SetScript("OnEvent", function(self, event)
        self:SetShown(event == "PLAYER_REGEN_ENABLED")
    end)
    bar.nudger = nudger

    bar:SetScript("OnDragStart", function()
        if not CanMove() then return end
        StartMoving(false)
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

-- The level up alert, in the three parts the settings turn on: the game's
-- level up sound, the flash on the bar, and a line in chat. The chat line
-- waits a moment for the training points, which the game may update just
-- after the level. A test, from the settings page or /petxp levelalert test,
-- plays every part that is on, whatever the cooldown, and names the next
-- level of the pet that is out, or a sample one.
local lastAlert -- when the last alert played

local function AlertText(name, level, points)
    local text = ("%s reached level %d."):format(name, level)
    if points and points > 0 then
        text = text .. (" You have %d training point%s to spend."):format(points, points == 1 and "" or "s")
    end
    return text
end

local function LevelUpAlert(test)
    local now = Now()
    if not test and lastAlert and now - lastAlert < ALERT_COOLDOWN then return end
    lastAlert = now

    if db.alertSound and type(PlaySound) == "function" then
        PlaySound(SOUNDKIT and SOUNDKIT.LEVEL_UP or LEVEL_UP_SOUND)
    end
    if db.alertFlash and bar and bar:IsShown() then FlashFrame(bar) end
    if not db.alertChat then return end

    local name = pet.present and SafeValue(UnitName("pet")) or nil
    if type(name) ~= "string" or name == "" then name = "Your pet" end
    local level = pet.level or 14
    if test then level = level + 1 end
    local function Say()
        local points = pet.present and PetTrainingPoints() or (test and 5) or nil
        Print(AlertText(name, level, points))
    end
    if C_Timer and C_Timer.After then C_Timer.After(ALERT_DELAY, Say) else Say() end
end

-- The one place the bar is updated. It shows while a hunter pet is out, and
-- also while the bar can be moved, so it can be placed before there is a pet.
local function Refresh()
    if not active then return end
    ReadPet()
    local leveled = FollowPet()

    if not pet.present and not CanMove() then
        if bar then bar:Hide() end
        return
    end

    local frame = EnsureBar()
    frame.mood = pet.present and PetMood() or nil
    ApplyColor(frame)
    if pet.present and pet.max > 0 then
        frame.status:SetMinMaxValues(0, pet.max)
        frame.status:SetValue(math.min(pet.current, pet.max))
    else
        frame.status:SetMinMaxValues(0, 1)
        frame.status:SetValue(0)
    end
    frame.text:SetText(BarText())
    frame:Show()
    if leveled then LevelUpAlert(false) end

    if GameTooltip:IsShown() and GameTooltip:GetOwner() == frame then
        ShowTooltip(frame)
    end
end

-- The game's Edit Mode opening or closing. An addon cannot join Edit Mode
-- itself, but it is told when it opens and closes: while it is open the bar
-- shows, even without a pet, highlighted and free to move and resize, and
-- closing it puts everything back as the settings have it. The bar keeps its
-- own saved position either way.
local function SetEditing(open)
    editing = open
    StopMoving()
    if bar then ApplyLock() end
    Refresh()
    UpdateReadout()
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

-- What the bar's text adds after its style: the loyalty rank, the happiness
-- and the unspent training points.
local function SetTextLoyalty(show)
    db.textLoyalty = show and true or false
    Refresh()
    NotifyChanged()
end

local function SetTextHappiness(show)
    db.textHappiness = show and true or false
    Refresh()
    NotifyChanged()
end

local function SetTextTraining(show)
    db.textTraining = show and true or false
    Refresh()
    NotifyChanged()
end

local function SetTooltipRate(show)
    db.tooltipRate = show and true or false
    Refresh()
    NotifyChanged()
end

local function SetHappyColor(on)
    db.happyColor = on and true or false
    if bar then ApplyColor(bar) end
    NotifyChanged()
end

-- What a level up does, by part: "sound", "flash" or "chat".
local ALERT_KEYS = { sound = "alertSound", flash = "alertFlash", chat = "alertChat" }

local function SetAlert(part, on)
    db[ALERT_KEYS[part]] = on and true or false
    NotifyChanged()
end

-- The size from the settings page's sliders. The bar keeps its place.
local function SetBarSize(width, height)
    db.width = Clamp(Round(width), MIN_WIDTH, MaxWidth())
    db.height = Clamp(Round(height), MIN_HEIGHT, MAX_HEIGHT)
    if bar then bar:SetSize(db.width, db.height) end
    NotifyChanged()
end

-- The bar's size as it is drawn: the saved one, inside the bounds.
local function DrawnSize()
    return Clamp(db.width, MIN_WIDTH, MaxWidth()), Clamp(db.height, MIN_HEIGHT, MAX_HEIGHT)
end

-- Where the bar sits, as X and Y: its centre's distance from the centre of
-- the screen, right and up. Worked out from the saved anchor, whichever point
-- a drag left it on. These are the numbers the settings page and
-- /petxp position show and take.
local function BarPosition()
    if not db.point then return DEFAULT_X, DEFAULT_Y end
    local point, relative = POINT_OFFSETS[db.point], POINT_OFFSETS[db.relativePoint]
    local width, height = DrawnSize()
    return Round(relative[1] * UIParent:GetWidth() + db.x - point[1] * width),
        Round(relative[2] * UIParent:GetHeight() + db.y - point[2] * height)
end

-- How far X and Y can go with the whole bar still on screen.
local function PositionLimits()
    local width, height = DrawnSize()
    return math.max(0, math.floor((UIParent:GetWidth() - width) / 2)),
        math.max(0, math.floor((UIParent:GetHeight() - height) / 2))
end

-- Moves the bar to an X and Y, kept on screen, by anchoring its centre to the
-- screen's.
local function SetBarPosition(x, y)
    local maxX, maxY = PositionLimits()
    db.point, db.relativePoint = "CENTER", "CENTER"
    db.x, db.y = Clamp(Round(x), -maxX, maxX), Clamp(Round(y), -maxY, maxY)
    if bar then ApplyLayout() end
    NotifyChanged()
end

-- Edit Mode's X and Y beside the bar's name. They come from where the bar is
-- drawn, so they follow a drag; the saved position only changes when it ends.
function UpdateReadout()
    if not (bar and editing) then return end
    local x, y = bar:GetCenter()
    local centerX, centerY = UIParent:GetCenter()
    if x and centerX then
        x, y = Round(x - centerX), Round(y - centerY)
    else
        x, y = BarPosition()
    end
    bar.readout:SetText(("X %d   Y %d"):format(x, y))
end

-- Moves the bar a step for an arrow key, ten with Shift. False for any other
-- key, which the caller passes on to the game.
function NudgeBar(key)
    local direction = NUDGE_KEYS[key]
    if not direction then return false end
    local step = IsShiftKeyDown() and NUDGE_SHIFT_STEP or NUDGE_STEP
    local x, y = BarPosition()
    SetBarPosition(x + direction[1] * step, y + direction[2] * step)
    return true
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

-- /petxp session reset and the settings page's button. An open tooltip
-- shows the rate starting over.
local function RestartSession()
    ResetSession()
    Refresh()
end

--------------------------------------------------------------------------------
-- Right-click menu
--------------------------------------------------------------------------------

-- Every choice of one kind of media ("font" or "statusbar"): the built-in
-- ones first, then whatever LibSharedMedia knows that is not one of them by
-- file or by name (it has its own Morpheus, in another file). Built when the
-- menu opens or a slash command asks, so LibSharedMedia is found whichever
-- addon loaded it, and media registered late is still there. The list costs
-- nothing until it is wanted.
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
        root:CreateTitle(VERSION and (addonName .. " " .. VERSION) or addonName)
        root:CreateCheckbox("Lock bar",
            function() return db.locked end,
            function() SetLocked(not db.locked) end)
        root:CreateCheckbox("Show tooltip",
            function() return db.showTooltip end,
            function() SetShowTooltip(not db.showTooltip) end)
        root:CreateCheckbox("Experience rate in tooltip",
            function() return db.tooltipRate end,
            function() SetTooltipRate(not db.tooltipRate) end)

        local alertMenu = root:CreateButton("Level-up alert")
        alertMenu:CreateCheckbox("Sound",
            function() return db.alertSound end,
            function() SetAlert("sound", not db.alertSound) end)
        alertMenu:CreateCheckbox("Flash",
            function() return db.alertFlash end,
            function() SetAlert("flash", not db.alertFlash) end)
        alertMenu:CreateCheckbox("Chat message",
            function() return db.alertChat end,
            function() SetAlert("chat", not db.alertChat) end)
        alertMenu:CreateDivider()
        alertMenu:CreateButton("Test alert", function() LevelUpAlert(true) end)

        AddMediaMenu(root, "Texture", TextureChoices(), "texturePath", SetTexturePath)

        local colorMenu = root:CreateButton("Bar color")
        for _, preset in ipairs(COLOR_PRESETS) do
            local color = preset.color
            colorMenu:CreateRadio(preset.name,
                function() return SameColor(db.barColor, color) end,
                function() SetBarColor(color[1], color[2], color[3]) end)
        end
        colorMenu:CreateButton("Custom color...", function() OpenColorPicker() end)
        colorMenu:CreateDivider()
        colorMenu:CreateCheckbox("Color by happiness",
            function() return db.happyColor end,
            function() SetHappyColor(not db.happyColor) end)

        local textMenu = root:CreateButton("Text")
        for _, style in ipairs(TEXT_STYLES) do
            local key = style.key
            textMenu:CreateRadio(style.name,
                function() return db.textStyle == key end,
                function() SetTextStyle(key) end)
        end
        textMenu:CreateDivider()
        textMenu:CreateCheckbox("Loyalty",
            function() return db.textLoyalty end,
            function() SetTextLoyalty(not db.textLoyalty) end)
        textMenu:CreateCheckbox("Happiness",
            function() return db.textHappiness end,
            function() SetTextHappiness(not db.textHappiness) end)
        textMenu:CreateCheckbox("Training points",
            function() return db.textTraining end,
            function() SetTextTraining(not db.textTraining) end)

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
    "/petxp width <number> - the bar's width, from " .. MIN_WIDTH .. " to nearly the screen's width",
    "/petxp height " .. MIN_HEIGHT .. "-" .. MAX_HEIGHT .. " - the bar's height",
    "/petxp position <x> <y> - where the bar sits, measured from the center of the screen",
    "/petxp tooltip on | off - the tooltip when you hover over the bar",
    "/petxp rate on | off - experience per hour and time to level in the tooltip",
    "/petxp session - this session's rate; /petxp session reset starts it over",
    "/petxp texture <name> - for example blizzard, solid or a LibSharedMedia texture",
    "/petxp color - pick the bar color, or give purple | blue | green | a hex code like 33aaff",
    "/petxp happycolor on | off - color the bar by happiness: green, yellow or red",
    "/petxp levelalert sound | flash | chat on | off - what a level up does",
    "/petxp levelalert test - play the level-up alert",
    "/petxp text full | short | level | percent | none - how much the bar says",
    "/petxp loyalty on | off - add your pet's loyalty to the bar's text",
    "/petxp happiness on | off - add its happiness, Happy, Content or Unhappy",
    "/petxp training on | off - add its unspent training points (TP)",
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
    elseif command == "width" or command == "height" then
        local size = tonumber(word:match("^%d+$") or "")
        if size and command == "width" then
            SetBarSize(size, db.height)
        elseif size then
            SetBarSize(db.width, size)
        end
        if size then
            Print(("bar size set to %d x %d."):format(Round(db.width), Round(db.height)))
        elseif command == "width" then
            Print(("give a width from %d to %d, for example /petxp width 240.")
                :format(MIN_WIDTH, math.floor(MaxWidth())))
        else
            Print(("give a height from %d to %d, for example /petxp height 18.")
                :format(MIN_HEIGHT, MAX_HEIGHT))
        end
    elseif command == "position" then
        local x, y = word:match("^(%-?%d+)%s+(%-?%d+)$")
        if x then
            SetBarPosition(tonumber(x), tonumber(y))
            Print(("bar moved to %d, %d from the center of the screen."):format(BarPosition()))
        else
            Print(("the bar is at %d, %d from the center of the screen. Give two numbers to move it, for example /petxp position 0 -180.")
                :format(BarPosition()))
        end
    elseif command == "tooltip" then
        if word == "on" or word == "off" then
            SetShowTooltip(word == "on")
            Print(db.showTooltip and "tooltip on: hover over the bar for your pet's details."
                or "tooltip off: hovering over the bar shows nothing.")
        else
            Print("use /petxp tooltip on or /petxp tooltip off.")
        end
    elseif command == "rate" then
        if word == "on" or word == "off" then
            SetTooltipRate(word == "on")
            Print(db.tooltipRate and "the tooltip shows your pet's experience per hour and time to level."
                or "the tooltip leaves the experience rate out.")
        else
            Print("use /petxp rate on or /petxp rate off.")
        end
    elseif command == "session" then
        if word == "reset" then
            RestartSession()
            Print("experience rate started over.")
        elseif word == "" then
            local perHour, toLevel = PetRate()
            if perHour then
                Print(("%s experience per hour, level in %s."):format(GroupedNumber(perHour), Duration(toLevel)))
            else
                Print(("still gathering: the rate shows after a minute with your pet out and some experience gained. %d gained so far.")
                    :format(session.gained))
            end
        else
            Print("use /petxp session, or /petxp session reset to start the rate over.")
        end
    elseif command == "happycolor" or command == "happycolour" then
        if word == "on" or word == "off" then
            SetHappyColor(word == "on")
            Print(db.happyColor and "the bar is colored by your pet's happiness: green, yellow or red."
                or "the bar keeps its own color.")
        else
            Print("use /petxp happycolor on or /petxp happycolor off.")
        end
    elseif command == "levelalert" or command == "alert" then
        local part, state = word:match("^(%S+)%s+(%S+)$")
        if word == "test" then
            LevelUpAlert(true)
        elseif part and ALERT_KEYS[part] and (state == "on" or state == "off") then
            SetAlert(part, state == "on")
            Print(("level-up %s %s."):format(part, state))
        else
            Print("use /petxp levelalert sound, flash or chat with on or off, or /petxp levelalert test.")
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
    elseif command == "loyalty" then
        if word == "on" or word == "off" then
            SetTextLoyalty(word == "on")
            Print(db.textLoyalty and "the bar's text shows your pet's loyalty."
                or "the bar's text leaves loyalty out.")
        else
            Print("use /petxp loyalty on or /petxp loyalty off.")
        end
    elseif command == "happiness" or command == "happy" then
        if word == "on" or word == "off" then
            SetTextHappiness(word == "on")
            Print(db.textHappiness and "the bar's text shows your pet's happiness."
                or "the bar's text leaves happiness out.")
        else
            Print("use /petxp happiness on or /petxp happiness off.")
        end
    elseif command == "training" or command == "tp" then
        if word == "on" or word == "off" then
            SetTextTraining(word == "on")
            Print(db.textTraining and "the bar's text shows your pet's unspent training points."
                or "the bar's text leaves training points out.")
        else
            Print("use /petxp training on or /petxp training off.")
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
    Version = VERSION, -- nil when the toc names none
    GetDB = function() return db end,
    Print = Print,

    BuildBarVisuals = BuildBarVisuals,
    ApplyTexture = ApplyTexture,
    ApplyFont = ApplyFont,
    FormatText = FormatText,
    -- The preview shows the real pet when one is out and reports its
    -- experience, and the sample pet of the Text menu's examples otherwise:
    -- level, experience, the most there is, loyalty, happiness and training
    -- points, then the mood as a number for the happiness colour.
    PreviewPet = function()
        if pet.present and pet.max > 0 then
            return pet.level, pet.current, pet.max, PetLoyalty(), PetHappiness(), PetTrainingPoints(), PetMood()
        end
        return 14, 1290, 2150, "Faithful", "Happy", 25, 3
    end,
    HAPPINESS_TEXT = HAPPINESS_TEXT,
    FlashFrame = FlashFrame,
    TestAlert = function() LevelUpAlert(true) end,

    SetLocked = SetLocked,
    SetShowTooltip = SetShowTooltip,
    SetBarSize = SetBarSize,
    BarPosition = BarPosition,
    SetBarPosition = SetBarPosition,
    -- The X and Y sliders reach the edges of the screen; the setter keeps
    -- the whole bar on it.
    PositionRange = function()
        return math.floor(UIParent:GetWidth() / 2), math.floor(UIParent:GetHeight() / 2)
    end,
    SetTexturePath = SetTexturePath,
    SetBarColor = SetBarColor,
    OpenColorPicker = OpenColorPicker,
    SetTextStyle = SetTextStyle,
    SetTextLoyalty = SetTextLoyalty,
    SetTextHappiness = SetTextHappiness,
    SetTextTraining = SetTextTraining,
    SetTooltipRate = SetTooltipRate,
    RestartSession = RestartSession,
    SetHappyColor = SetHappyColor,
    SetAlert = SetAlert,
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
-- kills. UNIT_HAPPINESS and UNIT_PET_TRAINING_POINTS keep happiness, loyalty
-- and training points current, on the bar, in its happiness colour and in an
-- open tooltip. UNIT_PET and UNIT_LEVEL tell a summon or a swap from a level
-- up, through FollowPet. UNIT_HEALTH is read only for the pet dying or
-- coming back. Each is
-- registered through pcall: registering an event the client does not have
-- raises an error, and one missing event must not stop the rest.
local PET_EVENTS = {
    "UNIT_PET",
    "UNIT_PET_EXPERIENCE",
    "UNIT_LEVEL",
    "PET_UI_UPDATE",
    "PLAYER_XP_UPDATE",
    "PLAYER_ENTERING_WORLD",
    "UNIT_HAPPINESS",
    "UNIT_PET_TRAINING_POINTS",
    "UNIT_HEALTH",
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
        -- The game's Edit Mode says when it opens and closes through the
        -- EventRegistry, which calls back through securecallfunction, so the
        -- bar's code cannot taint Edit Mode's.
        if EventRegistry and EventRegistry.RegisterCallback then
            EventRegistry:RegisterCallback("EditMode.Enter", function() SetEditing(true) end, self)
            EventRegistry:RegisterCallback("EditMode.Exit", function() SetEditing(false) end, self)
        end
        Refresh()
        return
    end

    unit = SafeValue(unit)
    if event == "UNIT_PET" and unit ~= "player" then return end
    if (event == "UNIT_LEVEL" or event == "UNIT_HAPPINESS" or event == "UNIT_HEALTH") and unit ~= "pet" then
        return
    end
    -- Health changes all through a fight; only a death or a revival matters.
    if event == "UNIT_HEALTH" then
        local dead = type(UnitIsDead) == "function" and SafeValue(UnitIsDead("pet")) == true
        if dead == pet.dead then return end
    end
    Refresh()
end)
