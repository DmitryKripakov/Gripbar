-- Paddles that page the native crossbar instead of firing a Gripbar slot.
-- Each paddle has a behavior: its Paddle actions (the default), or the
-- previous or next crossbar page.
--
-- The gamepad crossbar keeps its own page (GamepadMainActionBarFrame.PageUnit),
-- so the secure "actionbar" action type does not page it. Worse, that type
-- changes C_ActionBar's page, and every crossbar button fires its storage slot
-- plus 12 per action-bar page past the first (SecureActionButtonMixin:
-- CalculateAction; the buttons set no actionpage), which shifts the whole
-- crossbar by one bar per page. Never page with "actionbar" here. The only
-- secure way to page the crossbar is the page tracker's ChangePageButton,
-- which steps forward on LeftButton and back on RightButton;
-- the native D-pad shortcuts and LB + RB chord go through it too. A hidden
-- secure step button hands a click to it, and navigation paddles (and their
-- slots) run a macro that /clicks the step button, so paging stays untainted
-- and works in combat. The crossbar has no secure way to jump to an absolute
-- page. After every page change a single page number flashes above the
-- crossbar and fades out.
--
-- The special page S holds the pet / possess bar when the possess bar is set
-- to its own page. The paddles skip it: past the last standard page they step
-- back to page 1 instead (and from page 1 back to the last page), decided in
-- restricted code at the press, so it works in combat too.
local _, ns = ...

local PADDLE_COUNT = ns.PADDLE_COUNT
local SafeCall = ns.SafeCall

-- Every behavior in the order the settings button steps through them. The
-- icons are the arrows the native D-pad shortcuts bar uses for the same paging.
local BEHAVIORS = {
    { value = "action", label = "Paddle actions", short = "actions" },
    { value = "previous", label = "Previous crossbar page", short = "previous page", icon = "Interface\\Icons\\Misc_arrowleft", direction = "prev" },
    { value = "next", label = "Next crossbar page", short = "next page", icon = "Interface\\Icons\\Misc_arrowright", direction = "next" },
}

local behaviorByValue = {}
for _, behavior in ipairs(BEHAVIORS) do
    behaviorByValue[behavior.value] = behavior
end

local function GetPageUnit()
    local frame = _G.GamepadMainActionBarFrame
    return _G.GamepadMainActionBarFramePageUnit or (frame and frame.PageUnit)
end

local function GetChangePageButton()
    local pageUnit = GetPageUnit()
    return pageUnit and pageUnit.PageTracker and pageUnit.PageTracker.ChangePageButton
end

-- The one button that pages: "/click GripbarPageStep LeftButton" steps
-- forward, RightButton back. /click sends a release, so it acts on release.
local stepButton = CreateFrame("Button", "GripbarPageStep", UIParent, "SecureActionButtonTemplate")
stepButton:SetSize(1, 1)
stepButton:SetAlpha(0)
stepButton:EnableMouse(false)
stepButton:RegisterForClicks("AnyUp", "AnyDown")
stepButton:SetAttribute("useOnKeyDown", false)
stepButton:SetAttribute("type", "click")

-- Attached once the crossbar exists, always out of combat.
local function AttachChangePageButton()
    if InCombatLockdown() then
        return
    end
    local changePageButton = GetChangePageButton()
    if stepButton:GetAttribute("clickbutton") ~= changePageButton then
        stepButton:SetAttribute("clickbutton", changePageButton)
    end
end

-- Runs before every click of a paging button (pagedir set) and writes its
-- macro: one step, or, where the next step could land on the special page,
-- enough steps the other way round to wrap past it. The current page comes
-- from the ID of the top bar's first button, which the crossbar switches per
-- page (and leaves alone on the special page), and whether the special page
-- is showing from the possess bar's visibility. Both are protected frames,
-- readable here in combat. The nav* values are set by ConfigurePageSkip.
local NAV_PRECLICK = [[
    local dir = self:GetAttribute("pagedir")
    if not dir then
        return
    end
    local step = dir == "prev" and "RightButton" or "LeftButton"
    local count = 1
    if navReady and not navPossess:IsVisible() then
        local id = navTop:GetID()
        if dir == "next" and id == navLastId then
            step, count = "RightButton", navPages - 1
        elseif dir == "prev" and id == navFirstId then
            step, count = "LeftButton", navPages - 1
        end
    end
    local text = "/click GripbarPageStep " .. step
    for i = 2, count do
        text = text .. "\n/click GripbarPageStep " .. step
    end
    self:SetAttribute("macrotext", text)
]]

local navHeader = CreateFrame("Frame", "GripbarPageNavHeader", UIParent, "SecureHandlerBaseTemplate")
local wrapped = {}

-- Makes a secure action button page in a direction ("next" or "prev"), or
-- stop paging with nil; the caller then sets the button's own type again.
-- Out of combat only, like every secure attribute change.
local function SetPagingButton(button, direction)
    if direction then
        AttachChangePageButton()
        if not wrapped[button] then
            navHeader:WrapScript(button, "OnClick", NAV_PRECLICK)
            wrapped[button] = true
        end
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", "/click GripbarPageStep "
            .. (direction == "prev" and "RightButton" or "LeftButton"))
    end
    button:SetAttribute("pagedir", direction)
end

-- One hidden secure target per navigation behavior, for the paddle bindings.
-- Like the slot buttons they act on the press, not again on release.
local targets = {}
for _, behavior in ipairs(BEHAVIORS) do
    if behavior.direction then
        -- GripbarPagePrevious and GripbarPageNext.
        local name = "GripbarPage" .. behavior.value:gsub("^%l", string.upper)
        local target = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
        target:SetSize(1, 1)
        target:SetAlpha(0)
        target:EnableMouse(false)
        target:RegisterForClicks("AnyUp", "AnyDown")
        target:SetAttribute("useOnKeyDown", true)
        target.direction = behavior.direction
        targets[behavior.value] = target
    end
end

-- The top bar's first button: its ID is the action storage slot it shows,
-- which changes with the page.
local function GetTopBarButton(pageUnit)
    local bar = pageUnit.actionBars and pageUnit.actionBars.topBar
    local button = bar and bar.GetActionButtonByIndex and bar:GetActionButtonByIndex(1)
    if button and SafeCall(button.IsProtected, button) then
        return button
    end
    return nil
end

-- The possess bar, visible while the special page is (when it lives there),
-- or its first button when the bar itself is not protected.
local function GetPossessBar(pageUnit)
    local bar = pageUnit.actionBars and pageUnit.actionBars.possessBar
    if not bar then
        return nil
    end
    if SafeCall(bar.IsProtected, bar) then
        return bar
    end
    local button = bar.GetActionButtonByIndex and bar:GetActionButtonByIndex(1)
    if button and SafeCall(button.IsProtected, button) then
        return button
    end
    return nil
end

-- Hands the restricted code what it needs to skip the special page. That is
-- only needed while the possess bar is set to its own page; otherwise the
-- crossbar never stops there. Out of combat; rerun after combat and when the
-- possess bar setting changes.
local pageSkipState = "not set up"
local function ConfigurePageSkip()
    if InCombatLockdown() then
        return
    end
    local pageUnit = GetPageUnit()
    local util = _G.GamepadActionBarBindingUtil
    local constants = Constants and Constants.GamepadActionBarConstants
    local possessEnum = Enum and Enum.GamepadPossessBarOverride
    local topButton = pageUnit and GetTopBarButton(pageUnit)
    local possessBar = pageUnit and GetPossessBar(pageUnit)
    local pages = constants and constants.NUM_STANDARD_PAGES_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT
    local onSpecialPage = possessEnum ~= nil
        and tonumber(GetCVar("GamepadPossessBarOverride")) == possessEnum.SpecialPageTopBar

    local firstId, lastId
    if util and topButton and topButton.pageUnitSlotID and type(pages) == "number" and pages > 1 then
        firstId = SafeCall(util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID, 1, topButton.pageUnitSlotID)
        lastId = SafeCall(util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID, pages, topButton.pageUnitSlotID)
    end

    local ready = onSpecialPage and possessBar ~= nil and firstId ~= nil and lastId ~= nil
    if not onSpecialPage then
        pageSkipState = "not needed"
    elseif ready then
        pageSkipState = "on"
    else
        pageSkipState = "unavailable"
    end

    if ready then
        navHeader:SetFrameRef("navTop", topButton)
        navHeader:SetFrameRef("navPossess", possessBar)
    end
    navHeader:SetAttribute("navReady", ready)
    navHeader:SetAttribute("navFirstId", firstId)
    navHeader:SetAttribute("navLastId", lastId)
    navHeader:SetAttribute("navPages", pages)
    navHeader:Execute([[
        navReady = self:GetAttribute("navReady") and true or false
        navTop = navReady and self:GetFrameRef("navTop") or nil
        navPossess = navReady and self:GetFrameRef("navPossess") or nil
        navFirstId = self:GetAttribute("navFirstId")
        navLastId = self:GetAttribute("navLastId")
        navPages = self:GetAttribute("navPages")
        navReady = navReady and navTop ~= nil and navPossess ~= nil
    ]])
end

-- The crossbar's current page as a label: a number, or S for the
-- special (possess / vehicle) page. nil when the crossbar is missing.
local function GetCrossbarPageLabel()
    local pageUnit = GetPageUnit()
    local page = pageUnit and SafeCall(pageUnit.GetCurrentPage, pageUnit)
    if not page then
        return nil
    end
    local constants = Constants and Constants.GamepadActionBarConstants
    if constants and page == constants.GAMEPAD_ACTION_BAR_PAGE_UNIT_SPECIAL_PAGE_INDEX then
        return "S"
    end
    return tostring(page)
end

-- paddle actions per crossbar page.
--
-- Each slot button carries one native storage slot per page ("action-page1"
-- .. "action-pageN"). Right before every click a restricted snippet reads the
-- crossbar's current page from the ID of the top bar's first button (the same
-- protected signal the page skip uses, readable in combat) and points the
-- button's "action" at that page's slot. The routers (focus routing) get the
-- same treatment for their per-panel copies. Out of combat the attributes are
-- also kept in sync on every page change, and the icons follow the page.
local pageHeader = CreateFrame("Frame", "GripbarPageHeader", UIParent, "SecureHandlerBaseTemplate")
local pageTrackingState = "not set up"
local pageWrapped = {}

local SLOT_PAGE_PRECLICK = [[
    if not pageReady or self:GetAttribute("type") ~= "action" then
        return
    end
    local id = pageTop:GetID()
    for p = 1, pageCount do
        if pageIds[p] == id then
            local slot = self:GetAttribute("action-page" .. p)
            if slot then
                self:SetAttribute("action", slot)
            end
            return
        end
    end
]]

local ROUTER_PAGE_PRECLICK = [[
    if not pageReady then
        return
    end
    local id = pageTop:GetID()
    local page
    for p = 1, pageCount do
        if pageIds[p] == id then
            page = p
            break
        end
    end
    if not page then
        return
    end
    for n = 1, 4 do
        if self:GetAttribute("*type-panel" .. n) == "action" then
            local slot = self:GetAttribute("pageslot-panel" .. n .. "-page" .. page)
            if slot then
                self:SetAttribute("*action-panel" .. n, slot)
            end
        end
    end
]]

local function WrapPagedButton(button)
    if pageWrapped[button] or InCombatLockdown() then
        return
    end
    pageHeader:WrapScript(button, "OnClick", SLOT_PAGE_PRECLICK)
    pageWrapped[button] = true
end

local function WrapPagedRouter(router)
    if pageWrapped[router] or InCombatLockdown() then
        return
    end
    pageHeader:WrapScript(router, "OnClick", ROUTER_PAGE_PRECLICK)
    pageWrapped[router] = true
end

-- Hands the restricted code the top bar button and the slot ID it shows on
-- each standard page. Out of combat.
local function ConfigurePageTracking()
    if InCombatLockdown() then
        return
    end
    local pageUnit = GetPageUnit()
    local util = _G.GamepadActionBarBindingUtil
    local topButton = pageUnit and GetTopBarButton(pageUnit)
    local count = ns.pageCount or 1
    local ids = {}
    local ready = count > 1 and topButton ~= nil and util ~= nil and topButton.pageUnitSlotID ~= nil
    if ready then
        for p = 1, count do
            ids[p] = SafeCall(util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID, p, topButton.pageUnitSlotID)
            if type(ids[p]) ~= "number" then
                ready = false
            end
        end
    end

    if ready then
        pageHeader:SetFrameRef("pageTop", topButton)
    end
    pageHeader:SetAttribute("pageReady", ready)
    pageHeader:SetAttribute("pageCount", count)
    for p = 1, count do
        pageHeader:SetAttribute("pageId" .. p, ids[p])
    end
    pageHeader:Execute([[
        pageReady = self:GetAttribute("pageReady") and true or false
        pageCount = tonumber(self:GetAttribute("pageCount")) or 1
        pageTop = pageReady and self:GetFrameRef("pageTop") or nil
        pageIds = newtable()
        for p = 1, pageCount do
            pageIds[p] = self:GetAttribute("pageId" .. p)
        end
        pageReady = pageReady and pageTop ~= nil
    ]])

    if count <= 1 then
        pageTrackingState = "off (" .. tostring(ns.nativePageStatus or "1 page") .. ")"
    elseif ready then
        pageTrackingState = string.format("on, %d pages", count)
    else
        pageTrackingState = "unavailable (crossbar page signal not found)"
    end
end

-- The current standard crossbar page (1..pageCount). The special page and
-- unknown states keep the last standard page.
local function GetCurrentPaddlePage()
    local pageUnit = GetPageUnit()
    local page = pageUnit and SafeCall(pageUnit.GetCurrentPage, pageUnit)
    local constants = Constants and Constants.GamepadActionBarConstants
    if type(page) ~= "number"
        or (constants and page == constants.GAMEPAD_ACTION_BAR_PAGE_UNIT_SPECIAL_PAGE_INDEX)
        or page < 1 or page > (ns.pageCount or 1) then
        return ns.currentPage or 1
    end
    return page
end

local function SyncCurrentPage(force)
    local page = GetCurrentPaddlePage()
    if force or page ~= ns.currentPage then
        ns.currentPage = page
        if ns.ApplyCurrentPage then
            ns.ApplyCurrentPage()
        end
    end
end

-- Page indicator: one slot in the native page tracker's style, where that
-- tracker appears while LB is held, shown on a page change and faded out.
local INDICATOR_HOLD = 1.0
local INDICATOR_FADE = 0.5

local indicator

local function SetAtlasIfPresent(texture, atlas)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas)
        return true
    end
    return false
end

local function CreatePageIndicator(pageUnit)
    local frame = CreateFrame("Frame", "GripbarPageIndicator", UIParent)
    frame:SetSize(40, 40)
    frame:SetFrameStrata("HIGH")
    frame:SetPoint("BOTTOM", pageUnit.TopCenteredAnchor or pageUnit, "TOP", 0, 20)
    frame:EnableMouse(false)
    frame:Hide()

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    if not SetAtlasIfPresent(background, "gamepad-actionbar-slot-bg-empty") then
        background:SetColorTexture(0, 0, 0, 0.6)
    end
    local border = frame:CreateTexture(nil, "ARTWORK")
    border:SetAllPoints()
    if not SetAtlasIfPresent(border, "gamepad-actionbar-slot-frame-select") then
        border:Hide()
    end

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    frame.text:SetPoint("CENTER")

    frame.fade = frame:CreateAnimationGroup()
    local alpha = frame.fade:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0)
    alpha:SetStartDelay(INDICATOR_HOLD)
    alpha:SetDuration(INDICATOR_FADE)
    frame.fade:SetScript("OnFinished", function()
        frame:Hide()
    end)
    return frame
end

local lastPage
local function ShowPageIndicator()
    local pageUnit = GetPageUnit()
    local label = GetCrossbarPageLabel()
    -- SetCurrentPage returns early for the page already shown.
    if not pageUnit or not label or label == lastPage then
        return
    end
    lastPage = label
    -- While LB is held the native tracker already shows the page.
    if not pageUnit:IsVisible() or (pageUnit.PageTracker and pageUnit.PageTracker:IsShown()) then
        return
    end

    indicator = indicator or CreatePageIndicator(pageUnit)
    indicator:SetScale(pageUnit:GetEffectiveScale() / UIParent:GetEffectiveScale())
    indicator.text:SetText(label)
    indicator.fade:Stop()
    indicator:SetAlpha(1)
    indicator:Show()
    indicator.fade:Play()
end

-- Every page change, from a paddle or the native chord, goes through
-- SetCurrentPage. A post-hook keeps the Blizzard call path untainted.
local pageHooked = false
local function HookPageChanges()
    local pageUnit = GetPageUnit()
    if pageHooked or not pageUnit or type(pageUnit.SetCurrentPage) ~= "function" then
        return
    end
    lastPage = GetCrossbarPageLabel()
    hooksecurefunc(pageUnit, "SetCurrentPage", ShowPageIndicator)
    hooksecurefunc(pageUnit, "SetCurrentPage", function()
        SyncCurrentPage(false)
    end)
    pageHooked = true
end

HookPageChanges()
for _, target in pairs(targets) do
    SetPagingButton(target, target.direction)
end

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(hookFrame.RegisterEvent, hookFrame, "GAMEPAD_POSSESS_BAR_OVERRIDE_CHANGED")
hookFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        HookPageChanges()
        AttachChangePageButton()
    end
    ConfigurePageSkip()
    ConfigurePageTracking()
    SyncCurrentPage(event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED")
end)

local function GetPaddleBehavior(paddleIndex)
    local value = GripbarDB and GripbarDB.paddleBehaviors and GripbarDB.paddleBehaviors["P" .. paddleIndex]
    return behaviorByValue[value] or behaviorByValue.action
end

-- The secure button a navigation paddle clicks, or nil for Paddle actions.
local function GetPaddleNavigationTarget(paddleIndex)
    local target = targets[GetPaddleBehavior(paddleIndex).value]
    if target then
        AttachChangePageButton()
    end
    return target
end

-- Makes a slot button of a navigation paddle page like the paddle when it is
-- clicked (mouse or gamepad cursor), or stop paging for any other behavior.
-- Called after the slot's own secure action is set, which paging overrides.
local function ApplySlotNavigation(button, behavior)
    SetPagingButton(button, behavior and behavior.direction)
end

-- The icon drawn on the slots of a navigation paddle, or nil.
local function GetPaddleBehaviorIcon(paddleIndex)
    return GetPaddleBehavior(paddleIndex).icon
end

-- Accepts a behavior value or the friendlier names the slash command takes.
local BEHAVIOR_ALIASES = {
    actions = "action", slot = "action", slots = "action", paddle = "action",
    prev = "previous", back = "previous", ["<"] = "previous",
    forward = "next", [">"] = "next",
}

local function ParseBehavior(text)
    text = text and text:lower() or ""
    text = BEHAVIOR_ALIASES[text] or text
    return behaviorByValue[text] and text or nil
end

local function SetPaddleBehavior(paddleIndex, value)
    if not behaviorByValue[value] then
        return false
    end
    GripbarDB.paddleBehaviors["P" .. paddleIndex] = value
    -- Rebinds the keys and reconfigures the slot buttons (both deferred
    -- until after combat), and redraws the slots.
    ns.ApplyPaddleKeys(false)
    ns.RefreshButtons()
    return true
end

-- Steps to the next (or, with reverse, the previous) behavior.
local function CyclePaddleBehavior(paddleIndex, reverse)
    local current = GetPaddleBehavior(paddleIndex).value
    for index, behavior in ipairs(BEHAVIORS) do
        if behavior.value == current then
            local step = reverse and -1 or 1
            SetPaddleBehavior(paddleIndex, BEHAVIORS[(index - 1 + step) % #BEHAVIORS + 1].value)
            return
        end
    end
    SetPaddleBehavior(paddleIndex, "action")
end

local function GetPageNavigationDiagnostic()
    local parts = {}
    for paddleIndex = 1, PADDLE_COUNT do
        parts[#parts + 1] = string.format("P%d=%s", paddleIndex, GetPaddleBehavior(paddleIndex).short)
    end
    local delegate = stepButton:GetAttribute("clickbutton")
    return string.format("%s (crossbar page %s, page button %s, skip S page %s, paddle pages %s, paddle page %s)",
        table.concat(parts, "   "), tostring(GetCrossbarPageLabel()),
        delegate and delegate == GetChangePageButton() and "attached" or "missing",
        pageSkipState, pageTrackingState, tostring(ns.currentPage))
end

ns.GetPaddleBehavior = GetPaddleBehavior
ns.WrapPagedButton = WrapPagedButton
ns.WrapPagedRouter = WrapPagedRouter
ns.ConfigurePageTracking = ConfigurePageTracking
ns.SyncCurrentPage = SyncCurrentPage
ns.GetPaddleNavigationTarget = GetPaddleNavigationTarget
ns.ApplySlotNavigation = ApplySlotNavigation
ns.GetPaddleBehaviorIcon = GetPaddleBehaviorIcon
ns.GetCrossbarPageLabel = GetCrossbarPageLabel
ns.ParsePaddleBehavior = ParseBehavior
ns.SetPaddleBehavior = SetPaddleBehavior
ns.CyclePaddleBehavior = CyclePaddleBehavior
ns.GetPageNavigationDiagnostic = GetPageNavigationDiagnostic
