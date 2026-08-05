--[[ UI/Picker.lua — a small flyout of bare icon buttons (matching the main
widget's own look, see UI/Widget.lua) listing the runes available for
whichever slot was clicked. No dropdown-menu chrome. Repopulated fresh on
every open via RRR:GetRunesForSlot, so newly-learned runes always show up.
]]

local ADDON, ns = ...
local RRR = ns.RRR

local ICON_SIZE = 28
local ICON_PADDING = 4

local flyout
local flyoutButtons = {} -- reused pool, index = position in the current list
local openForSlot -- nil when closed, else the slot the flyout is currently showing

local function HideFlyout()
	openForSlot = nil
	flyout:Hide()
end

local function CreateFlyoutButton()
	local b = CreateFrame("Button", nil, flyout)
	b:SetSize(ICON_SIZE, ICON_SIZE)

	local border = b:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0, 0, 0, 0.5)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:RegisterForClicks("LeftButtonUp")

	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(self.runeName or "")
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	return b
end

function RRR:OpenPicker(slot, anchorButton)
	if openForSlot == slot then
		HideFlyout()
		return
	end

	local runes = RRR:GetRunesForSlot(slot)

	for _, b in ipairs(flyoutButtons) do
		b:Hide()
	end

	for i, rune in ipairs(runes) do
		local b = flyoutButtons[i]
		if not b then
			b = CreateFlyoutButton()
			flyoutButtons[i] = b
		end
		b.icon:SetTexture(rune.iconTexture)
		b.runeName = rune.name
		b:SetScript("OnClick", function()
			RRR:CastRuneOnSlot(rune.skillLineAbilityID)
			HideFlyout()
		end)
		b:ClearAllPoints()
		b:SetPoint("LEFT", flyout, "LEFT", (i - 1) * (ICON_SIZE + ICON_PADDING), 0)
		b:Show()
	end

	local width = #runes > 0 and (#runes * ICON_SIZE + (#runes - 1) * ICON_PADDING) or ICON_SIZE
	flyout:SetSize(width, ICON_SIZE)

	flyout:ClearAllPoints()
	flyout:SetPoint("BOTTOM", anchorButton, "TOP", 0, 6)
	flyout:Show()
	openForSlot = slot
end

function RRR:InitPicker()
	flyout = CreateFrame("Frame", "RuneReminderReforgedPickerFlyout", UIParent)
	flyout:SetFrameStrata("DIALOG")
	flyout:Hide()
end
