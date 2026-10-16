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
-- UICheckButtonTemplate and UIPanelButtonTemplate (QuestForever), and
-- InputBoxTemplate from the client's own shared templates.

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

-- Under the header the page scrolls, since its rows can be taller than the
-- settings window leaves room for. The client's scroll bar sits 6 to the
-- right of the scrolling area and is 8 wide.
local SCROLL_TOP = HEADER_HEIGHT + 2
local SCROLL_RIGHT = -24
local SCROLL_BOTTOM = 4

local DROPDOWN_WIDTH = 220
local SLIDER_WIDTH = 250
local NUMBER_BOX_WIDTH = 52

-- The preview is the bar at its real size, up to what fits in its row.
local PREVIEW_ROW_HEIGHT = 34
local PREVIEW_MAX_WIDTH = 300
local PREVIEW_MAX_HEIGHT = 30

local page            -- the canvas frame, built at login
local content         -- the scrolling part of the page, under the header
local categoryID      -- what Settings.OpenToCategory takes
local combatWaiter    -- opens the page once combat ends
local controls = {}   -- what RefreshPage keeps in step with the settings
local refreshing = false -- true while RefreshPage sets controls, so they do not call back

--------------------------------------------------------------------------------
-- Building blocks
--------------------------------------------------------------------------------

local nextY -- where the next row goes, walking down the scrolling part

local function NextRow(height)
    local row = CreateFrame("Frame", nil, content)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, nextY)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, nextY)
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

local function WholeNumber(value)
    return ("%d"):format(math.floor(value + 0.5))
end

-- The client's stepper slider, whole numbers only, with the value on its
-- right unless a NumberBox shows it there instead. Its change callback is the
-- one Baganator reads on Forever.
local function Slider(row, minimum, maximum, onChange, withBox)
    local slider = CreateFrame("Slider", nil, row, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("LEFT", row, "CENTER", CONTROL_X, 0)
    slider:SetWidth(SLIDER_WIDTH)
    slider:SetHeight(20)
    slider:Init(minimum, minimum, maximum, maximum - minimum, not withBox and {
        [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(
            MinimalSliderWithSteppersMixin.Label.Right, WholeNumber),
    } or nil)
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if refreshing then return end
        onChange(math.floor(value + 0.5))
    end)
    return slider
end

-- A box on a slider's right for typing an exact number. Enter or clicking
-- away applies it, and the setter keeps it in range; Escape, or a box left
-- empty or not holding a number, puts the current value back. A signed box
-- takes a minus sign too, which a numeric box refuses.
local function NumberBox(row, slider, current, apply, signed)
    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetSize(NUMBER_BOX_WIDTH, 20)
    box:SetPoint("LEFT", slider, "RIGHT", 14, 0)
    box:SetAutoFocus(false)
    if not signed then box:SetNumeric(true) end
    box:SetMaxLetters(signed and 5 or 4)
    box:SetJustifyH("CENTER")
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self)
        self.cancelled = true
        self:ClearFocus()
    end)
    -- Hooked, so the template still clears its highlight.
    box:HookScript("OnEditFocusLost", function(self)
        local value = tonumber(self:GetText())
        if value and not self.cancelled then apply(value) end
        self.cancelled = false
        self:SetText(WholeNumber(current()))
    end)
    return box
end

-- Shows a value in a NumberBox, unless a number is being typed into it.
local function SetBoxValue(box, value)
    if not box:HasFocus() then box:SetText(WholeNumber(value)) end
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

    local level, current, max, loyalty, happiness, points = API.PreviewPet()
    preview.status:SetMinMaxValues(0, max > 0 and max or 1)
    preview.status:SetValue(math.min(current, max))
    preview.text:SetText(API.FormatText(db.textStyle, true, level, current, max,
        db.textLoyalty and loyalty or nil, db.textHappiness and happiness or nil,
        db.textTraining and points or nil))
end

local function RefreshPage()
    local db = API.GetDB()
    refreshing = true
    controls.lock:SetChecked(db.locked)
    controls.tooltip:SetChecked(db.showTooltip)
    controls.textLoyalty:SetChecked(db.textLoyalty)
    controls.textHappiness:SetChecked(db.textHappiness)
    controls.textTraining:SetChecked(db.textTraining)
    controls.width:SetValue(db.width)
    controls.height:SetValue(db.height)
    SetBoxValue(controls.widthBox, db.width)
    SetBoxValue(controls.heightBox, db.height)
    local x, y = API.BarPosition()
    controls.x:SetValue(x)
    controls.y:SetValue(y)
    SetBoxValue(controls.xBox, x)
    SetBoxValue(controls.yBox, y)
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

    -- The version beside the title, small and grey, when the toc names one.
    if API.Version then
        local version = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 2)
        version:SetTextColor(0.5, 0.5, 0.5)
        version:SetText(API.Version)
    end

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
    Tooltip(controls.lock, "A locked bar cannot be moved or resized, and hides while no pet is out. The game's Edit Mode can still move it.")

    controls.tooltip = Checkbox(Row("Show tooltip"), API.SetShowTooltip)
    Tooltip(controls.tooltip, "Hovering over the bar shows your pet's name, the experience it still needs, its loyalty, its happiness and its training points.")

    -- Drag the slider, or type the exact size into the box beside it.
    local function SetWidth(value) API.SetBarSize(value, API.GetDB().height) end
    local function SetHeight(value) API.SetBarSize(API.GetDB().width, value) end

    local widthRow = Row("Width")
    controls.width = Slider(widthRow, API.MIN_WIDTH, API.MaxWidth(), SetWidth, true)
    controls.widthBox = NumberBox(widthRow, controls.width, function() return API.GetDB().width end, SetWidth)
    Tooltip(controls.widthBox, ("Type a width from %d to %d, then press Enter."):format(
        API.MIN_WIDTH, math.floor(API.MaxWidth())))

    local heightRow = Row("Height")
    controls.height = Slider(heightRow, API.MIN_HEIGHT, API.MAX_HEIGHT, SetHeight, true)
    controls.heightBox = NumberBox(heightRow, controls.height, function() return API.GetDB().height end, SetHeight)
    Tooltip(controls.heightBox, ("Type a height from %d to %d, then press Enter."):format(
        API.MIN_HEIGHT, API.MAX_HEIGHT))

    -- Where the bar sits, from the centre of the screen, the same way.
    local function SetX(value) API.SetBarPosition(value, select(2, API.BarPosition())) end
    local function SetY(value) API.SetBarPosition((API.BarPosition()), value) end
    local rangeX, rangeY = API.PositionRange()

    local xRow = Row("X position")
    controls.x = Slider(xRow, -rangeX, rangeX, SetX, true)
    controls.xBox = NumberBox(xRow, controls.x, function() return (API.BarPosition()) end, SetX, true)
    Tooltip(controls.xBox, "How far right of the center of the screen the bar sits; below 0 is left of it. Type a number, then press Enter.")

    local yRow = Row("Y position")
    controls.y = Slider(yRow, -rangeY, rangeY, SetY, true)
    controls.yBox = NumberBox(yRow, controls.y, function() return select(2, API.BarPosition()) end, SetY, true)
    Tooltip(controls.yBox, "How far above the center of the screen the bar sits; below 0 is under it. Type a number, then press Enter.")

    local positionRow = Row("Position")
    local reset = CreateFrame("Button", nil, positionRow, "UIPanelButtonTemplate")
    reset:SetPoint("LEFT", positionRow, "CENTER", CONTROL_X, 0)
    reset:SetSize(160, 22)
    reset:SetText("Reset position")
    reset:SetScript("OnClick", function() API.ResetLayout() end)
    Tooltip(reset, "Puts the bar back below your character at its first size.")

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
    controls.textHappiness = Checkbox(Row("Happiness"), API.SetTextHappiness)
    Tooltip(controls.textHappiness, "Adds your pet's happiness after the text, for example Happy or Unhappy.")
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

    -- The rows scroll under the header in the client's own scroll frame,
    -- whose scroll bar shows only when the rows do not fit.
    local scroll = CreateFrame("ScrollFrame", nil, page, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -SCROLL_TOP)
    scroll:SetPoint("BOTTOMRIGHT", SCROLL_RIGHT, SCROLL_BOTTOM)
    if scroll.ScrollBar and scroll.ScrollBar.SetHideIfUnscrollable then
        scroll.ScrollBar:SetHideIfUnscrollable(true)
    end
    content = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(content)
    -- A scroll child takes no width from its scroll frame, so it is given it.
    scroll:HookScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    nextY = -10

    -- The bar itself is usually under the settings window, so the page shows
    -- its own copy, built the same way.
    local previewRow = Row("Preview", PREVIEW_ROW_HEIGHT)
    local preview = CreateFrame("Frame", nil, previewRow)
    preview:SetPoint("LEFT", previewRow, "CENTER", CONTROL_X, 0)
    API.BuildBarVisuals(preview)
    controls.preview = preview

    BuildBarSection()
    BuildTextSection()
    content:SetSize(scroll:GetWidth(), -nextY)

    page:SetScript("OnShow", function()
        content:SetWidth(scroll:GetWidth())
        RefreshPage()
    end)
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
