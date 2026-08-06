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
-- Hover label: bare slot-name text above (or, when the picker flyout
-- expands upward and would collide with it, below) the hovered button --
-- replaces a full GameTooltip, which was oversized for just a slot name.
----------------------------------------------------------------------

local hoverLabel

local function CreateHoverLabel()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(1, 1)
	f:SetFrameStrata("TOOLTIP")
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.text:SetPoint("CENTER")
	f:Hide()
	return f
end

local function ShowHoverLabel(button)
	if not hoverLabel then
		hoverLabel = CreateHoverLabel()
	end
	hoverLabel.text:SetText(RRR:GetSlotDisplayName(button.slot))
	hoverLabel:ClearAllPoints()
	if RRR.db.widget.flyoutDirection == "UP" then
		hoverLabel:SetPoint("TOP", button, "BOTTOM", 0, -4)
	else
		hoverLabel:SetPoint("BOTTOM", button, "TOP", 0, 4)
	end
	hoverLabel:Show()
end

local function HideHoverLabel()
	if hoverLabel then
		hoverLabel:Hide()
	end
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
		ShowHoverLabel(self)
	end)
	button:SetScript("OnLeave", function()
		HideHoverLabel()
	end)

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
-- Reapply prompt: a small one-click, non-modal nudge shown at a slot when
-- a gear swap cleared its rune (see Core/Notify.lua). Not a StaticPopup --
-- just a bare clickable frame, matching the picker's lightweight style.
----------------------------------------------------------------------

local reapplyPrompt

local function CreateReapplyPrompt()
	local p = CreateFrame("Button", "RuneReminderReforgedReapplyPrompt", UIParent)
	p:SetSize(160, 28)
	p:SetFrameStrata("DIALOG")

	local bg = p:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.8)

	p.icon = p:CreateTexture(nil, "ARTWORK")
	p.icon:SetSize(24, 24)
	p.icon:SetPoint("LEFT", 2, 0)
	p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.text:SetPoint("LEFT", p.icon, "RIGHT", 4, 0)
	p.text:SetPoint("RIGHT", -4, 0)
	p.text:SetJustifyH("LEFT")
	p.text:SetWordWrap(false)

	p:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	p:RegisterForClicks("LeftButtonUp")
	p:SetScript("OnClick", function(self)
		if self.onConfirm then
			self.onConfirm()
		end
		self:Hide()
	end)

	-- Small explicit dismiss button, separate from the main clickable area
	-- (which reapplies) -- stays up until manually dismissed one way or
	-- another, no auto-hide timer.
	local close = CreateFrame("Button", nil, p)
	close:SetSize(14, 14)
	close:SetPoint("TOPRIGHT", -2, -2)
	local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	closeText:SetAllPoints()
	closeText:SetText("x")
	close:SetScript("OnClick", function()
		p:Hide()
	end)
	close:SetScript("OnEnter", function(self)
		closeText:SetTextColor(1, 0.3, 0.3)
	end)
	close:SetScript("OnLeave", function(self)
		closeText:SetTextColor(1, 1, 1)
	end)

	-- Escape dismisses it too, same as any other WoW UI panel.
	tinsert(UISpecialFrames, p:GetName())

	p:Hide()
	return p
end

-- Anchored the same direction as the picker flyout (widget.flyoutDirection),
-- so it appears in a visually consistent spot.
local PROMPT_DIRECTIONS = {
	UP    = { point = "BOTTOM", relativePoint = "TOP",    x = 0,  y = 6  },
	DOWN  = { point = "TOP",    relativePoint = "BOTTOM", x = 0,  y = -6 },
	LEFT  = { point = "RIGHT",  relativePoint = "LEFT",   x = -6, y = 0  },
	RIGHT = { point = "LEFT",   relativePoint = "RIGHT",  x = 6,  y = 0  },
}

function RRR:ShowReapplyPrompt(slot, oldRune)
	local button = buttons[slot]
	if not button then
		return
	end

	if not reapplyPrompt then
		reapplyPrompt = CreateReapplyPrompt()
	end

	reapplyPrompt.icon:SetTexture(oldRune.iconTexture)
	reapplyPrompt.text:SetText("Reapply " .. oldRune.name .. "?")
	reapplyPrompt.onConfirm = function()
		RRR:CastRuneOnSlot(oldRune, slot)
	end
	reapplyPrompt:SetScale(RRR.db.widget.scale)

	local dir = PROMPT_DIRECTIONS[RRR.db.widget.flyoutDirection] or PROMPT_DIRECTIONS.UP
	reapplyPrompt:ClearAllPoints()
	reapplyPrompt:SetPoint(dir.point, button, dir.relativePoint, dir.x, dir.y)
	reapplyPrompt:Show()
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
