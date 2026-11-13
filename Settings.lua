-- The addon's page in the game's Settings window
local _, ns = ...

local PADDLE_COUNT = ns.PADDLE_COUNT
local Print = ns.Print
local GetPaddleKey = ns.GetPaddleKey
local GetKeyDisplayName = ns.GetKeyDisplayName
local UpdatePanelVisibility = ns.UpdatePanelVisibility
local StartKeyCapture = ns.StartKeyCapture
local ToggleGuideFrame = ns.ToggleGuideFrame
local ApplyAppearance = ns.ApplyAppearance
local ShowDiagnosticsFrame = ns.ShowDiagnosticsFrame
local GetProfileSetting = ns.GetProfileSetting
local GetProfileChoiceLabel = ns.GetProfileChoiceLabel
local CycleControllerProfileSetting = ns.CycleControllerProfileSetting
local GetPaddleBehavior = ns.GetPaddleBehavior
local CyclePaddleBehavior = ns.CyclePaddleBehavior

-- Everything lives on one canvas page built from plain widgets. Forever's
-- vertical-layout settings list hangs the client when the Settings window is
-- closed in gamepad mode after that page was shown (canvas pages such as
-- ChattyLittleNpc's do not), and its subcategories crash the gamepad
-- smart-navigation cursor (ScrollUtil.lua IsSelected on a released list button).
local function RegisterSettings()
    if ns.settingsRegistered or not Settings or type(Settings.RegisterCanvasLayoutCategory) ~= "function" then
        return
    end

    ns.settingsRegistered = true

    -- Hidden until the Settings window displays it, so OnShow always fires.
    local panel = CreateFrame("Frame")
    panel.name = "Gripbar"
    panel:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(560, 1)
    scrollFrame:SetScrollChild(content)

    -- Each control registers a function that reloads it from GripbarDB.
    local refreshers = {}
    local y = -6
    local sliderCount = 0

    local note = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 6, y)
    note:SetWidth(540)
    note:SetJustifyH("LEFT")
    note:SetText("With a controller, use the mouse on this page. The gamepad cursor cannot enter it without freezing Forever when Settings is closed. Paddle keys, lock/unlock and reset also work through /grip.")
    y = y - 34

    local function AttachTooltip(control, label, tooltip)
        control:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        control:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    local function AddSection(label)
        y = y - 12
        local header = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", 6, y)
        header:SetText(label)
        y = y - 26
    end

    local checkboxPairTop
    local function AddCheckbox(key, label, tooltip, onChange, column)
        local checkbox = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        local x, top = 14, y
        if column == "left" then
            checkboxPairTop = y
        elseif column == "right" and checkboxPairTop then
            x, top = 290, checkboxPairTop
        end
        checkbox:SetPoint("TOPLEFT", x, top)
        checkbox.Text:SetText(label)
        checkbox:SetScript("OnClick", function(self)
            GripbarDB[key] = self:GetChecked() and true or false
            onChange(GripbarDB[key])
        end)
        AttachTooltip(checkbox, label, tooltip)
        table.insert(refreshers, function()
            checkbox:SetChecked(GripbarDB[key] == true)
        end)
        if column == "left" then
            y = top - 30
        elseif column == "right" then
            y = top - 30
            checkboxPairTop = nil
        else
            y = y - 30
        end
    end

    -- OptionsSliderTemplate needs a global name on Classic-derived clients.
    -- column = "left" / "right" puts two sliders side by side
    -- (the left one starts the row, the right one closes it).
    local pairTop
    local function AddSlider(key, label, minValue, maxValue, step, tooltip, column)
        sliderCount = sliderCount + 1
        local x, width = 22, 250
        local top = y
        if column == "left" then
            pairTop = y
            width = 240
        elseif column == "right" and pairTop then
            top = pairTop
            x, width = 296, 240
        end
        local sliderY = top - 16
        local slider = CreateFrame("Slider", "GripbarSettingsSlider" .. sliderCount, content, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", x, sliderY)
        slider:SetWidth(width)
        slider:SetMinMaxValues(minValue, maxValue)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        local numberFormat = step >= 1 and "%d" or "%.2f"
        if slider.Low then
            slider.Low:SetText(string.format(numberFormat, minValue))
        end
        if slider.High then
            slider.High:SetText(string.format(numberFormat, maxValue))
        end

        local function UpdateLabel(value)
            slider.Text:SetText(string.format("%s: " .. numberFormat, label, value))
        end

        slider:SetScript("OnValueChanged", function(_, value)
            value = math.floor(value / step + 0.5) * step
            UpdateLabel(value)
            -- Refreshing the page calls SetValue too; only real changes apply.
            if math.abs((tonumber(GripbarDB[key]) or 0) - value) > 0.001 then
                GripbarDB[key] = value
                ApplyAppearance()
            end
        end)
        AttachTooltip(slider, label, tooltip)
        table.insert(refreshers, function()
            local value = tonumber(GripbarDB[key]) or minValue
            slider:SetValue(value)
            UpdateLabel(value)
        end)
        if column == "left" then
            -- The right slider of the pair closes the row.
            y = top - 56
        elseif column == "right" then
            y = top - 56
            pairTop = nil
        else
            y = sliderY - 40
        end
    end

    local function AddSubheader(label)
        local text = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("TOPLEFT", 20, y - 4)
        text:SetText(label)
        y = y - 20
    end

    -- buttonText may be a function so the paddle rows can show the current key.
    local function AddButton(label, buttonText, onClick, tooltip)
        local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("TOPLEFT", 20, y - 5)
        -- label may be a function too (paddle names follow the profile).
        if type(label) == "function" then
            local getLabel = label
            label = getLabel()
            text:SetText(label)
            table.insert(refreshers, function()
                text:SetText(getLabel())
            end)
        else
            text:SetText(label)
        end

        local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        button:SetSize(180, 22)
        button:SetPoint("TOPLEFT", 250, y)
        button:SetScript("OnClick", onClick)
        AttachTooltip(button, label, tooltip)
        if type(buttonText) == "function" then
            table.insert(refreshers, function()
                button:SetText(buttonText())
            end)
        else
            button:SetText(buttonText)
        end
        y = y - 28
        return button
    end

    AddSection("Combat")

    AddCheckbox(
        "wandShoot",
        "Swap melee and wand (X / RB + X)",
        "With a wand in the ranged slot and a living enemy targeted, X shoots the wand and RB + X swings the melee weapon: the game's two are swapped. On a corpse, an NPC or an object X stays the game's own press; LT / RT + X still press that layer's crossbar X. Works on every client language. Turn off Improved Forever's \"Square shoots the wand\" if you use that addon. Also: /grip wand.",
        function()
            ns.ApplyWandShoot()
        end
    )

    AddSection("HUD")

    AddSlider("hudScale", "HUD scale", 0.65, 1.50, 0.05,
        "Resizes every paddle slot around its own centre; positions do not move. 1.00 matches the size of the native crossbar slots.", "left")
    AddSlider("inactiveOpacity", "Inactive panels opacity", 0.10, 1.0, 0.05,
        "Fades the three unfocused panels. The native crossbar does not fade unfocused bars, so 1.00 is the default.", "right")

    AddSubheader("Top row (L4 / R4)")
    AddSlider("spreadTopX", "Horizontal", 0, 200, 1,
        "Distance of the top paddle slots from the centre of their bar, left and right (collapsed units; the focused bar scales it by 1.25 from the bar centre). Also: /grip spread top <x> <y>.", "left")
    AddSlider("spreadTopY", "Vertical", 0, 200, 1,
        "How far above the centre of their bar the top paddle slots sit. Also: /grip spread top <x> <y>.", "right")

    AddSubheader("Bottom row (L5 / R5)")
    AddSlider("spreadBottomX", "Horizontal", 0, 200, 1,
        "Distance of the bottom paddle slots from the centre of their bar, left and right. Also: /grip spread bottom <x> <y>.", "left")
    AddSlider("spreadBottomY", "Vertical", 0, 200, 1,
        "How far below the centre of their bar the bottom paddle slots sit. Also: /grip spread bottom <x> <y>.", "right")

    AddSubheader("Native LT badge (left bar)")
    AddSlider("badge_lt_x", "Horizontal", -200, 200, 1,
        "Moves the native LT prompt under the left bar (crossbar units; 0 = where the game puts it). Also: /grip badge lt <x> <y>.", "left")
    AddSlider("badge_lt_y", "Vertical", -200, 200, 1,
        "Moves the native LT prompt under the left bar (crossbar units; 0 = where the game puts it). Also: /grip badge lt <x> <y>.", "right")

    AddSubheader("Native RT badge (right bar)")
    AddSlider("badge_rt_x", "Horizontal", -200, 200, 1,
        "Moves the native RT prompt under the right bar (crossbar units; 0 = where the game puts it). Also: /grip badge rt <x> <y>.", "left")
    AddSlider("badge_rt_y", "Vertical", -200, 200, 1,
        "Moves the native RT prompt under the right bar (crossbar units; 0 = where the game puts it). Also: /grip badge rt <x> <y>.", "right")

    AddSubheader("Native LT + RT badge (bottom bar)")
    AddSlider("badge_both_x", "Horizontal", -200, 200, 1,
        "Moves the native LT + RT prompt under the bottom bar (crossbar units; 0 = where the game puts it). Also: /grip badge both <x> <y>.", "left")
    AddSlider("badge_both_y", "Vertical", -200, 200, 1,
        "Moves the native LT + RT prompt under the bottom bar (crossbar units; 0 = where the game puts it). Also: /grip badge both <x> <y>.", "right")

    AddCheckbox("gamepadOnly", "Only show in gamepad mode",
        "Hides the paddle panels while the interface is in mouse and keyboard mode.",
        function()
            UpdatePanelVisibility()
        end, "left")
    AddCheckbox("highlightActivePanel", "Highlight focused panel",
        "Draws the native crossbar focus highlight behind the panel that is currently active. Off by default: the native bar under it already highlights.",
        function()
            ApplyAppearance()
        end, "right")

    AddSection("Paddles")

    AddButton(
        "Controller",
        function()
            return GetProfileChoiceLabel(GetProfileSetting())
        end,
        function()
            CycleControllerProfileSetting()
            ns.RefreshSettingsKeyRows()
        end,
        "Which paddle controller you use: it names the slots and draws their glyphs. Auto detects the Xbox Elite, DualSense Edge, Steam Controller and Razer pads when the game sees them. Click to step through Auto, Xbox Elite / Scuf (P1-P4), DualSense Edge (Fn L / Fn R on top, back buttons below), Steam Controller / Steam Deck (L4 / R4 / L5 / R5), Razer (M1-M4) and Generic (P1-P4); pick one manually when Steam Input, reWASD or a Bluetooth driver hides the real controller. Changing it never touches your paddle keys or actions."
    )

    -- One row per paddle: its input and what it does.
    local function AddTwoButtons(label, first, second)
        local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("TOPLEFT", 20, y - 5)
        local getLabel = type(label) == "function" and label or nil
        text:SetText(getLabel and getLabel() or label)
        if getLabel then
            table.insert(refreshers, function()
                text:SetText(getLabel())
            end)
        end
        for i, spec in ipairs({ first, second }) do
            local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            button:SetSize(spec.width or 140, 22)
            button:SetPoint("TOPLEFT", spec.x or (i == 1 and 180 or 330), y)
            button:SetScript("OnClick", spec.click)
            if spec.rightClick then
                button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            end
            AttachTooltip(button, spec.title or "", spec.tooltip)
            if type(spec.text) == "function" then
                table.insert(refreshers, function()
                    button:SetText(spec.text())
                end)
            else
                button:SetText(spec.text)
            end
        end
        y = y - 28
    end

    local inputHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    inputHeader:SetPoint("TOP", content, "TOPLEFT", 250, y)
    inputHeader:SetText("Input")
    local doesHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    doesHeader:SetPoint("TOP", content, "TOPLEFT", 400, y)
    doesHeader:SetText("Does (right-click: back)")
    y = y - 16

    for paddleIndex = 1, PADDLE_COUNT do
        AddTwoButtons(
            function()
                return "Paddle " .. ns.GetPaddleName(paddleIndex)
            end,
            {
                title = "Paddle input",
                text = function() return GetKeyDisplayName(GetPaddleKey(paddleIndex)) end,
                click = function() StartKeyCapture(paddleIndex, false) end,
                tooltip = "The input that triggers this paddle. Click it, then press the paddle to assign a new one.",
            },
            {
                title = "Paddle behavior",
                text = function() return GetPaddleBehavior(paddleIndex).label end,
                click = function(_, mouseButton) CyclePaddleBehavior(paddleIndex, mouseButton == "RightButton") end,
                rightClick = true,
                tooltip = "Paddle actions fires this paddle's slot on the BASE, LT, RT or LT + RT panel. The other choices turn the paddle into native crossbar paging instead, on every layer: previous page or next page. The slot actions are kept and come back when you switch back. Left-click steps forward, right-click steps back.",
            }
        )
    end

    AddTwoButtons(
        "Setup",
        {
            title = "Assign all four in order",
            text = "Assign all",
            click = function() StartKeyCapture(1, true) end,
            tooltip = "Prompts for every paddle one after another.",
        },
        {
            title = "How to set up the paddles",
            text = "Setup guide",
            click = function() ToggleGuideFrame() end,
            tooltip = "Step-by-step instructions for Steam Input and the Xbox Accessories app, plus a live readout of what WoW receives when you press a paddle.",
        }
    )

    AddCheckbox("showPaddleBadges", "Paddle prompts on actions",
        "Shows the paddle's name or glyph on assigned actions of the focused panel, like the native button prompts. Also respects the game's own action bar button prompt setting.",
        function()
            ApplyAppearance()
        end, "left")
    AddCheckbox("showPageArrows", "Page arrows on paging paddles",
        "Draws the native left or right arrow on the slots of a paddle that pages the crossbar. Off leaves those slots empty; the paddle still pages.",
        function()
            ns.UpdateAllButtonVisuals()
        end, "right")

    AddSection("Page binds (pages 2 and 3)")

    local note = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 20, y - 2)
    note:SetWidth(520)
    note:SetJustifyH("LEFT")
    note:SetText("Keys that fire a button's slot on crossbar page 2 or 3 without switching to it, on the layer LT / RT select (for example sent by a Steam Input long press). The top bar's A / B / X / Y are locked on pages 2-3 and are not bound.")
    y = y - 44

    -- Two key buttons per row: page 2 and page 3.
    local function AddPagePair(label, text2, click2, text3, click3, tooltip)
        local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("TOPLEFT", 20, y - 5)
        if type(label) == "function" then
            local getLabel = label
            text:SetText(getLabel())
            table.insert(refreshers, function()
                text:SetText(getLabel())
            end)
        else
            text:SetText(label)
        end
        for i, spec in ipairs({ { text2, click2, 250 }, { text3, click3, 400 } }) do
            local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            button:SetSize(140, 22)
            button:SetPoint("TOPLEFT", spec[3], y)
            button:SetScript("OnClick", spec[2])
            AttachTooltip(button, (type(label) == "string" and label or "Page bind") .. (i == 1 and " (page 2)" or " (page 3)"), tooltip)
            if type(spec[1]) == "function" then
                table.insert(refreshers, function()
                    button:SetText(spec[1]())
                end)
            else
                button:SetText(spec[1])
            end
        end
        y = y - 28
    end

    local headerPage2 = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerPage2:SetPoint("TOP", content, "TOPLEFT", 320, y)
    headerPage2:SetText("Page 2")
    local headerPage3 = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerPage3:SetPoint("TOP", content, "TOPLEFT", 470, y)
    headerPage3:SetText("Page 3")
    y = y - 20

    AddPagePair(
        "Assign all twelve in order",
        "Assign all", function() ns.StartPageBindCapture(2, 1, true) end,
        "Assign all", function() ns.StartPageBindCapture(3, 1, true) end,
        "Press the key for each button in turn. Esc skips a button, Delete clears it."
    )

    for index in ipairs(ns.PAGE_BIND_INPUTS) do
        AddPagePair(
            function()
                return ns.PageBindInputLabel(ns.PAGE_BIND_INPUTS[index])
            end,
            function() return ns.GetPageBindKey(2, index) or "Not set" end,
            function() ns.StartPageBindCapture(2, index, false) end,
            function() return ns.GetPageBindKey(3, index) or "Not set" end,
            function() ns.StartPageBindCapture(3, index, false) end,
            "Click, then press the key for this button. Delete clears it."
        )
    end

    AddSection("Diagnostics")

    AddButton(
        "Gamepad integration",
        "View Diagnostics",
        function()
            ShowDiagnosticsFrame()
        end,
        "Shows native storage, LT/RT detection, and native art status as plain text you can select and copy (Ctrl+C) into a bug report. Same as /grip diag copy; /grip diag prints it to chat."
    )

    content:SetHeight(-y + 10)

    local function RefreshControls()
        for _, refresh in ipairs(refreshers) do
            refresh()
        end
    end
    -- Deliberately not announced to the gamepad cursor (SmartNavigation). Once
    -- this page's controls are in its button list, closing Settings with the
    -- controller (B, or A on Close) hangs the client for the rest of the
    -- session. The controls are created at login and only reparented into the
    -- Settings window, so the cursor never picks them up on its own.
    panel:SetScript("OnShow", RefreshControls)

    -- Keeps the page in step with slash commands and press-to-assign while open.
    ns.RefreshSettingsKeyRows = function()
        if panel:IsVisible() then
            RefreshControls()
        end
    end

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    ns.settingsCategory = category
end

local function OpenSettings()
    if not ns.settingsRegistered then
        RegisterSettings()
    end

    if ns.settingsCategory and Settings and type(Settings.OpenToCategory) == "function" then
        Settings.OpenToCategory(ns.settingsCategory:GetID())
    else
        Print("The native Settings UI is not available yet.")
    end
end

ns.RegisterSettings = RegisterSettings
ns.OpenSettings = OpenSettings
