--[[ Core/Engraving.lua — C_Engraving wrapper: slot discovery, per-slot rune
cache, and change detection.

Slot discovery loops the 19 standard equipment slots and asks
C_Engraving.IsEquipmentSlotEngravable per slot, the same approach Blizzard's
own paperdoll code uses -- simpler and more directly correct than filtering
C_Engraving.GetRuneCategories, whose ownedOnly=false semantics aren't
demonstrated anywhere in Blizzard's reference UI code.

CastRune needs no explicit slot targeting: each rune ability is already bound
to one equipment slot, and the client/server resolves the target from the
ability itself (confirmed via Blizzard_EngravingUI.lua's cast flow).
]]

local ADDON, ns = ...
local RRR = ns.RRR

----------------------------------------------------------------------
-- Slot discovery
----------------------------------------------------------------------

-- Ordered so the widget lays out buttons in the same order as the paperdoll.
-- SoD's rune-engraving system covers exactly 9 slot categories: chest,
-- gloves, legs, waist, feet, head, wrist, back, and ring (confirmed via
-- Icy Veins' SoD rune overview -- "Notably absent... shoulder, neck, and
-- trinket slots", and neither weapons nor tabard/shirt are armor). Ring
-- covers both physical finger slots. C_Engraving.IsEquipmentSlotEngravable
-- still gates each of these individually below, but it isn't reliable
-- enough on its own to also decide which slot *categories* are worth
-- probing in the first place: it returned true for INVSLOT_RANGED despite
-- ranged weapons not actually being engravable, so anything outside this
-- confirmed 9-category set is excluded here rather than trusted to
-- self-report correctly.
local ALL_SLOTS = {
	INVSLOT_HEAD, INVSLOT_BACK, INVSLOT_CHEST,
	INVSLOT_WRIST, INVSLOT_HAND, INVSLOT_WAIST, INVSLOT_LEGS, INVSLOT_FEET,
	INVSLOT_FINGER1, INVSLOT_FINGER2,
}

local function RunesMatch(a, b)
	if a == nil and b == nil then
		return true
	end
	if a == nil or b == nil then
		return false
	end
	return a.skillLineAbilityID == b.skillLineAbilityID
end

-- Re-scans which equipment slots are currently engravable. Returns true if
-- the set of tracked slots changed (so the widget knows to rebuild buttons
-- rather than just refresh icons). Cheap: 19 boolean calls.
function RRR:RefreshSlotList()
	local newSlots = {}
	for _, slot in ipairs(ALL_SLOTS) do
		if C_Engraving.IsEquipmentSlotEngravable(slot) then
			newSlots[#newSlots + 1] = slot
		end
	end

	local changed = false
	if not RRR.slots or #RRR.slots ~= #newSlots then
		changed = true
	else
		for i, slot in ipairs(newSlots) do
			if RRR.slots[i] ~= slot then
				changed = true
				break
			end
		end
	end

	RRR.slots = newSlots
	RRR.runeCache = RRR.runeCache or {}
	for _, slot in ipairs(RRR.slots) do
		if RRR.runeCache[slot] == nil then
			RRR.runeCache[slot] = C_Engraving.GetRuneForEquipmentSlot(slot)
		end
	end

	return changed
end

function RRR:InitEngraving()
	RRR.runeCache = {}
	RRR:RefreshSlotList()
end

----------------------------------------------------------------------
-- Picker support
----------------------------------------------------------------------

-- Fresh query every time (no caching) so newly-learned runes show up
-- immediately without any extra event wiring.
function RRR:GetRunesForSlot(slot)
	local runes = C_Engraving.GetRunesForCategory(slot, true)
	table.sort(runes, function(a, b) return a.name < b.name end)
	return runes
end

function RRR:CastRuneOnSlot(skillLineAbilityID)
	C_Engraving.CastRune(skillLineAbilityID)
end

----------------------------------------------------------------------
-- Event handlers
----------------------------------------------------------------------

function RRR:PLAYER_EQUIPMENT_CHANGED(_, slotID)
	local slotSetChanged = RRR:RefreshSlotList()

	local tracked = false
	for _, slot in ipairs(RRR.slots) do
		if slot == slotID then
			tracked = true
			break
		end
	end

	if tracked then
		local oldRune = RRR.runeCache[slotID]
		local newRune = C_Engraving.GetRuneForEquipmentSlot(slotID)
		RRR.runeCache[slotID] = newRune
		if not RunesMatch(oldRune, newRune) then
			RRR:RuneMismatch(slotID, oldRune, newRune)
		end
	end

	-- A slot-set change means buttons must be rebuilt (covers this slot too,
	-- since RebuildWidgetSlots re-reads runeCache -- already updated above).
	-- Otherwise, just refresh the one button that actually changed.
	if slotSetChanged and RRR.RebuildWidgetSlots then
		RRR:RebuildWidgetSlots()
	elseif tracked and RRR.RefreshSlotButton then
		RRR:RefreshSlotButton(slotID)
	end
end

-- PLAYER_LOGIN can fire before equipment/engraving data is fully synced from
-- the server, so InitEngraving's initial scan may find zero engravable slots
-- (an empty, invisible widget). Force a full re-scan and re-fetch once the
-- world is actually entered, and rebuild unconditionally so the widget is
-- guaranteed to reflect reality even if nothing looked "changed" by the
-- (possibly wrong) earlier comparison.
function RRR:PLAYER_ENTERING_WORLD()
	RRR.runeCache = {}
	RRR:RefreshSlotList()
	if RRR.RebuildWidgetSlots then
		RRR:RebuildWidgetSlots()
	end
end

-- Fires for any successful engrave (ours via the picker, Blizzard's own
-- character panel, or another addon) -- deliberate engraving is never a
-- mismatch, so this never routes through Notify.
function RRR:RUNE_UPDATED(_, rune)
	if rune then
		local slot = rune.equipmentSlot
		RRR.runeCache[slot] = C_Engraving.GetRuneForEquipmentSlot(slot)
		if RRR.RefreshSlotButton then
			RRR:RefreshSlotButton(slot)
		end
	else
		for _, slot in ipairs(RRR.slots) do
			RRR.runeCache[slot] = C_Engraving.GetRuneForEquipmentSlot(slot)
			if RRR.RefreshSlotButton then
				RRR:RefreshSlotButton(slot)
			end
		end
	end
end
