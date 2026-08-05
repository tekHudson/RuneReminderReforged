--[[ UI/Picker.lua — a single shared context-menu-style dropdown (Blizzard's
native UIDropDownMenuTemplate, zero third-party libraries) listing the runes
available for whichever slot button was clicked. Repopulated fresh on every
open via RRR:GetRunesForSlot, so newly-learned runes always show up.
]]

local ADDON, ns = ...
local RRR = ns.RRR

local menu
local currentSlot

local function InitializePicker(_, level)
	-- UIDropDownMenu_Initialize invokes this once immediately during setup
	-- (before any slot has ever been picked), not just lazily on open.
	if not currentSlot then
		return
	end

	local runes = RRR:GetRunesForSlot(currentSlot)

	if #runes == 0 then
		local info = UIDropDownMenu_CreateInfo()
		info.text = "No runes known for this slot"
		info.notCheckable = true
		info.disabled = true
		UIDropDownMenu_AddButton(info, level)
		return
	end

	for _, rune in ipairs(runes) do
		local info = UIDropDownMenu_CreateInfo()
		info.text = rune.name
		info.notCheckable = true
		info.icon = rune.iconTexture
		info.func = function()
			RRR:CastRuneOnSlot(rune.skillLineAbilityID)
			CloseDropDownMenus()
		end
		UIDropDownMenu_AddButton(info, level)
	end
end

function RRR:OpenPicker(slot, anchorButton)
	currentSlot = slot
	ToggleDropDownMenu(1, nil, menu, anchorButton, 0, 0)
end

function RRR:InitPicker()
	menu = CreateFrame("Frame", "RuneReminderReforgedPickerMenu", UIParent, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(menu, InitializePicker, "MENU")
end
