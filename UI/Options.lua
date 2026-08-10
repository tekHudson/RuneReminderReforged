--[[ UI/Options.lua — a single native Blizzard Settings canvas page. No
subcategories (this addon only has five settings), no third-party UI
libraries -- just CreateFrame + Settings.RegisterCanvasLayoutCategory and
small helper functions for checkbox/slider/dropdown controls built on
Blizzard's own templates.
]]

local ADDON, ns = ...
local RRR = ns.RRR

local category

----------------------------------------------------------------------
-- Small widget helpers
----------------------------------------------------------------------

local function newCheckbox(parent, label, tooltip, get, set)
	local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
	cb.Text:SetText(label)
	cb.tooltipText = tooltip
	cb:SetScript("OnShow", function(self) self:SetChecked(get()) end)
	cb:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
	end)
	cb:SetChecked(get())
	return cb
end

local sliderCount = 0
local function newSlider(parent, label, minV, maxV, step, get, set)
	sliderCount = sliderCount + 1
	local name = "RuneReminderReforgedSlider" .. sliderCount
	local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s:SetWidth(200)
	s.Low = _G[name .. "Low"] or s.Low
	s.High = _G[name .. "High"] or s.High
	s.Text = _G[name .. "Text"] or s.Text
	if s.Text then s.Text:SetText(label) end
	if s.Low then s.Low:SetText(minV) end
	if s.High then s.High:SetText(maxV) end
	s:SetScript("OnShow", function(self) self:SetValue(get()) end)
	s:SetValue(get())
	s:SetScript("OnValueChanged", function(self, v)
		v = math.floor(v / step + 0.5) * step
		set(v)
	end)
	return s
end

local ddCount = 0
local function newDropdown(parent, label, choices, get, set)
	ddCount = ddCount + 1
	local title = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	title:SetText(label)
	local dd = CreateFrame("Frame", "RuneReminderReforgedDropdown" .. ddCount, parent, "UIDropDownMenuTemplate")

	local function textFor(value)
		for _, c in ipairs(choices) do
			if c.value == value then return c.text end
		end
		return tostring(value)
	end

	UIDropDownMenu_SetWidth(dd, 150)
	UIDropDownMenu_Initialize(dd, function()
		for _, c in ipairs(choices) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = c.text
			info.checked = (get() == c.value)
			info.func = function()
				set(c.value)
				UIDropDownMenu_SetText(dd, c.text)
				CloseDropDownMenus()
			end
			UIDropDownMenu_AddButton(info)
		end
	end)
	dd:SetScript("OnShow", function() UIDropDownMenu_SetText(dd, textFor(get())) end)
	UIDropDownMenu_SetText(dd, textFor(get()))

	dd.PlaceAt = function(_, px, py)
		title:SetPoint("TOPLEFT", parent, "TOPLEFT", px + 18, py)
		dd:SetPoint("TOPLEFT", parent, "TOPLEFT", px, py - 16)
	end
	return dd
end

----------------------------------------------------------------------
-- Page
----------------------------------------------------------------------

local function BuildPage()
	local panel = CreateFrame("Frame", "RuneReminderReforgedOptionsPanel", UIParent)
	panel.name = "Rune Reminder Reforged"

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Rune Reminder Reforged v" .. tostring(RRR.version))

	local COL1, ROW = 22, 30
	local y = -50

	local showCB = newCheckbox(panel, "Show widget", "Toggle the rune-tracking widget.",
		function() return RRR.db.widget.shown end,
		function(v) RRR:SetWidgetShown(v) end)
	showCB:SetPoint("TOPLEFT", panel, "TOPLEFT", COL1, y)
	y = y - ROW

	local lockCB = newCheckbox(panel, "Lock position", "Prevent dragging the widget.",
		function() return RRR.db.widget.locked end,
		function(v) RRR.db.widget.locked = v end)
	lockCB:SetPoint("TOPLEFT", panel, "TOPLEFT", COL1, y)
	y = y - ROW

	local notifyCB = newCheckbox(panel, "Chat notification on gear-swap mismatch",
		"Print a chat message when equipping different gear changes or clears a tracked slot's rune.",
		function() return RRR.db.notify.enabled end,
		function(v) RRR.db.notify.enabled = v end)
	notifyCB:SetPoint("TOPLEFT", panel, "TOPLEFT", COL1, y)
	y = y - ROW

	local castConfirmCB = newCheckbox(panel, "Chat message on rune replacement",
		"Print a chat message confirming a rune you engraved via the picker successfully replaced the slot's old rune.",
		function() return RRR.db.notify.castConfirm end,
		function(v) RRR.db.notify.castConfirm = v end)
	castConfirmCB:SetPoint("TOPLEFT", panel, "TOPLEFT", COL1, y)
	y = y - ROW

	local labelHoverCB = newCheckbox(panel, "Text on hover",
		"Show each slot's name only on mouseover. Unchecked, slot names are always shown.",
		function() return RRR.db.widget.labelOnHover end,
		function(v) RRR:SetLabelOnHover(v) end)
	labelHoverCB:SetPoint("TOPLEFT", panel, "TOPLEFT", COL1, y)
	y = y - ROW - 12

	local LAYOUT_CHOICES = {
		{ text = "Vertical (flyout left)",   value = "VERTICAL_LEFT" },
		{ text = "Vertical (flyout right)",  value = "VERTICAL_RIGHT" },
		{ text = "Horizontal (flyout up)",   value = "HORIZONTAL_UP" },
		{ text = "Horizontal (flyout down)", value = "HORIZONTAL_DOWN" },
	}
	local layoutDD = newDropdown(panel, "Layout", LAYOUT_CHOICES,
		function()
			return RRR.db.widget.alignment .. "_" .. RRR.db.widget.flyoutDirection
		end,
		function(v)
			local alignment, direction = v:match("^(%a+)_(%a+)$")
			RRR:SetWidgetAlignment(alignment)
			RRR.db.widget.flyoutDirection = direction
		end)
	layoutDD:PlaceAt(COL1 - 4, y)
	y = y - 52 - 16

	local sizeSlider = newSlider(panel, "Size", 0.5, 2.0, 0.1,
		function() return RRR.db.widget.scale end,
		function(v) RRR:SetWidgetScale(v) end)
	sizeSlider:SetPoint("TOPLEFT", panel, "TOPLEFT", COL1 + 8, y)

	return panel
end

----------------------------------------------------------------------
-- Register + open
----------------------------------------------------------------------

function RRR:InitOptions()
	if RRR.optionsPanel then
		return
	end
	RRR.optionsPanel = BuildPage()

	if Settings and Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(RRR.optionsPanel, RRR.optionsPanel.name)
		Settings.RegisterAddOnCategory(category)
	end
end

function RRR:OpenOptions()
	RRR:InitOptions()
	if Settings and Settings.OpenToCategory and category then
		Settings.OpenToCategory(category:GetID())
	end
end
