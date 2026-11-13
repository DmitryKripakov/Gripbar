-- The four paddle panels: creation, position, visibility, focus visuals and
-- appearance. Each panel is centred on its native crossbar bar.
local _, ns = ...

local PANEL_COUNT = ns.PANEL_COUNT
local PADDLE_COUNT = ns.PADDLE_COUNT
local LAYOUT = ns.LAYOUT
local ATLAS = ns.ATLAS
local NATIVE_CVAR_SCALING = ns.NATIVE_CVAR_SCALING
local NATIVE_CVAR_HIGHLIGHT = ns.NATIVE_CVAR_HIGHLIGHT
local PANELS = ns.PANELS
local panelFrames = ns.panelFrames
local buttons = ns.buttons
local focusRouting = ns.focusRouting
local SafeCall = ns.SafeCall
local ApplyArt = ns.ApplyArt
local GetNativeCVarBool = ns.GetNativeCVarBool
local DefaultPanelPosition = ns.DefaultPanelPosition
local ResolvePanelAnchor = ns.ResolvePanelAnchor
local UpdatePromptVisibility = ns.UpdatePromptVisibility
local GetButtonCenter = ns.GetButtonCenter
local GetPanelSize = ns.GetPanelSize
local LayoutButtonVisual = ns.LayoutButtonVisual
local CreateActionButton = ns.CreateActionButton
local GetVisualPanelFromGamepadState = ns.GetVisualPanelFromGamepadState

local lastVisualPanel
local lastCrossbarFocused

-- Mirrors GamepadMainActionBarFrameMixin:UpdateActionBarFocusedState: the
-- native crossbar collapses every bar while a binding set other than the core
-- gameplay one (game menu, bags, settings) owns the controller. Polled rather
-- than registered through BindToCoreBindingActive so no addon code runs inside
-- Blizzard's listener loop. Unknown counts as focused, as before.
local function IsNativeCrossbarFocused()
    local manager = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
    if type(manager) ~= "table" or type(manager.IsOnlyCoreBindingSetActive) ~= "function" then
        return true
    end
    return SafeCall(manager.IsOnlyCoreBindingSetActive, manager) ~= false
end

local function SetPanelPosition(panelIndex)
    local panel = panelFrames[panelIndex]
    if not panel then
        return
    end

    -- panels are always centred on their bar; there is no dragging
    -- (the slots are placed with the spread settings instead).
    local pos = DefaultPanelPosition(panelIndex)
    -- SetPoint offsets are in the panel's own (scaled) units, so
    -- the HUD scale would also pull the panel towards the anchor. Dividing by
    -- the scale keeps the panel centre on its bar; only the paddles around
    -- that centre shrink or grow.
    local point, relativeTo, relativePoint, x, y = ResolvePanelAnchor(pos)
    local scale = panel:GetScale() or 1
    if scale <= 0 then
        scale = 1
    end
    panel:ClearAllPoints()
    panel:SetPoint(point, relativeTo, relativePoint, (x or 0) / scale, (y or 0) / scale)
end

local function IsGamepadInterfaceActive()
    if C_InputInterfaceStyle and type(C_InputInterfaceStyle.GetCurrentStyle) == "function" then
        local style = SafeCall(C_InputInterfaceStyle.GetCurrentStyle)
        if style ~= nil then
            local gamepad = Enum and Enum.InputDeviceInterfaceType and Enum.InputDeviceInterfaceType.Gamepad or 1
            return style == gamepad
        end
    end
    if type(IsGamePadEnabled) == "function" then
        return SafeCall(IsGamePadEnabled) == true
    end
    return true
end

-- Hides the panels outside gamepad mode.
-- The panels parent secure action buttons, so showing or hiding them is a
-- protected action; in combat it waits for PLAYER_REGEN_ENABLED.
local function UpdatePanelVisibility()
    if InCombatLockdown() then
        ns.pendingAppearanceRefresh = true
        return
    end

    local shown = GripbarDB.gamepadOnly == false or IsGamepadInterfaceActive()
    for panelIndex = 1, PANEL_COUNT do
        local panel = panelFrames[panelIndex]
        if panel then
            panel:SetShown(shown)
        end
    end
end

-- the native crossbar fades the bars that are not in play (for
-- example while a bumper is held: after about a second every bar but the
-- top one fades out). Each panel copies the effective alpha of its native
-- bar (first d-pad button, so a fade on the button, the bar or the anchor
-- is all caught), relative to UIParent. Panels: 1 top, 2 left, 3 right,
-- 4 bottom, same order as the bars.
local NATIVE_FADE_ANCHORS = { "TopCenteredAnchor", "LeftCenteredAnchor", "RightCenteredAnchor", "BottomCenteredAnchor" }
local nativeFadeFrames

local function FindNativeFadeFrames()
    local pageUnit = _G.GamepadMainActionBarFramePageUnit
        or (_G.GamepadMainActionBarFrame and _G.GamepadMainActionBarFrame.PageUnit)
    if not pageUnit then
        return nil
    end
    local frames = {}
    for i, key in ipairs(NATIVE_FADE_ANCHORS) do
        local anchor = pageUnit[key]
        local bar = anchor and anchor.Bar
        local button = bar and bar.Left and bar.Left.ActionButton1
        frames[i] = button or bar or anchor
        if not frames[i] then
            return nil
        end
    end
    return frames
end

local function GetNativeFade(panelIndex)
    nativeFadeFrames = nativeFadeFrames or FindNativeFadeFrames()
    local frame = nativeFadeFrames and nativeFadeFrames[panelIndex]
    if not frame or type(frame.GetEffectiveAlpha) ~= "function" then
        return 1
    end
    local parentAlpha = UIParent:GetEffectiveAlpha()
    if not parentAlpha or parentAlpha <= 0 then
        parentAlpha = 1
    end
    return math.max(0, math.min(1, frame:GetEffectiveAlpha() / parentAlpha))
end

local function ApplyPanelAlpha(panel, force)
    local alpha = (panel.baseAlpha or 1) * GetNativeFade(panel.panelIndex)
    if force or not panel.appliedAlpha or math.abs(panel.appliedAlpha - alpha) > 0.004 then
        panel.appliedAlpha = alpha
        panel:SetAlpha(alpha)
    end
end

-- Every frame, from the state poller. SetAlpha is allowed in combat.
local function UpdateNativeFades()
    for panelIndex = 1, PANEL_COUNT do
        local panel = panelFrames[panelIndex]
        if panel then
            ApplyPanelAlpha(panel, false)
        end
    end
end

-- isActive: the panel's layer is selected by the triggers. isFocused: it is
-- selected and the native crossbar has gamepad focus, so it draws expanded.
local function SetPanelActiveVisual(panelIndex, isActive, crossbarFocused)
    local panel = panelFrames[panelIndex]
    if not panel then
        return
    end

    local scalingEnabled = GetNativeCVarBool(NATIVE_CVAR_SCALING, true)
    local highlightEnabled = GripbarDB.highlightActivePanel ~= false and GetNativeCVarBool(NATIVE_CVAR_HIGHLIGHT, true)
    local isFocused = isActive and crossbarFocused
    local expanded = isFocused and scalingEnabled
    local wasExpanded = panel.expanded == true

    panel.isActive = isActive
    panel.isFocused = isFocused
    panel.expanded = expanded

    local inactiveOpacity = GripbarDB.inactiveOpacity or 1.0
    panel.baseAlpha = isActive and 1 or inactiveOpacity
    ApplyPanelAlpha(panel, true)

    panel.focusBackground:SetAlpha(LAYOUT.FOCUS_BACKGROUND_ALPHA)
    panel.focusBackground:SetShown(isFocused and highlightEnabled and panel.focusBackground.artAvailable)

    if expanded and not wasExpanded then
        -- Native focus: the focus shadow starts fully opaque and settles to 0.4.
        panel.focusFadeStart = GetTime()
    elseif not expanded then
        panel.focusFadeStart = nil
    end

    for paddleIndex = 1, PADDLE_COUNT do
        local button = buttons[panelIndex][paddleIndex]
        if button then
            LayoutButtonVisual(button)
            if expanded and not wasExpanded then
                button.visual.shadowFocus:SetAlpha(1)
            end
            UpdatePromptVisibility(button)
        end
    end
end

local function UpdateFocusFades()
    local now = GetTime()
    for panelIndex = 1, PANEL_COUNT do
        local panel = panelFrames[panelIndex]
        if panel and panel.focusFadeStart then
            local progress = (now - panel.focusFadeStart) / LAYOUT.FOCUS_FADE_DURATION
            local alpha
            if progress >= 1 then
                alpha = LAYOUT.FOCUS_SHADOW_MIN_ALPHA
                panel.focusFadeStart = nil
            else
                alpha = 1 - ((1 - LAYOUT.FOCUS_SHADOW_MIN_ALPHA) * progress)
            end

            for paddleIndex = 1, PADDLE_COUNT do
                local button = buttons[panelIndex][paddleIndex]
                if button then
                    button.visual.shadowFocus:SetAlpha(alpha)
                end
            end
        end
    end
end

local function UpdatePanelVisualState(panelIndex, force)
    local crossbarFocused = IsNativeCrossbarFocused()
    if not force and lastVisualPanel == panelIndex and lastCrossbarFocused == crossbarFocused then
        return
    end

    lastVisualPanel = panelIndex
    lastCrossbarFocused = crossbarFocused
    for i = 1, PANEL_COUNT do
        SetPanelActiveVisual(i, i == panelIndex, crossbarFocused)
    end
end

-- sizes the panel to the paddle rectangle and puts the secure
-- click targets on their expanded spots. Protected, so out of combat only.
local function LayoutPanel(panelIndex)
    local panel = panelFrames[panelIndex]
    if not panel or InCombatLockdown() then
        return
    end
    local width, height = GetPanelSize()
    panel:SetSize(width, height)
    for paddleIndex = 1, PADDLE_COUNT do
        local button = buttons[panelIndex][paddleIndex]
        if button then
            local x, y = GetButtonCenter(paddleIndex, true)
            local size = LAYOUT.BUTTON_SIZE_EXPANDED * ns.GetHudScale()
            button:SetSize(size, size)
            button:ClearAllPoints()
            button:SetPoint("CENTER", panel, "CENTER", x, y)
        end
    end
end

local function CreatePanelFrame(panelIndex)
    local panel = CreateFrame("Frame", "GripbarPanel" .. panelIndex, UIParent)
    panel.panelIndex = panelIndex
    panel.expanded = false
    panel:SetSize(LAYOUT.PANEL_WIDTH, LAYOUT.PANEL_HEIGHT)
    panel:SetFrameStrata("LOW")
    -- The panels nest inside the native crossbar; keep them above its slots so
    -- an expanded paddle grid never disappears behind a native ring.
    panel:SetFrameLevel(40)
    -- not clamped. The LT + RT panel is centred on the bottom bar,
    -- close to the screen edge, and clamping pushed it up off its bar.
    panel:SetClampedToScreen(false)
    -- Registered before the slots are created so their first layout pass works.
    panelFrames[panelIndex] = panel

    -- Soft highlight the native crossbar draws behind the focused bar.
    panel.focusBackground = panel:CreateTexture(nil, "BACKGROUND", nil, -2)
    panel.focusBackground:SetSize(LAYOUT.FOCUS_BACKGROUND_WIDTH, LAYOUT.FOCUS_BACKGROUND_HEIGHT)
    panel.focusBackground:SetPoint("CENTER", panel, "CENTER", 0, LAYOUT.GRID_CENTER_Y)
    if not ApplyArt(panel.focusBackground, ATLAS.focusBackground, nil) then
        panel.focusBackground:SetColorTexture(0.68, 0.45, 0.08, 0.6)
        panel.focusBackground:SetSize(LAYOUT.PANEL_WIDTH - 20, LAYOUT.PANEL_WIDTH - 20)
        panel.focusBackground.artAvailable = true
    end
    panel.focusBackground:Hide()

    for paddleIndex = 1, PADDLE_COUNT do
        local button = CreateActionButton(panelIndex, paddleIndex, panel)
        local x, y = GetButtonCenter(paddleIndex, true)
        button:SetPoint("CENTER", panel, "CENTER", x, y)
    end

    SetPanelPosition(panelIndex)
    LayoutPanel(panelIndex)
    return panel
end

local function CreateUI()
    focusRouting.CreateRouters()
    for panelIndex = 1, PANEL_COUNT do
        buttons[panelIndex] = {}
        CreatePanelFrame(panelIndex)
    end

    UpdatePanelVisualState(1, true)
    UpdatePanelVisibility()
end

local function ApplyAppearance()
    if not panelFrames[1] then
        return
    end

    if InCombatLockdown() then
        ns.pendingAppearanceRefresh = true
        return
    end

    -- panels stay at scale 1; the HUD scale is applied per slot in
    -- LayoutButtonVisual / LayoutPanel, so every paddle keeps its position.
    for panelIndex = 1, PANEL_COUNT do
        local panel = panelFrames[panelIndex]
        if panel then
            panel:SetScale(1)
            SetPanelPosition(panelIndex)
            LayoutPanel(panelIndex)
        end
    end

    UpdatePanelVisualState(GetVisualPanelFromGamepadState(), true)
    UpdatePanelVisibility()
    if ns.ApplyBadgeOffsets then
        ns.ApplyBadgeOffsets()
    end
    ns.pendingAppearanceRefresh = false
end

ns.SetPanelPosition = SetPanelPosition
ns.IsGamepadInterfaceActive = IsGamepadInterfaceActive
ns.UpdatePanelVisibility = UpdatePanelVisibility
ns.UpdateFocusFades = UpdateFocusFades
ns.UpdateNativeFades = UpdateNativeFades
ns.UpdatePanelVisualState = UpdatePanelVisualState
ns.IsNativeCrossbarFocused = IsNativeCrossbarFocused
ns.CreateUI = CreateUI
ns.ApplyAppearance = ApplyAppearance
