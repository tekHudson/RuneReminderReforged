--[[ UI/Widget.lua — draggable row/column of per-slot buttons showing what's
currently engraved, with a cooldown swirl. Click opens the picker (see
UI/Picker.lua); drag (via the same button, RegisterForClicks + RegisterForDrag
together, matching this addon's own RaidNamesCopy minimap-button convention)
moves the whole row. No custom chrome -- just the buttons themselves.
]]

local ADDON, ns = ...
local RRR = ns.RRR

local BUTTON_SIZE = 32
local BUTTON_PADDING = 4
local EMPTY_SLOT_TEXTURE = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

local container
local buttons = {} -- [slot] = button

----------------------------------------------------------------------
-- Position persistence
----------------------------------------------------------------------

local function SavePosition()
	local point, _, relativePoint, x, y = container:GetPoint()
	RRR.db.widget.point = { point, "UIParent", relativePoint, x, y }
end

local function RestorePosition()
	local p = RRR.db.widget.point
	container:ClearAllPoints()
	container:SetPoint(p[1], UIParent, p[3], p[4], p[5])
end

----------------------------------------------------------------------
-- Slot buttons
----------------------------------------------------------------------

local function CreateSlotButton(slot)
	local button = CreateFrame("Button", "RuneReminderReforgedSlotButton" .. slot, container)
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button.slot = slot

	local border = button:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0, 0, 0, 0.5)

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", 1, -1)
	button.icon:SetPoint("BOTTOMRIGHT", -1, 1)

	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints(button.icon)

	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	button:RegisterForClicks("LeftButtonUp")
	button:RegisterForDrag("LeftButton")

	button:SetScript("OnClick", function(self)
		RRR:OpenPicker(self.slot, self)
	end)

	button:SetScript("OnDragStart", function()
		if not RRR.db.widget.locked then
			container:StartMoving()
		end
	end)
	button:SetScript("OnDragStop", function()
		container:StopMovingOrSizing()
		SavePosition()
	end)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(RRR:GetSlotDisplayName(self.slot))
		local rune = RRR.runeCache[self.slot]
		if rune then
			GameTooltip:AddLine(rune.name, 1, 1, 1)
		else
			GameTooltip:AddLine("No rune engraved", 0.6, 0.6, 0.6)
		end
		GameTooltip:AddLine("Click to choose a rune", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	return button
end

function RRR:RefreshSlotButton(slot)
	local button = buttons[slot]
	if not button then
		return
	end

	local rune = RRR.runeCache[slot]
	if rune and rune.iconTexture then
		button.icon:SetTexture(rune.iconTexture)
		button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	else
		button.icon:SetTexture(EMPTY_SLOT_TEXTURE)
		button.icon:SetTexCoord(0, 1, 0, 1)
	end

	local start, duration, enable = GetInventoryItemCooldown("player", slot)
	CooldownFrame_Set(button.cooldown, start, duration, enable)
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------

function RRR:LayoutSlots()
	local step = BUTTON_SIZE + BUTTON_PADDING
	for i, slot in ipairs(RRR.slots) do
		local button = buttons[slot]
		button:ClearAllPoints()
		if RRR.db.widget.alignment == "VERTICAL" then
			button:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -((i - 1) * step))
		else
			button:SetPoint("TOPLEFT", container, "TOPLEFT", (i - 1) * step, 0)
		end
	end

	local count = #RRR.slots
	if RRR.db.widget.alignment == "VERTICAL" then
		container:SetSize(BUTTON_SIZE, math.max(count * step - BUTTON_PADDING, BUTTON_SIZE))
	else
		container:SetSize(math.max(count * step - BUTTON_PADDING, BUTTON_SIZE), BUTTON_SIZE)
	end
end

local function RebuildButtons()
	for slot, button in pairs(buttons) do
		button:Hide()
		button:SetParent(nil)
		buttons[slot] = nil
	end
	for _, slot in ipairs(RRR.slots) do
		local button = CreateSlotButton(slot)
		buttons[slot] = button
		button:Show()
		RRR:RefreshSlotButton(slot)
	end
	RRR:LayoutSlots()
end

----------------------------------------------------------------------
-- Public controls (used by Options + slash command)
----------------------------------------------------------------------

function RRR:SetWidgetShown(shown)
	RRR.db.widget.shown = shown
	container:SetShown(shown)
end

function RRR:SetWidgetScale(scale)
	RRR.db.widget.scale = scale
	container:SetScale(scale)
end

function RRR:SetWidgetAlignment(alignment)
	RRR.db.widget.alignment = alignment
	RRR:LayoutSlots()
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------

function RRR:BuildWidget()
	container = CreateFrame("Frame", "RuneReminderReforgedWidget", UIParent)
	container:SetMovable(true)
	container:SetClampedToScreen(true)
	container:SetScale(RRR.db.widget.scale)
	RestorePosition()

	RebuildButtons()
	container:SetShown(RRR.db.widget.shown)
end
