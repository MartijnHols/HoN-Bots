-- runetracker v1.02 by Fanha
local _G = getfenv(0)
local object = _G.object

object.runeTracker = object.runeTracker or {}
local runeTracker = object.runeTracker

runfile (object.sBotFilesRoot .. "RuneTracker/LibStateMachine.lua");

local print, ipairs, pairs, string, table, next, type, tinsert, tremove, tsort, format, tostring, tonumber, strfind, strsub
	= _G.print, _G.ipairs, _G.pairs, _G.string, _G.table, _G.next, _G.type, _G.table.insert, _G.table.remove, _G.table.sort, _G.string.format, _G.tostring, _G.tonumber, _G.string.find, _G.string.sub
local ceil, floor, pi, tan, atan, atan2, abs, cos, sin, acos, max, random
	= _G.math.ceil, _G.math.floor, _G.math.pi, _G.math.tan, _G.math.atan, _G.math.atan2, _G.math.abs, _G.math.cos, _G.math.sin, _G.math.acos, _G.math.max, _G.math.random
	
local core, statemachinelib = object.core, object.statemachinelib
local BotEcho, VerboseLog, BotLog = core.BotEcho, core.VerboseLog, core.BotLog

BotEcho('loading runeTracker...')

local smRuneTracker = statemachinelib.CreateStateMachine('RuneTracker')
-- Uncomment for debug state logging
-- smRuneTracker.bLogStatechanges = true

local nCachedMatchTimeMS = nil
local nNextRuneTimeMS = 120000
local nNextUpdateTimeMS = 120000
local nUpdateFrequencyMS = 500 -- Default ms update frequency
local bMayBeTop = false
local bMayBeBottom = false
local bIsTop = false
local bIsBottom = false
local unitLastRuneSeen = nil

local vecTopRunePosition = Vector3.Create(5824,9728)
local vecBottomRunePosition = Vector3.Create(11136, 5376)

-- Returns the rune unit seen since the last update, if there was one
function runeTracker.GetCurrentRune()
	return unitLastRuneSeen
end

-- Return true if the rune is visble top
function runeTracker.IsTop()
	return bIsTop
end

-- Returns true if the rune is visible bottom
function runeTracker.IsBottom()
	return bIsBottom
end

-- Returns true if we haven't confirmed it is not top
function runeTracker.MayBeTop()
	return bMayBeTop
end

-- Returns true if we haven't confirmed it is not bottom
function runeTracker.MayBeBottom()
	return bMayBeBottom
end

-- Returns true if the rune is visible
function runeTracker.IsVisible()
	return bIsTop or bIsBottom
end

-- Returns true if the rune is known to not be at either spawn
function runeTracker.IsLost()
	return not bMayBeTop and not bMayBeBottom
end

-- Gets the Vector3 of the top rune spawn position
function runeTracker.GetTopRunePosition()
	return vecTopRunePosition
end

-- Gets the Vector3 of the bottom rune spawn position
function runeTracker.GetBottomRunePosition()
	return vecBottomRunePosition
end

-- Set the frequency at which to poll for visible indications of a rune
-- NOTE: This will not affect the 2-minute rune checks, which will always run on-time
function runeTracker.SetUpdateFrequency(msFrequency)
	nUpdateFrequencyMS = msFrequency
end

-- Resets the rune knowledge, usually when a new rune spawns
local function ResetToUnknown()
	smRuneTracker:ChangeState('Unknown')
	bMayBeTop = true
	bMayBeBottom = true
end

-- Checks for the 2-minute cycle reset, and if we can't see the rune when it happens, assume it might have respawned
local function ResetRuneSpawnIfNecessary()
	if nCachedMatchTimeMS ~= nil and nCachedMatchTimeMS > nNextRuneTimeMS then
		nNextRuneTimeMS = (floor( nCachedMatchTimeMS / 120000 ) + 1) * 120000
		if not runeTracker.IsVisible() then
			ResetToUnknown()
		end
	end
end

-- Update the state of the rune spawn
function runeTracker.Update()
	nCachedMatchTimeMS = HoN.GetMatchTime()
	-- If the match has started
	if nCachedMatchTimeMS ~= nil	then
		-- Update on the interval or on a 2-minute mark
		if nCachedMatchTimeMS > nNextRuneTimeMS or nCachedMatchTimeMS >= nNextUpdateTimeMS then
			smRuneTracker:Update()
			ResetRuneSpawnIfNecessary()
			nNextUpdateTimeMS = nNextUpdateTimeMS + nUpdateFrequencyMS
		end
	end
end

-- Called when it is determined the rune is visible top
local function AssertVisibleTop()
	smRuneTracker:ChangeState('Visible')
	bMayBeBottom = false
	bIsTop = true
end

-- Called when it is determined the rune is visible bottom
local function AssertVisibleBottom()
	smRuneTracker:ChangeState('Visible')
	bMayBeTop = false
	bIsBottom = true
end

-- If both spawns have been ruled out, mark the rune lost
local function DeclareLostIfOutOfOptions()
	if not bMayBeTop and not bMayBeBottom then
		smRuneTracker:ChangeState('Lost')
	end
end

-- Checks for vision and a rune at a location
-- Returns nil if no vision, false if it's visibly not present, or true if found
-- Caches the unit in unitLastRuneSeen
local function PeekForRuneAtLocation(vecPosition)
	if HoN.CanSeePosition(vecPosition) then
		local powerups = HoN.GetUnitsInRadius(vecPosition,2000,core.UNIT_MASK_ALIVE + core.UNIT_MASK_POWERUP)
		if powerups ~= nil and core.NumberElements(powerups) > 0 then
			for _,powerup in pairs(powerups) do
				unitLastRuneSeen = powerup
				break
			end
			return true
		else
			return false
		end
	else
		return nil
	end
end

-- State: Unknown
smRuneTracker.stateUnknown = smRuneTracker:CreateState('Unknown')

function smRuneTracker.stateUnknown:onupdate()
	-- Check for vision on the top rune
	local bPeekTop = PeekForRuneAtLocation(vecTopRunePosition)
	
	if bPeekTop ~= nil then
		-- Have vision on the top
		if bPeekTop then
			-- The rune is there
			AssertVisibleTop()
			return
		else
			-- The rune is not there
			bMayBeTop = false
		end
	end
	
	-- Check for vision on the bottom rune
	local bPeekBottom = PeekForRuneAtLocation(vecBottomRunePosition)
	
	if bPeekBottom ~= nil then
		-- Have vision on the bottom
		if bPeekBottom then
			-- The rune is there
			AssertVisibleBottom()
			return
		else
			-- The rune is not there
			bMayBeBottom = false
		end
	end
	
	-- TODO: Check for heroes with a rune buff, or in a bottle
	
	-- TODO: Check for illusions (?)
	
	DeclareLostIfOutOfOptions()
end

-- State: Lost
smRuneTracker.stateLost = smRuneTracker:CreateState('Lost')

function smRuneTracker.stateLost:onenter(statePrevious)
	bMayBeTop = false
	bMayBeBottom = false
end

-- State: Visible
smRuneTracker.stateVisible = smRuneTracker:CreateState('Visible')

function smRuneTracker.stateVisible:onupdate()
	-- Poll to see if it's still at the location we saw it
	local bPeek
	
	if bIsTop then
		bPeek = PeekForRuneAtLocation(vecTopRunePosition)
	else
		bPeek = PeekForRuneAtLocation(vecBottomRunePosition)
	end
	
	if bPeek == nil then
		-- Lost vision
		smRuneTracker:ChangeState('Unknown')
	elseif bPeek == false then
		-- The rune has been taken
		smRuneTracker:ChangeState('Lost')
	end
end

-- When the rune is no longer visible, reset definite knowledge
function smRuneTracker.stateVisible:onleave(stateNext)
	unitLastRuneSeen = nil
	bIsTop = false
	bIsBottom = false
end

-- Set initial state to not spawned/unknown based on the time
if HoN.GetMatchTime() == nil or HoN.GetMatchTime() < 120000 then
	smRuneTracker:ChangeState('Lost')
else
	ResetToUnknown()
end

BotEcho('finished loading runeTracker')
