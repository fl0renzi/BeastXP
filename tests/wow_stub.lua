-- BeastXP - tests/wow_stub.lua
-- A minimal headless mock of the WoW client API surface the addon touches. It
-- runs under fengari (Lua 5.3), not the game: the point is to exercise the
-- addon's own logic, not Blizzard's. Anything game-side a test needs to
-- control lives behind a __ helper below. A widget method the addon calls that
-- is not defined here fails the test, the way a misspelled one fails in game.

-- Lua 5.1 compatibility the addon relies on.
unpack = unpack or table.unpack

--------------------------------------------------------------------------------
-- Secret values
--------------------------------------------------------------------------------

local secretRegistry = setmetatable({}, { __mode = "k" })

-- A stand-in for a secret value: any comparison or arithmetic on it errors.
local secretMeta = {
    __eq = function() error("attempt to compare a secret value") end,
    __lt = function() error("attempt to compare a secret value") end,
    __le = function() error("attempt to compare a secret value") end,
    __add = function() error("attempt to perform arithmetic on a secret value") end,
    __sub = function() error("attempt to perform arithmetic on a secret value") end,
    __div = function() error("attempt to perform arithmetic on a secret value") end,
    __concat = function() error("attempt to concatenate a secret value") end,
    __len = function() error("attempt to get length of a secret value") end,
}

function __secret()
    local secret = setmetatable({}, secretMeta)
    secretRegistry[secret] = true
    return secret
end

function issecretvalue(value)
    return secretRegistry[value] == true
end

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

local real_print = print
__print = real_print
__output = {}

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    __output[#__output + 1] = table.concat(parts, " ")
end

function __printed(fragment)
    for _, line in ipairs(__output) do
        if line:find(fragment, 1, true) then return true end
    end
    return false
end

function strtrim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- What the embedded libraries take from the client.
strmatch = string.match
bit = { band = function(a, b) return a & b end }
function getfenv() return _G end
function GetLocale() return "enUS" end
function securecallfunction(func, ...) return func(...) end

--------------------------------------------------------------------------------
-- Game state the tests drive
--------------------------------------------------------------------------------

-- Forever reports 16001. A test changes it to exercise the gate.
__interface = 16001
function GetBuildInfo() return "1.60.1", "69893", "Sep 18 2026", __interface end

__class = "HUNTER"
function UnitClass(unit)
    if unit == "player" then return "Hunter", __class, 3 end
end

-- nil when no pet is out, otherwise { current, max, level, name, hunter }.
__pet = nil

function HasPetUI()
    if not __pet then return false, false end
    return true, __pet.hunter ~= false
end

function GetPetExperience()
    if not __pet then return 0, 0 end
    return __pet.current, __pet.max
end

function UnitLevel(unit)
    if unit == "pet" and __pet then return __pet.level end
    return 0
end

function UnitName(unit)
    if unit == "pet" and __pet then return __pet.name end
    if unit == "player" then return "Tester" end
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

-- Font files the client cannot load. SetFont returns false for these and, as
-- the worst case, leaves the font string with no font at all.
__badFonts = {}

-- Texture files the client cannot load: setting one returns false.
__badTextures = {}

local methods = {}
local frames = {}

local function fontOf(object)
    return object and object.__font
end

function methods:SetPoint(...) self.__points[#self.__points + 1] = { ... } end
function methods:ClearAllPoints() self.__points = {} end
function methods:SetAllPoints() end
-- The last anchor, in the long form the game reports: SetPoint("TOP", 0, -4)
-- comes back relative to the parent, at the same point.
function methods:GetPoint()
    local point = self.__points[#self.__points]
    if not point then return nil end
    if type(point[2]) == "table" then
        return point[1], point[2], point[3], point[4], point[5]
    end
    return point[1], self.__parent, point[1], point[2] or 0, point[3] or 0
end
function methods:SetSize(width, height) self.__width, self.__height = width, height end
function methods:SetWidth(width) self.__width = width end
function methods:SetHeight(height) self.__height = height end
function methods:GetWidth() return self.__width or 0 end
function methods:GetHeight() return self.__height or 0 end
function methods:Show()
    local was = self.__shown
    self.__shown = true
    if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
end
-- Visibility through the parents, as the game reports it.
function methods:IsVisible()
    local widget = self
    while widget do
        if not widget.__shown then return false end
        widget = widget.__parent
    end
    return true
end
function methods:Hide()
    local was = self.__shown
    self.__shown = false
    if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
end
function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
function methods:IsShown() return self.__shown end
function methods:SetScript(name, handler) self.__scripts[name] = handler end
function methods:GetScript(name) return self.__scripts[name] end
function methods:SetFrameStrata(strata) self.__strata = strata end
function methods:SetFrameLevel(level) self.__frameLevel = level end
function methods:GetFrameLevel() return self.__frameLevel or 1 end
function methods:SetClampedToScreen(clamped) self.__clamped = clamped end
function methods:SetMovable(movable) self.__movable = movable end
function methods:SetResizable(resizable) self.__resizable = resizable end
function methods:SetResizeBounds(minW, minH, maxW, maxH)
    self.__bounds = { minW, minH, maxW, maxH }
end
function methods:EnableMouse(enabled) self.__mouse = enabled end
function methods:RegisterForDrag(button) self.__drag = button end
function methods:StartMoving() self.__moving = true end
function methods:StartSizing(corner) self.__sizing = corner end
function methods:StopMovingOrSizing()
    self.__moving, self.__sizing = nil, nil
    self.__stopped = (self.__stopped or 0) + 1
end
function methods:CreateTexture() return __new_widget("Texture", self) end
function methods:CreateFontString(_, _, template)
    local fontString = __new_widget("FontString", self)
    if template then fontString:SetFontObject(_G[template]) end
    return fontString
end
function methods:RegisterEvent(event)
    if not __knownEvents[event] then
        error("Attempt to register unknown event \"" .. tostring(event) .. "\"")
    end
    self.__events[event] = true
end
function methods:UnregisterEvent(event) self.__events[event] = nil end
function methods:UnregisterAllEvents() self.__events = {} end

-- StatusBar. There are no backdrop methods: the bar has no border, and a call
-- to one fails the test.
function methods:SetStatusBarTexture(texture)
    if __badTextures[texture:lower()] then return false end
    self.__barTexture = texture
    return true
end
function methods:SetStatusBarColor(...) self.__barColor = { ... } end
function methods:SetMinMaxValues(minimum, maximum) self.__min, self.__max = minimum, maximum end
function methods:GetMinMaxValues() return self.__min, self.__max end
function methods:SetValue(value) self.__value = value end
function methods:GetValue() return self.__value end

-- Button
function methods:SetNormalTexture(texture) self.__normal = texture end
function methods:SetHighlightTexture(texture) self.__highlight = texture end
function methods:SetPushedTexture(texture) self.__pushed = texture end

-- Texture
function methods:SetTexture(texture)
    if __badTextures[texture:lower()] then return false end
    self.__texture = texture
    return true
end
function methods:SetColorTexture(...) self.__color = { ... } end
function methods:SetAtlas(atlas) self.__atlas = atlas; return true end

-- CheckButton
function methods:SetChecked(checked) self.__checked = checked and true or false end
function methods:GetChecked() return self.__checked or false end
function methods:SetVertexColor(...) self.__vertexColor = { ... } end

-- FontString
function methods:SetFontObject(object) self.__font = fontOf(object) and { unpack(fontOf(object)) } end
function methods:SetFont(path, size, flags)
    if type(flags) ~= "string" then error("SetFont: flags must be a string") end
    if __badFonts[path:lower()] then
        self.__font = nil
        return false
    end
    self.__font = { path, size, flags }
    return true
end
function methods:GetFont()
    if self.__font then return unpack(self.__font) end
end
function methods:SetText(text)
    if self.__kind == "FontString" and not self.__font then error("FontString:SetText(): Font not set") end
    self.__text = text
end
function methods:GetText() return self.__text end
function methods:SetJustifyH(justify) self.__justify = justify end
function methods:SetWordWrap(wrap) self.__wrap = wrap end

local widgetMeta = { __index = methods }

function __new_widget(kind, parent)
    local widget = setmetatable({
        __kind = kind,
        __parent = parent,
        __points = {},
        __scripts = {},
        __events = {},
        __shown = true,
    }, widgetMeta)
    frames[#frames + 1] = widget
    return widget
end

--------------------------------------------------------------------------------
-- Menus
--------------------------------------------------------------------------------
-- The client's menu descriptions, for the right-click menu and the settings
-- page's dropdowns alike. A generator runs against a tree the tests can read
-- and click through.

local description = {}
local descriptionMeta = { __index = description }

local function node(kind, text, a, b)
    return setmetatable({ kind = kind, text = text, a = a, b = b, children = {} }, descriptionMeta)
end

local function add(parent, child)
    parent.children[#parent.children + 1] = child
    return child
end

function description:CreateTitle(text) return add(self, node("title", text)) end
function description:CreateDivider() return add(self, node("divider")) end
function description:CreateButton(text, callback) return add(self, node("button", text, callback)) end
function description:CreateCheckbox(text, isSelected, setSelected)
    return add(self, node("checkbox", text, isSelected, setSelected))
end
function description:CreateRadio(text, isSelected, setSelected)
    return add(self, node("radio", text, isSelected, setSelected))
end
function description:SetScrollMode(extent) self.scroll = extent end

function __new_menu_root() return node("root") end

--------------------------------------------------------------------------------
-- Templates
--------------------------------------------------------------------------------
-- The client templates the settings page builds on, as far as the page uses
-- them. A template name the stub does not know fails the test.

MinimalSliderWithSteppersMixin = {
    Event = { OnValueChanged = "OnValueChanged" },
    Label = { Left = 1, Right = 2, Top = 3 },
}
function CreateMinimalSliderFormatter(_, formatter) return formatter end

local templates = {}

templates.BackdropTemplate = nil -- the bar has no border

templates.UICheckButtonTemplate = function() end
templates.UIPanelButtonTemplate = function() end

templates.ColorSwatchTemplate = function(frame)
    function frame:SetColorRGB(r, g, b) self.__swatch = { r, g, b } end
end

-- The settings dropdown: SetupMenu keeps the generator and generates at once,
-- GenerateMenu runs it again and shows the radio that is selected.
templates.WowStyle1DropdownTemplate = function(frame)
    function frame:SetupMenu(generator)
        self.__generator = generator
        self:GenerateMenu()
    end
    function frame:GenerateMenu()
        local root = node("root")
        self.__generator(self, root)
        self.__menuRoot = root
        self.__selectedText = nil
        for _, child in ipairs(root.children) do
            if child.kind == "radio" and child.a() then self.__selectedText = child.text end
        end
    end
    function frame:SetDefaultText(text) self.__defaultText = text end
end

-- The stepper slider: OnValueChanged fires when the value changes, whoever
-- changed it, the way the client's does.
templates.MinimalSliderWithSteppersTemplate = function(frame)
    frame.__callbacks = {}
    function frame:Init(value, minimum, maximum, steps, formatters)
        self.__sliderValue, self.__minValue, self.__maxValue = value, minimum, maximum
        self.__steps, self.__formatters = steps, formatters
    end
    function frame:RegisterCallback(event, func) self.__callbacks[event] = func end
    function frame:SetValue(value)
        value = math.max(self.__minValue, math.min(self.__maxValue, value))
        if value == self.__sliderValue then return end
        self.__sliderValue = value
        local callback = self.__callbacks[MinimalSliderWithSteppersMixin.Event.OnValueChanged]
        if callback then callback(nil, value) end
    end
    function frame:GetValue() return self.__sliderValue end
end

function CreateFrame(kind, name, parent, template)
    local frame = __new_widget(kind, parent)
    frame.__name = name
    frame.__template = template
    if template then
        local apply = templates[template]
        if not apply then error("CreateFrame: unknown template " .. tostring(template)) end
        apply(frame)
    end
    if name then _G[name] = frame end
    return frame
end

-- The widget a settings row holds: the row is found by its label, then the
-- child of that row made from the template (or of the kind, for no template).
function __control(label, template, kind)
    local row
    for _, widget in ipairs(frames) do
        if widget.__kind == "FontString" and widget.__text == label and widget.__parent ~= nil then
            row = widget.__parent
        end
    end
    if not row then error("no settings row labelled " .. tostring(label)) end
    for _, widget in ipairs(frames) do
        if widget.__parent == row and widget.__template == template and (not kind or widget.__kind == kind) then
            return widget
        end
    end
    error("no " .. tostring(template or kind) .. " in the row labelled " .. tostring(label))
end

-- Picks an entry in a settings dropdown the way the player would.
function __dropdown_pick(dropdown, text)
    dropdown:GenerateMenu()
    for _, child in ipairs(dropdown.__menuRoot.children) do
        if child.text == text then
            child.b()
            return
        end
    end
    error("no entry " .. tostring(text) .. " in the dropdown")
end

function __dropdown_text(dropdown)
    dropdown:GenerateMenu()
    return dropdown.__selectedText
end

-- The settings page, once registered.
function __settings_page()
    return __settingsCategory and __settingsCategory.frame
end

-- The button on the settings page with this text.
function __page_button(text)
    for _, widget in ipairs(frames) do
        if widget.__template == "UIPanelButtonTemplate" and widget.__text == text then return widget end
    end
    error("no button " .. tostring(text))
end

-- Calls a widget's script handler the way the game would.
function __script(widget, name, ...)
    local handler = widget.__scripts[name]
    if handler then return handler(widget, ...) end
end

function __fire(event, ...)
    for _, frame in ipairs(frames) do
        if frame.__events[event] then
            local handler = frame.__scripts.OnEvent
            if handler then handler(frame, event, ...) end
        end
    end
end

function __registered(event)
    for _, frame in ipairs(frames) do
        if frame.__events[event] then return true end
    end
    return false
end

function __frame_count() return #frames end

--------------------------------------------------------------------------------
-- Client globals
--------------------------------------------------------------------------------

local function resetGlobals()
    frames = {}
    UIParent = __new_widget("Frame")
    UIParent:SetSize(1920, 1080)

    GameFontHighlightSmall = { __font = { "Fonts\\FRIZQT__.TTF", 10, "" } }
    GameFontNormal = { __font = { "Fonts\\FRIZQT__.TTF", 12, "" } }
    GameFontHighlightLarge = { __font = { "Fonts\\FRIZQT__.TTF", 16, "" } }
    GameFontHighlightHuge = { __font = { "Fonts\\FRIZQT__.TTF", 20, "" } }

    -- The client's settings window: a canvas category per addon, opened by
    -- its ID, which shows the canvas frame.
    __settingsCategory, __settingsAddOn, __settingsOpened = nil, nil, nil
    Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            __settingsCategory = { frame = frame, name = name, ID = name }
            function __settingsCategory:GetID() return self.ID end
            return __settingsCategory
        end,
        RegisterAddOnCategory = function(category) __settingsAddOn = category end,
        OpenToCategory = function(id)
            __settingsOpened = id
            if __settingsCategory and __settingsCategory.ID == id then __settingsCategory.frame:Show() end
        end,
    }

    __inCombat = false
    function InCombatLockdown() return __inCombat end

    GameTooltip = __new_widget("GameTooltip")
    GameTooltip.__shown = false
    GameTooltip.__lines = {}
    function GameTooltip:SetOwner(owner) self.__owner = owner; self.__lines = {} end
    function GameTooltip:GetOwner() return self.__owner end
    function GameTooltip:AddLine(text) self.__lines[#self.__lines + 1] = text end
    function GameTooltip:AddDoubleLine(left, right) self.__lines[#self.__lines + 1] = left .. " | " .. right end
    function GameTooltip:Show() self.__shown = true end
    function GameTooltip:Hide() self.__shown = false; self.__owner = nil end

    -- The client's context menu.
    __menu = nil
    MenuUtil = {
        CreateContextMenu = function(owner, generator)
            local root = __new_menu_root()
            generator(owner, root)
            __menu = root
        end,
    }

    -- The client's colour picker, as Forever has it: set up with an info table,
    -- read back with GetColorRGB, then swatchFunc on a change and cancelFunc
    -- on Cancel.
    __picker = nil
    ColorPickerFrame = {
        SetupColorPickerAndShow = function(self, info)
            __picker = info
            self.__rgb = { info.r, info.g, info.b }
        end,
        GetColorRGB = function(self) return unpack(self.__rgb) end,
    }

    LibStub = nil
    SlashCmdList = {}
    SLASH_BEASTXP1, SLASH_BEASTXP2 = nil, nil
end

-- Finds a menu entry by its path of texts, for example ("Font", "Arial Narrow").
function __menu_item(...)
    local current = __menu
    for i = 1, select("#", ...) do
        local text = select(i, ...)
        local found
        for _, child in ipairs(current and current.children or {}) do
            if child.text == text then found = child end
        end
        current = found
    end
    return current
end

-- Clicks a menu entry the way the client would.
function __menu_click(item)
    if item.kind == "button" then
        if item.a then item.a() end
    else
        item.b()
    end
end

function __menu_selected(item)
    return item.a() and true or false
end

-- Drags the open colour picker to a colour, as the player would.
function __picker_drag(r, g, b)
    ColorPickerFrame.__rgb = { r, g, b }
    __picker.swatchFunc()
end

function __picker_cancel()
    __picker.cancelFunc()
end

--------------------------------------------------------------------------------
-- Loading the addon
--------------------------------------------------------------------------------

-- The events this client knows. A test removes one to check that a missing
-- event does not stop the addon.
local DEFAULT_EVENTS = {
    "PLAYER_LOGIN", "UNIT_PET", "UNIT_PET_EXPERIENCE", "UNIT_LEVEL",
    "PET_UI_UPDATE", "PLAYER_XP_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
}

-- Starts a fresh session: a clean world, the given saved settings, every file
-- the .toc lists loaded in order as the game loads them (noLibs leaves out the
-- embedded libraries), and (unless told not to) PLAYER_LOGIN fired. Returns
-- the addon's namespace.
function __boot(options)
    options = options or {}
    resetGlobals()

    __output = {}
    __interface = options.interface or 16001
    __class = options.class or "HUNTER"
    __pet = options.pet
    __badFonts = {}
    __badTextures = {}
    for _, path in ipairs(options.badTextures or {}) do __badTextures[path:lower()] = true end
    __knownEvents = {}
    for _, event in ipairs(DEFAULT_EVENTS) do __knownEvents[event] = true end
    for _, event in ipairs(options.missingEvents or {}) do __knownEvents[event] = nil end
    BeastXPDB = options.db
    BeastXPBar = nil
    if options.noSettings then Settings = nil end

    local ns = {}
    for _, entry in ipairs(__toc_files) do
        if not (options.noLibs and entry.file:find("^Libs")) then
            local chunk, err = load(entry.source, "=" .. entry.file)
            if not chunk then error(err) end
            chunk("BeastXP", ns)
        end
    end

    if options.login ~= false then __fire("PLAYER_LOGIN") end
    return ns
end
