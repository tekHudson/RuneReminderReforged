--[[ Core/Engraving.lua — C_Engraving wrapper: fixed slot list, per-slot
rune cache, and change detection.

CastRune needs no explicit slot targeting: each rune ability is already bound
to one equipment slot, and the client/server resolves the target from the
ability itself (confirmed via Blizzard_EngravingUI.lua's cast flow).
]]

local ADDON, ns = ...
local RRR = ns.RRR

----------------------------------------------------------------------
-- Tracked slots
----------------------------------------------------------------------

-- SoD's rune-engraving system covers exactly 9 slot categories: chest,
-- gloves, legs, waist, feet, head, wrist, back, and ring (confirmed via
-- Icy Veins' SoD rune overview -- "Notably absent... shoulder, neck, and
-- trinket slots"; weapons and tabard/shirt aren't armor either). Ring
-- covers both physical finger slots, hence 10 slot IDs for 9 categories.
--
-- This list is fixed and always shown, regardless of what's currently
-- equipped there (or whether anything is). C_Engraving.IsEquipmentSlotEngravable
-- reflects whether the CURRENTLY EQUIPPED ITEM in a slot is engravable, not
-- whether the slot category is part of the system in general -- Blizzard's
-- own paperdoll code uses it exactly that way. Gating which buttons exist on
-- that call meant the widget could show nothing at all whenever none of the
-- player's current gear happened to test as engravable at that instant, and
-- it also returned true for INVSLOT_RANGED despite ranged weapons never
-- being part of the system. A reminder widget should show a stable set of
-- slots and just display "no rune" for whichever ones aren't currently
-- engraved, rather than buttons appearing and disappearing with gear swaps.
local ALL_SLOTS = {
	INVSLOT_HEAD, INVSLOT_BACK, INVSLOT_CHEST,
	INVSLOT_WRIST, INVSLOT_HAND, INVSLOT_WAIST, INVSLOT_LEGS, INVSLOT_FEET,
	INVSLOT_FINGER1, INVSLOT_FINGER2,
}

-- IMPORTANT: paperdoll slot positions (INVSLOT_*, used by
-- GetRuneForEquipmentSlot/GetInventoryItemCooldown) and item equip-location
-- *types* (Enum.InventoryType, used by GetRunesForCategory and
-- C_Item.GetItemInventorySlotInfo) are two DIFFERENT numbering schemes that
-- happen to share values 1-11 but diverge after that: INVSLOT_BACK=15 but
-- Enum.InventoryType.IndexCloakType=16, while Enum.InventoryType.IndexRangedType
-- happens to equal 15 -- so passing the paperdoll Back slot into a function
-- expecting an InventoryType returned "Ranged" instead of "Back". Confirmed
-- against Blizzard_APIDocumentationGenerated/ItemConstantsDocumentation.lua.
-- Finger1 and Finger2 both map to the single IndexFingerType category (rings
-- aren't distinguished by which of the two slots they're in for this purpose).
local PAPERDOLL_TO_INVTYPE = {
	[INVSLOT_HEAD]    = Enum.InventoryType.IndexHeadType,
	[INVSLOT_CHEST]   = Enum.InventoryType.IndexChestType,
	[INVSLOT_WAIST]   = Enum.InventoryType.IndexWaistType,
	[INVSLOT_LEGS]    = Enum.InventoryType.IndexLegsType,
	[INVSLOT_FEET]    = Enum.InventoryType.IndexFeetType,
	[INVSLOT_WRIST]   = Enum.InventoryType.IndexWristType,
	[INVSLOT_HAND]    = Enum.InventoryType.IndexHandType,
	[INVSLOT_FINGER1] = Enum.InventoryType.IndexFingerType,
	[INVSLOT_FINGER2] = Enum.InventoryType.IndexFingerType,
	[INVSLOT_BACK]    = Enum.InventoryType.IndexCloakType,
}

-- Human-readable slot name for tooltips, via the InventoryType-based API.
function RRR:GetSlotDisplayName(slot)
	local category = PAPERDOLL_TO_INVTYPE[slot] or slot
	return C_Item.GetItemInventorySlotInfo(category) or "Unknown Slot"
end

local function RunesMatch(a, b)
	if a == nil and b == nil then
		return true
	end
	if a == nil or b == nil then
		return false
	end
	return a.skillLineAbilityID == b.skillLineAbilityID
end

function RRR:InitEngraving()
	RRR.slots = ALL_SLOTS
	RRR.runeCache = {}
	-- Blizzard's own EngravingFrame_OnShow always calls this before querying
	-- any rune data; GetRuneForEquipmentSlot returned nil for every slot
	-- without it, even for slots with a real engraved rune equipped.
	C_Engraving.RefreshRunesList()
	for _, slot in ipairs(RRR.slots) do
		RRR.runeCache[slot] = C_Engraving.GetRuneForEquipmentSlot(slot)
	end
end

-- Re-fetches every tracked slot's rune fresh and refreshes its button. The
-- slot set itself never changes, so this is just a full cache/UI refresh --
-- used after a loading screen, where equipment data may not have been fully
-- synced yet at the time InitEngraving originally ran.
function RRR:RefreshAllRunes()
	C_Engraving.RefreshRunesList()
	for _, slot in ipairs(RRR.slots) do
		RRR.runeCache[slot] = C_Engraving.GetRuneForEquipmentSlot(slot)
		if RRR.RefreshSlotButton then
			RRR:RefreshSlotButton(slot)
		end
	end
end

----------------------------------------------------------------------
-- Picker support
----------------------------------------------------------------------

-- Fresh query every time (no caching) so newly-learned runes show up
-- immediately without any extra event wiring.
function RRR:GetRunesForSlot(slot)
	local category = PAPERDOLL_TO_INVTYPE[slot] or slot
	local runes = C_Engraving.GetRunesForCategory(category, true)
	table.sort(runes, function(a, b) return a.name < b.name end)
	return runes
end

-- CastRune only selects the rune and enters "targeting mode" -- Blizzard's
-- own EngravingFrameSpell_OnClick does nothing more than this either. The
-- actual application to a specific slot happens when you then use/interact
-- with that inventory slot (UseInventoryItem(paperdollSlot)); if that slot
-- already has a different rune engraved, a native StaticPopupDialogs
-- ["REPLACE_ENCHANT"] confirmation appears, whose Yes button just calls
-- C_Item.ReplaceEnchant() (confirmed in
-- Blizzard_StaticPopup_Game/GameDialogDefs.lua). Calling that ourselves
-- auto-confirms the overwrite instead of requiring a manual Yes click --
-- this exact CastRune -> UseInventoryItem -> ReplaceEnchant sequence is
-- what the original RuneReminder addon used too (via the deprecated bare
-- global `ReplaceEnchant`, which is just an alias for C_Item.ReplaceEnchant
-- gated behind the loadDeprecationFallbacks CVar -- using the namespaced
-- form directly avoids that dependency). StaticPopup_Hide/ClearCursor are
-- defensive cleanup for the same reason the original called them.
function RRR:CastRuneOnSlot(rune, slot)
	local oldRune = RRR.runeCache[slot]

	ClearCursor()
	C_Engraving.CastRune(rune.skillLineAbilityID)
	if slot then
		UseInventoryItem(slot)
	end
	-- Auto-confirms the overwrite (see note above) with zero visual "are you
	-- sure" -- print a record of what happened so a misclick in the picker
	-- is at least visible after the fact.
	C_Item.ReplaceEnchant()
	StaticPopup_Hide("REPLACE_ENCHANT")
	ClearCursor()

	if oldRune and oldRune.skillLineAbilityID ~= rune.skillLineAbilityID then
		RRR:Print(string.format("Replaced |cffffcc00%s|r with |cffffcc00%s|r on your %s.",
			oldRune.name, rune.name, RRR:GetSlotDisplayName(slot)))
	end
end

----------------------------------------------------------------------
-- Event handlers
----------------------------------------------------------------------

function RRR:PLAYER_EQUIPMENT_CHANGED(_, slotID)
	local tracked = false
	for _, slot in ipairs(RRR.slots) do
		if slot == slotID then
			tracked = true
			break
		end
	end
	if not tracked then
		return
	end

	local oldRune = RRR.runeCache[slotID]
	local newRune = C_Engraving.GetRuneForEquipmentSlot(slotID)
	RRR.runeCache[slotID] = newRune

	if RRR.RefreshSlotButton then
		RRR:RefreshSlotButton(slotID)
	end

	-- Any further equipment change on this slot invalidates a still-open
	-- "Reapply?" prompt for it -- whether the rune's back or a different
	-- item entirely went on, the prompt's context is stale either way.
	if RRR.HideReapplyPrompt then
		RRR:HideReapplyPrompt(slotID)
	end

	if not RunesMatch(oldRune, newRune) then
		RRR:RuneMismatch(slotID, oldRune, newRune)
	end
end

-- PLAYER_LOGIN can fire before equipment/engraving data is fully synced from
-- the server, so InitEngraving's initial fetch may have grabbed stale/empty
-- rune data for some slots. Force a full re-fetch once the world is
-- actually entered.
--
-- A loading screen (hearth, taxi, dungeon/instance transition, etc.) can
-- finish -- firing this event -- before the server's actually finished
-- re-syncing engraving data to the client, so even this fetch can still
-- come back empty for every slot. One more pass a couple seconds later
-- catches that case without needing to hook additional events.
function RRR:PLAYER_ENTERING_WORLD()
	RRR:RefreshAllRunes()
	C_Timer.After(2, function()
		RRR:RefreshAllRunes()
	end)
end

-- Fires for any successful engrave (ours via the picker, Blizzard's own
-- character panel, or another addon) -- deliberate engraving is never a
-- mismatch, so this never routes through Notify.
--
-- rune.equipmentSlot (when non-nil) is an InventoryType category, not a
-- paperdoll slot -- and since Finger1/Finger2 share one category, it can't
-- be reliably mapped back to which specific tracked slot changed. Simplest
-- correct handling: always do a full refresh, matching the nil-rune case.
-- Cheap (10 API calls), and RUNE_UPDATED only fires on an actual engrave.
function RRR:RUNE_UPDATED(_, rune)
	RRR:RefreshAllRunes()
end
