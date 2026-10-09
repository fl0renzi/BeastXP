-- BeastXP - BeastXP_Options.lua
-- The settings page, under Options > AddOns > BeastXP, drawn the way the
-- game's own settings list is and the way ItemTree and QuestForever draw
-- theirs: the title in a header strip with a Defaults button and the divider
-- under it, section headings, then rows with the label on the left and the
-- control from the middle. Every control goes through the same setters as the
-- right-click menu and the slash commands (ns.API, in BeastXP.lua), so the
-- three can never disagree.
--
-- A canvas page (Settings.RegisterCanvasLayoutCategory), not a vertical list:
-- the game's settings search reads the rows of every vertical list, and
-- ItemTree found that carries an addon's taint into Blizzard's own rows. And
-- every frame is made at login while the page is hidden, never while the
-- settings window is open, the other rule ItemTree's taint fixes settled on.
-- The controls are the client's own templates, each one already in use by an
-- addon that runs on Forever: WowStyle1DropdownTemplate (LFGForever),
-- MinimalSliderWithSteppersTemplate and ColorSwatchTemplate (Baganator),
-- UICheckButtonTemplate and UIPanelButtonTemplate (QuestForever).

local addonName, ns = ...
if not ns.Allowed then return end

local API = ns.API

local PAGE_TITLE = "BeastXP"

-- The settings list's own measurements, as ItemTree takes them from
-- Blizzard_SettingsList: the title at 7, -22 in a 50 tall header strip, the
-- Defaults button 96 by 22 at -36, -16 from the top right, rows 26 tall with
-- 9 between them, the label 37 in, the control from 80 left of the middle.
local HEADER_HEIGHT = 50
local TITLE_X, TITLE_Y = 7, -22
local DEFAULTS_WIDTH, DEFAULTS_HEIGHT = 96, 22
local DEFAULTS_X, DEFAULTS_Y = -36, -16
local ROW_HEIGHT = 26
local ROW_SPACING = 9
local SECTION_HEIGHT = 40
local LABEL_X = 37
local CONTROL_X = -80
local PAGE_RIGHT = -20

local DROPDOWN_WIDTH = 220
local SLIDER_WIDTH = 250

-- The preview is the bar at its real size, up to what fits in its row.
local PREVIEW_ROW_HEIGHT = 34
local PREVIEW_MAX_WIDTH = 300
local PREVIEW_MAX_HEIGHT = 30

local page            -- the canvas frame, built at login
local categoryID      -- what Settings.OpenToCategory takes
local combatWaiter    -- opens the page once combat ends
local controls = {}   -- what RefreshPage keeps in step with the settings
local refreshing = false -- true while RefreshPage sets controls, so they do not call back

--------------------------------------------------------------------------------
-- Building blocks
--------------------------------------------------------------------------------

local nextY -- where the next row goes, walking down the page

local function NextRow(height)
    local row = CreateFrame("Frame", nil, page)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, nextY)
    row:SetPoint("TOPRIGHT", page, "TOPRIGHT", PAGE_RIGHT, nextY)
    row:SetHeight(height)
    nextY = nextY - height - ROW_SPACING
    return row
end

local function Section(text)
    local row = NextRow(SECTION_HEIGHT)
    local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("BOTTOMLEFT", TITLE_X, 4)
    title:SetText(text)
end

-- A row with its label; the control is anchored to the row's middle.
local function Row(text, height)
    local row = NextRow(height or ROW_HEIGHT)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", LABEL_X, 0)
    label:SetPoint("RIGHT", row, "CENTER", CONTROL_X - 8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(text)
    return row
end

local function Tooltip(widget, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Checkbox(row, onClick)
    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetPoint("LEFT", row, "CENTER", CONTROL_X, 0)
    check:SetScript("OnClick", function(self)
        if refreshing then return end
        onClick(self:GetChecked() and true or false)
    end)
    return check
end

-- The client's stepper slider, whole numbers only, with the value on its
-- right. Its change callback is the one Baganator reads on Forever.
local function Slider(row, minimum, maximum, onChange)
    local slider = CreateFrame("Slider", nil, row, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("LEFT", row, "CENTER", CONTROL_X, 0)
    slider:SetWidth(SLIDER_WIDTH)
    slider:SetHeight(20)
    slider:Init(minimum, minimum, maximum, maximum - minimum, {
        [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(
            MinimalSliderWithSteppersMixin.Label.Right,
            function(value) return ("%d"):format(math.floor(value + 0.5)) end),
    })
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if refreshing then return end
        onChange(math.floor(value + 0.5))
    end)
    return slider
end

-- The client's dropdown. The generator runs every time the menu opens and on
-- every refresh, so the list is current and the button shows the selection.
local function Dropdown(row, width, generator)
    local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("LEFT", row, "CENTER", CONTROL_X, 0)
    dropdown:SetWidth(width)
    dropdown:SetupMenu(generator)
    controls.dropdowns[#controls.dropdowns + 1] = dropdown
    return dropdown
end

-- A dropdown of LibSharedMedia choices, checked against the saved path.
local function MediaDropdown(row, choicesFunc, key, apply)
    return Dropdown(row, DROPDOWN_WIDTH, function(_, root)
        local db = API.GetDB()
        local choices = choicesFunc()
        for _, entry in ipairs(choices) do
            local path = entry.path
            root:CreateRadio(entry.name,
                function() return API.SamePath(db[key], path) end,
                function() apply(path) end)
        end
        -- A large LibSharedMedia collection would run off the screen.
        if #choices > 20 and root.SetScrollMode then
            root:SetScrollMode(400)
        end
    end)
end

local function MatchesPreset(color)
    for _, preset in ipairs(API.COLOR_PRESETS) do
        if API.SameColor(color, preset.color) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Keeping the page in step
--------------------------------------------------------------------------------

local function UpdatePreview()
    local db, preview = API.GetDB(), controls.preview
    preview:SetSize(math.min(db.width, PREVIEW_MAX_WIDTH), math.min(db.height, PREVIEW_MAX_HEIGHT))
    API.ApplyTexture(preview)
    API.ApplyFont(preview)

    local level, current, max, loyalty, points = API.PreviewPet()
    preview.status:SetMinMaxValues(0, max > 0 and max or 1)
    preview.status:SetValue(math.min(current, max))
    preview.text:SetText(API.FormatText(db.textStyle, true, level, current, max,
        db.textLoyalty and loyalty or nil, db.textTraining and points or nil))
end

local function RefreshPage()
    local db = API.GetDB()
    refreshing = true
    controls.lock:SetChecked(db.locked)
    controls.tooltip:SetChecked(db.showTooltip)
    controls.textLoyalty:SetChecked(db.textLoyalty)
    controls.textTraining:SetChecked(db.textTraining)
    controls.width:SetValue(db.width)
    controls.height:SetValue(db.height)
    controls.fontSize:SetValue(db.fontSize)
    controls.swatch:SetColorRGB(db.barColor[1], db.barColor[2], db.barColor[3])
    for _, dropdown in ipairs(controls.dropdowns) do
        dropdown:GenerateMenu()
    end
    UpdatePreview()
    refreshing = false
end

-- Called by every setter in BeastXP.lua. Only an open page is redrawn; a
-- closed one catches up in OnShow.
function ns.OnSettingsChanged()
    if page and page:IsVisible() then RefreshPage() end
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local function BuildHeader()
    local title = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", TITLE_X, TITLE_Y)
    title:SetJustifyH("LEFT")
    title:SetText(PAGE_TITLE)

    local divider = page:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOP", 0, -HEADER_HEIGHT)

    -- Defaults takes a second click, as ItemTree's does: the first only asks.
    -- Leaving the page puts the question away again.
    local defaults = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    defaults:SetSize(DEFAULTS_WIDTH, DEFAULTS_HEIGHT)
    defaults:SetPoint("TOPRIGHT", DEFAULTS_X, DEFAULTS_Y)
    defaults:SetText("Defaults")
    defaults:SetScript("OnClick", function(self)
        if self.armed then
            self.armed = false
            self:SetText("Defaults")
            API.ResetDefaults()
        else
            self.armed = true
            self:SetText("Click again")
        end
    end)
    Tooltip(defaults, "Puts every setting back to how a fresh install has it. The bar keeps its place.")
    controls.defaults = defaults
end

local function BuildBarSection()
    Section("Bar")

    controls.lock = Checkbox(Row("Lock bar"), API.SetLocked)
    Tooltip(controls.lock, "A locked bar cannot be moved or resized, and hides while no pet is out.")

    controls.tooltip = Checkbox(Row("Show tooltip"), API.SetShowTooltip)
    Tooltip(controls.tooltip, "Hovering over the bar shows your pet's name, the experience it still needs, its loyalty and its training points.")

    controls.width = Slider(Row("Width"), API.MIN_WIDTH, API.MaxWidth(), function(value)
        API.SetBarSize(value, API.GetDB().height)
    end)
    controls.height = Slider(Row("Height"), API.MIN_HEIGHT, API.MAX_HEIGHT, function(value)
        API.SetBarSize(API.GetDB().width, value)
    end)

    MediaDropdown(Row("Texture"), API.TextureChoices, "texturePath", API.SetTexturePath)

    local colorRow = Row("Color")
    local swatch = CreateFrame("Button", nil, colorRow, "ColorSwatchTemplate")
    swatch:SetPoint("LEFT", colorRow, "CENTER", CONTROL_X, 0)
    swatch:SetScript("OnClick", function() API.OpenColorPicker() end)
    Tooltip(swatch, "Click to pick any color.")
    controls.swatch = swatch

    local presets = Dropdown(colorRow, DROPDOWN_WIDTH - 32, function(_, root)
        local db = API.GetDB()
        for _, preset in ipairs(API.COLOR_PRESETS) do
            local color = preset.color
            root:CreateRadio(preset.name,
                function() return API.SameColor(db.barColor, color) end,
                function() API.SetBarColor(color[1], color[2], color[3]) end)
        end
        root:CreateRadio("Custom...",
            function() return not MatchesPreset(db.barColor) end,
            function() API.OpenColorPicker() end)
    end)
    presets:ClearAllPoints()
    presets:SetPoint("LEFT", swatch, "RIGHT", 8, 0)

    local positionRow = Row("Position")
    local reset = CreateFrame("Button", nil, positionRow, "UIPanelButtonTemplate")
    reset:SetPoint("LEFT", positionRow, "CENTER", CONTROL_X, 0)
    reset:SetSize(160, 22)
    reset:SetText("Reset position")
    reset:SetScript("OnClick", function() API.ResetLayout() end)
    Tooltip(reset, "Puts the bar back below your character at its first size.")
end

local function BuildTextSection()
    Section("Text")

    Dropdown(Row("Text"), DROPDOWN_WIDTH, function(_, root)
        local db = API.GetDB()
        for _, style in ipairs(API.TEXT_STYLES) do
            local key = style.key
            root:CreateRadio(style.name,
                function() return db.textStyle == key end,
                function() API.SetTextStyle(key) end)
        end
    end)

    controls.textLoyalty = Checkbox(Row("Loyalty"), API.SetTextLoyalty)
    Tooltip(controls.textLoyalty, "Adds your pet's loyalty rank after the text.")
    controls.textTraining = Checkbox(Row("Training points"), API.SetTextTraining)
    Tooltip(controls.textTraining, "Adds your pet's unspent training points after the text, for example 25 TP.")

    MediaDropdown(Row("Font"), API.FontChoices, "fontPath", API.SetFontPath)

    controls.fontSize = Slider(Row("Font size"), API.MIN_FONT_SIZE, API.MAX_FONT_SIZE, API.SetFontSize)

    Dropdown(Row("Outline"), DROPDOWN_WIDTH, function(_, root)
        local db = API.GetDB()
        for _, outline in ipairs(API.OUTLINES) do
            local flag = outline.flag
            root:CreateRadio(outline.name,
                function() return db.outline == flag end,
                function() API.SetOutline(flag) end)
        end
    end)
end

local function BuildPage()
    page = CreateFrame("Frame")
    page:Hide()
    controls.dropdowns = {}

    BuildHeader()
    nextY = -(HEADER_HEIGHT + 10)

    -- The bar itself is usually under the settings window, so the page shows
    -- its own copy, built the same way.
    local previewRow = Row("Preview", PREVIEW_ROW_HEIGHT)
    local preview = CreateFrame("Frame", nil, previewRow)
    preview:SetPoint("LEFT", previewRow, "CENTER", CONTROL_X, 0)
    API.BuildBarVisuals(preview)
    controls.preview = preview

    BuildBarSection()
    BuildTextSection()

    page:SetScript("OnShow", RefreshPage)
    page:SetScript("OnHide", function()
        controls.defaults.armed = false
        controls.defaults:SetText("Defaults")
    end)
end

--------------------------------------------------------------------------------
-- Registering and opening
--------------------------------------------------------------------------------

-- Called once from BeastXP.lua's PLAYER_LOGIN, after the settings are loaded,
-- for every character: the settings are account-wide, so they can be set up
-- from any of them.
function ns.InstallSettings()
    if page or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end

    BuildPage()
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, page, PAGE_TITLE)
    if not ok or not category then return end
    pcall(Settings.RegisterAddOnCategory, category)
    categoryID = category.GetID and category:GetID() or category.ID

    -- The client will not open the settings window in combat, so a request
    -- made then waits for combat to end.
    combatWaiter = CreateFrame("Frame")
    combatWaiter:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        Settings.OpenToCategory(categoryID)
    end)
end

-- Returns false when there is no page to open, so the caller can say so.
function ns.OpenSettings()
    if not categoryID then return false end
    if InCombatLockdown() then
        API.Print("the settings page opens when combat ends.")
        combatWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return true
    end
    Settings.OpenToCategory(categoryID)
    return true
end
