--[[ RuneReminderReforged — bootstrap, shared namespace, utilities, event dispatch.

Lightweight live tracker for Season of Discovery engraving runes: a small
draggable row of per-slot buttons showing what's currently engraved, a
one-click picker to engrave a different rune, and a chat nudge when a gear
swap silently changes or clears a tracked slot's rune. Classic Era / Season
of Discovery only. Pure Lua, no XML, no third-party libraries.
]]

local ADDON, ns = ...

-- The public object. Modules hang methods off this; the event frame below
-- dispatches WoW events to same-named methods (e.g. RRR:PLAYER_EQUIPMENT_CHANGED).
local RRR = {}
_G.RuneReminderReforged = RRR
ns.RRR = RRR
ns.ADDON = ADDON

----------------------------------------------------------------------
-- Environment / constants
----------------------------------------------------------------------
RRR.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "0.0"

----------------------------------------------------------------------
-- Saved variables + defaults merge
----------------------------------------------------------------------
local DEFAULTS = {
	widget = {
		shown           = true,
		locked          = false,
		alignment       = "HORIZONTAL", -- or "VERTICAL"
		flyoutDirection = "UP",         -- or "DOWN", "LEFT", "RIGHT"
		scale           = 1.0,
		point           = { "CENTER", "UIParent", "CENTER", 0, 0 },
	},
	notify = {
		enabled = true,
	},
}

local function mergeDefaults(db, defaults)
	for k, v in pairs(defaults) do
		if db[k] == nil then
			db[k] = (type(v) == "table") and {} or v
		end
		if type(v) == "table" then
			mergeDefaults(db[k], v)
		end
	end
	return db
end

----------------------------------------------------------------------
-- Output helper
----------------------------------------------------------------------
local PREFIX = "|cff2da3cfRuneReminderReforged:|r "
function RRR:Print(...)
	print(PREFIX .. strjoin(" ", tostringall(...)))
end

----------------------------------------------------------------------
-- Event dispatch: RRR:RegisterEvent("X") -> calls RRR:X(event, ...)
----------------------------------------------------------------------
local frame = CreateFrame("Frame", "RuneReminderReforgedEventFrame")
ns.eventFrame = frame
local registered = {}

function RRR:RegisterEvent(event)
	if not registered[event] then
		registered[event] = true
		frame:RegisterEvent(event)
	end
end

function RRR:UnregisterEvent(event)
	if registered[event] then
		registered[event] = nil
		frame:UnregisterEvent(event)
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	local handler = RRR[event]
	if handler then
		handler(RRR, event, ...)
	end
end)

----------------------------------------------------------------------
-- Bootstrap lifecycle
----------------------------------------------------------------------
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

function RRR:ADDON_LOADED(_, name)
	if name ~= ADDON then return end
	RRR:UnregisterEvent("ADDON_LOADED")
	RuneReminderReforgedDB = RuneReminderReforgedDB or {}
	RRR.db = mergeDefaults(RuneReminderReforgedDB, DEFAULTS)
end

function RRR:PLAYER_LOGIN()
	RRR:InitEngraving() -- Core/Engraving.lua: slot discovery, rune cache, change detection
	RRR:InitPicker()     -- UI/Picker.lua: shared rune-selection dropdown
	RRR:BuildWidget()    -- UI/Widget.lua: draggable per-slot button row
	RRR:InitOptions()    -- UI/Options.lua: settings panel

	RRR:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	RRR:RegisterEvent("RUNE_UPDATED")
	RRR:RegisterEvent("PLAYER_ENTERING_WORLD")

	RRR:SetupSlash()
	RRR:Print("v" .. RRR.version .. " loaded. /rrr for options.")
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
function RRR:SetupSlash()
	SLASH_RUNEREMINDERREFORGED1 = "/rrr"
	SLASH_RUNEREMINDERREFORGED2 = "/runereminderreforged"
	_G.SlashCmdList["RUNEREMINDERREFORGED"] = function(msg)
		msg = (msg or ""):lower():trim()
		if msg == "show" then
			RRR:SetWidgetShown(true)
		elseif msg == "hide" then
			RRR:SetWidgetShown(false)
		else
			RRR:OpenOptions()
		end
	end
end
