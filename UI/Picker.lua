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

	-- SetEngravingRune's underlying spell data (icon, full description) is
	-- warmed into the client's cache well before this ever runs (see
	-- Core/Engraving.lua:WarmRuneTooltipCache, called on entering world), so
	-- this can just build the tooltip once per hover instead of needing to
	-- repeatedly re-poll for data that might still be loading.
	local function RefreshTooltip(self)
		-- ANCHOR_RIGHT, matching Blizzard's own EngravingFrame rune buttons
		-- (RuneSpellButton_OnEnter) -- keeps the tooltip clear of the flyout's
		-- own icon stack instead of covering neighboring rune buttons.
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetEngravingRune(self.skillLineAbilityID)

		if self.disabledReason then
			-- Blizzard's own tooltip appends a bracketed action hint (e.g.
			-- "<Click to Engrave Rune>") that's misleading here since the
			-- button can't actually be clicked. That embedded ability
			-- preview isn't a plain text line (ClearLines()+rebuild would
			-- destroy it), so blank the hint line in place instead of
			-- rebuilding the tooltip, then append our own reason below it.
			for i = 1, GameTooltip:NumLines() do
				local fontString = _G["GameTooltipTextLeft" .. i]
				local text = fontString and fontString:GetText()
				if text and text:match("^%s*<.*>%s*$") then
					fontString:SetText("")
				end
			end
			GameTooltip:AddLine(self.disabledReason, 1, 0.2, 0.2, true)
		end

		GameTooltip:Show()
	end

	b:SetScript("OnEnter", RefreshTooltip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	return b
end

-- Which edge of the flyout attaches to the clicked button, which edge the
-- icons stack outward from, and whether that stacking is vertical.
local DIRECTIONS = {
	UP    = { flyoutPoint = "BOTTOM", relativePoint = "TOP",    x = 0,  y = 6,  iconPoint = "BOTTOM", vertical = true  },
	DOWN  = { flyoutPoint = "TOP",    relativePoint = "BOTTOM", x = 0,  y = -6, iconPoint = "TOP",    vertical = true  },
	LEFT  = { flyoutPoint = "RIGHT",  relativePoint = "LEFT",   x = -6, y = 0,  iconPoint = "RIGHT",  vertical = false },
	RIGHT = { flyoutPoint = "LEFT",   relativePoint = "RIGHT",  x = 6,  y = 0,  iconPoint = "LEFT",   vertical = false },
}

local function CreateFlyout()
	local f = CreateFrame("Frame", "RuneReminderReforgedPickerFlyout", UIParent)
	f:SetFrameStrata("DIALOG")

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.5)

	-- Shown instead of an icon row on the rare slot category with no rune
	-- definitions at all (GetRunesForSlot now returns every rune for the
	-- category, known or not, so this only fires for a genuinely empty
	-- category -- not just "player hasn't learned any yet"). A flyout with
	-- zero icons and no background was otherwise indistinguishable from
	-- nothing happening on click at all.
	f.emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.emptyText:SetPoint("CENTER")
	f.emptyText:SetText("No runes exist for this slot")
	f.emptyText:Hide()

	f:Hide()
	return f
end

function RRR:OpenPicker(slot, anchorButton)
	if openForSlot == slot then
		HideFlyout()
		return
	end

	local runes = RRR:GetRunesForSlot(slot)
	local dir = DIRECTIONS[RRR.db.widget.flyoutDirection] or DIRECTIONS.UP
	local step = ICON_SIZE + ICON_PADDING

	-- Whether the item currently sitting in this slot can even be engraved
	-- right now (empty slot, non-engravable item, etc.) -- if not, every
	-- rune is equally inapplicable, so still render the full list (rather
	-- than the flyout looking broken/empty) but grey it all out instead of
	-- letting a click silently no-op.
	local engravable = C_Engraving.IsEquipmentSlotEngravable(slot)

	-- flyout is parented to UIParent (not the widget container), so it
	-- doesn't inherit the widget's scale automatically -- match it here so
	-- the flyout's icons stay visually proportional to the widget's own.
	flyout:SetScale(RRR.db.widget.scale)

	for _, b in ipairs(flyoutButtons) do
		b:Hide()
	end

	for i, rune in ipairs(runes) do
		local b = flyoutButtons[i]
		if not b then
			b = CreateFlyoutButton()
			flyoutButtons[i] = b
		end
		local usable = engravable and rune.known
		b.icon:SetTexture(rune.iconTexture)
		b.icon:SetDesaturated(not usable)
		b:SetAlpha(usable and 1 or 0.4)
		b.skillLineAbilityID = rune.skillLineAbilityID
		if not rune.known then
			b.disabledReason = "You haven't learned this rune yet."
		elseif not engravable then
			b.disabledReason = "Can't engrave this slot right now."
		else
			b.disabledReason = nil
		end
		b:SetScript("OnClick", function()
			if not usable then
				return
			end
			RRR:CastRuneOnSlot(rune, slot)
			HideFlyout()
		end)
		b:ClearAllPoints()
		if dir.vertical then
			b:SetPoint(dir.iconPoint, flyout, dir.iconPoint, 0, (i - 1) * step * (dir.iconPoint == "TOP" and -1 or 1))
		else
			b:SetPoint(dir.iconPoint, flyout, dir.iconPoint, (i - 1) * step * (dir.iconPoint == "RIGHT" and -1 or 1), 0)
		end
		b:Show()
	end

	if #runes == 0 then
		flyout.emptyText:Show()
		flyout:SetSize(flyout.emptyText:GetStringWidth() + 16, ICON_SIZE)
	else
		flyout.emptyText:Hide()
		local extent = #runes * ICON_SIZE + (#runes - 1) * ICON_PADDING
		if dir.vertical then
			flyout:SetSize(ICON_SIZE, extent)
		else
			flyout:SetSize(extent, ICON_SIZE)
		end
	end

	flyout:ClearAllPoints()
	flyout:SetPoint(dir.flyoutPoint, anchorButton, dir.relativePoint, dir.x, dir.y)
	flyout:Show()
	openForSlot = slot
end

function RRR:InitPicker()
	flyout = CreateFlyout()
end
