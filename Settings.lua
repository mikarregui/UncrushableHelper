local addonName, ns = ...

local panel
local showMinimapCheck, closeOutsideCheck

local function refreshControls()
    if not panel then return end
    local db      = UncrushableHelperDB
    local perChar = UncrushableHelperPerCharDB
    if not (db and db.global and perChar) then return end

    if showMinimapCheck then
        -- LibDBIcon uses `hide=true` to suppress the icon, so the checkbox
        -- reflects the *negation* of that flag (checked = visible).
        local hidden = perChar.minimap and perChar.minimap.hide
        showMinimapCheck:SetChecked(not hidden)
    end

    if closeOutsideCheck then
        closeOutsideCheck:SetChecked(db.global.closeOnOutsideClick == true)
    end
end

local function buildPanel()
    if panel then return panel end

    panel = CreateFrame(
        "Frame",
        "UHSettingsFrame",
        UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil
    )
    panel:SetSize(440, 340)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    panel:Hide()

    tinsert(UISpecialFrames, "UHSettingsFrame")

    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    end

    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Uncrushable Helper")

    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    subtitle:SetText("Settings")

    -- ========== Display section ==========
    local displayHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalMed3")
    displayHeader:SetPoint("TOPLEFT", 20, -68)
    displayHeader:SetText("Display")

    showMinimapCheck = CreateFrame(
        "CheckButton",
        "UHSettingsShowMinimapCheck",
        panel,
        "InterfaceOptionsCheckButtonTemplate"
    )
    showMinimapCheck:SetPoint("TOPLEFT", displayHeader, "BOTTOMLEFT", 0, -8)
    showMinimapCheck.Text:SetText("Show minimap icon")
    showMinimapCheck:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        UncrushableHelperPerCharDB.minimap = UncrushableHelperPerCharDB.minimap or {}
        UncrushableHelperPerCharDB.minimap.hide = not checked
        local icon = LibStub and LibStub("LibDBIcon-1.0", true)
        if icon then
            if checked then icon:Show("UncrushableHelper") else icon:Hide("UncrushableHelper") end
        end
    end)

    closeOutsideCheck = CreateFrame(
        "CheckButton",
        "UHSettingsCloseOutsideCheck",
        panel,
        "InterfaceOptionsCheckButtonTemplate"
    )
    closeOutsideCheck:SetPoint("TOPLEFT", showMinimapCheck, "BOTTOMLEFT", 0, -2)
    closeOutsideCheck.Text:SetText("Close main window when clicking outside")
    closeOutsideCheck:SetScript("OnClick", function(self)
        UncrushableHelperDB.global.closeOnOutsideClick = self:GetChecked() and true or false
    end)

    local resetBtn = CreateFrame("Button", "UHSettingsResetBtn", panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(220, 22)
    resetBtn:SetPoint("TOPLEFT", closeOutsideCheck, "BOTTOMLEFT", 4, -8)
    resetBtn:SetText("Reset main window position")
    resetBtn:SetScript("OnClick", function()
        if UncrushableHelperPerCharDB and UncrushableHelperPerCharDB.mainFrame then
            UncrushableHelperPerCharDB.mainFrame.point = nil
        end
        if ns.ui and ns.ui.ResetPosition then ns.ui:ResetPosition() end
    end)

    -- ========== About section ==========
    local aboutHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalMed3")
    aboutHeader:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", -4, -24)
    aboutHeader:SetText("About")

    local version = GetAddOnMetadata and GetAddOnMetadata(addonName, "Version")
    if not version or version == "" or version == "@project-version@" then
        version = "dev"
    end

    local aboutText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    aboutText:SetPoint("TOPLEFT", aboutHeader, "BOTTOMLEFT", 0, -8)
    aboutText:SetWidth(400)
    aboutText:SetJustifyH("LEFT")
    aboutText:SetText(
        "Version: |cffffffff" .. version .. "|r" ..
        "|n|nAvailable on:" ..
        "|n  \194\183 |cffffffffgithub.com/mikarregui/UncrushableHelper|r" ..
        "|n  \194\183 |cffffffffcurseforge.com/wow/addons/uncrushable-helper|r" ..
        "|n  \194\183 |cffffffffaddons.wago.io/addons/uncrushable-helper|r" ..
        "|n|n|cffffffff/uh|r toggle \194\183 |cffffffff/uh config|r this window \194\183 " ..
        "|cffffffff/uh debug|r snapshot \194\183 |cffffffff/uh reset|r window position."
    )

    return panel
end

function ns:OpenSettings()
    buildPanel()
    refreshControls()
    panel:Show()
    panel:Raise()
end

-- Pre-build the panel at PLAYER_LOGIN so right-click on the minimap icon
-- and /uh config open instantly.
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("PLAYER_LOGIN")
loadFrame:SetScript("OnEvent", function(self)
    buildPanel()
    self:UnregisterAllEvents()
end)
