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
-- Slot label: bare slot-name text overlaid on the button itself (near the
-- top edge, over the icon), white so it reads against any icon. Shown only
-- on hover by default, or always shown when widget.labelOnHover is false
-- (see RRR:SetLabelOnHover, wired to the options checkbox) -- an
-- always-visible label positioned above/below the button collided with
-- neighboring buttons in a vertical layout, so it stays inside the button.
----------------------------------------------------------------------

local function CreateSlotLabel(button)
	local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetText(RRR:GetSlotDisplayName(button.slot))
	label:SetTextColor(1, 1, 1, 1)
	label:SetPoint("TOP", button, "TOP", 0, -2)
	label:SetShown(not RRR.db.widget.labelOnHover)
	return label
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

	button.label = CreateSlotLabel(button)

	button:SetScript("OnEnter", function(self)
		if RRR.db.widget.labelOnHover then
			self.label:Show()
		end
	end)
	button:SetScript("OnLeave", function(self)
		if RRR.db.widget.labelOnHover then
			self.label:Hide()
		end
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
-- Reapply prompt: a small non-modal dialog shown when a gear swap cleared
-- a tracked slot's rune (see Core/Notify.lua). Just two buttons side by
-- side -- the message lives in the accept button's own label, so there's
-- no separate title/icon taking up space. Styled with the classic dialog
-- box background/border (same art Blizzard's own popups use) and anchored
-- dead center on screen.
----------------------------------------------------------------------

local REAPPLY_PADDING = 14
local REAPPLY_BUTTON_HEIGHT = 22

local reapplyPrompt

local function CreateReapplyPrompt()
	local p = CreateFrame("Frame", "RuneReminderReforgedReapplyPrompt", UIParent, "BackdropTemplate")
	p:SetFrameStrata("DIALOG")
	p:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	p:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})

	p:SetMovable(true)
	p:EnableMouse(true)
	p:RegisterForDrag("LeftButton")
	p:SetScript("OnDragStart", p.StartMoving)
	p:SetScript("OnDragStop", p.StopMovingOrSizing)

	p.accept = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	p.accept:SetHeight(REAPPLY_BUTTON_HEIGHT)
	p.accept:SetScript("OnClick", function()
		if p.onConfirm then
			p.onConfirm()
		end
		p:Hide()
	end)

	p.cancel = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	p.cancel:SetHeight(REAPPLY_BUTTON_HEIGHT)
	p.cancel:SetText(CANCEL or "Cancel")
	p.cancel:SetScript("OnClick", function()
		p:Hide()
	end)

	-- Escape dismisses it too, same as any other WoW UI panel.
	tinsert(UISpecialFrames, p:GetName())

	p:Hide()
	return p
end

function RRR:ShowReapplyPrompt(slot, oldRune)
	if not reapplyPrompt then
		reapplyPrompt = CreateReapplyPrompt()
	end

	reapplyPrompt.slot = slot
	reapplyPrompt.onConfirm = function()
		RRR:CastRuneOnSlot(oldRune, slot)
	end

	local accept, cancel = reapplyPrompt.accept, reapplyPrompt.cancel
	accept:SetText("Re-apply " .. oldRune.name)
	accept:SetWidth(math.max(accept:GetFontString():GetStringWidth() + 24, 90))
	cancel:SetWidth(math.max(cancel:GetFontString():GetStringWidth() + 24, 80))

	accept:ClearAllPoints()
	accept:SetPoint("LEFT", REAPPLY_PADDING, 0)
	cancel:ClearAllPoints()
	cancel:SetPoint("LEFT", accept, "RIGHT", REAPPLY_PADDING, 0)

	reapplyPrompt:SetSize(
		accept:GetWidth() + cancel:GetWidth() + REAPPLY_PADDING * 3,
		REAPPLY_BUTTON_HEIGHT + REAPPLY_PADDING * 2
	)
	reapplyPrompt:ClearAllPoints()
	reapplyPrompt:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	reapplyPrompt:Show()
end

-- Dismisses a still-open prompt for `slot` -- called whenever that slot's
-- equipment changes again, so a stale "Reapply?" doesn't linger once the
-- rune is back (or the slot's moved on to something else entirely).
function RRR:HideReapplyPrompt(slot)
	if reapplyPrompt and reapplyPrompt:IsShown() and reapplyPrompt.slot == slot then
		reapplyPrompt:Hide()
	end
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

function RRR:SetLabelOnHover(onHover)
	RRR.db.widget.labelOnHover = onHover
	for _, button in pairs(buttons) do
		button.label:SetShown(not onHover)
	end
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
