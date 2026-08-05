--[[ Core/Notify.lua — chat-only notification when a gear swap silently
changes or clears a tracked slot's rune. No popups, no reapply buttons.
]]

local ADDON, ns = ...
local RRR = ns.RRR

function RRR:RuneMismatch(slot, oldRune, newRune)
	if not RRR.db.notify.enabled then
		return
	end

	local slotName = C_Item.GetItemInventorySlotInfo(slot) or "item"

	if newRune then
		if oldRune then
			RRR:Print(string.format("Your %s now has |cffffcc00%s|r engraved (had |cffffcc00%s|r before).",
				slotName, newRune.name, oldRune.name))
		else
			RRR:Print(string.format("Your %s now has |cffffcc00%s|r engraved.", slotName, newRune.name))
		end
	else
		if oldRune then
			RRR:Print(string.format("Your %s has no rune engraved (had |cffffcc00%s|r before).",
				slotName, oldRune.name))
		else
			RRR:Print(string.format("Your %s has no rune engraved.", slotName))
		end
	end
end
