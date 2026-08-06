--[[ Core/Notify.lua — chat notification when a gear swap silently changes
or clears a tracked slot's rune. When a slot goes from having a rune to
having none, also shows a small one-click "Reapply?" prompt on the widget
(UI/Widget.lua:ShowReapplyPrompt) -- not a blocking popup, just a bare
clickable nudge.
]]

local ADDON, ns = ...
local RRR = ns.RRR

function RRR:RuneMismatch(slot, oldRune, newRune)
	if not RRR.db.notify.enabled then
		return
	end

	local slotName = RRR:GetSlotDisplayName(slot)

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
			if RRR.ShowReapplyPrompt then
				RRR:ShowReapplyPrompt(slot, oldRune)
			end
		else
			RRR:Print(string.format("Your %s has no rune engraved.", slotName))
		end
	end
end
