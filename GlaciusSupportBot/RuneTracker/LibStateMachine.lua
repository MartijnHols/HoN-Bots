-- statemachinelib v1.02 by Fanha
local _G = getfenv(0)
local object = _G.object

object.statemachinelib = object.statemachinelib or {}
local statemachinelib = object.statemachinelib

local print, ipairs, pairs, string, table, next, type, tinsert, tremove, tsort, format, tostring, tonumber, strfind, strsub
	= _G.print, _G.ipairs, _G.pairs, _G.string, _G.table, _G.next, _G.type, _G.table.insert, _G.table.remove, _G.table.sort, _G.string.format, _G.tostring, _G.tonumber, _G.string.find, _G.string.sub

local core = object.core
local BotEcho, VerboseLog, BotLog = core.BotEcho, core.VerboseLog, core.BotLog

BotEcho('loading statemachinelib...')

-- Runs update function for the current state
local function StateMachineUpdate(sm)
	if sm.stateCurrent ~= nil and sm.stateCurrent.onupdate ~= nil then
		sm.stateCurrent:onupdate()
	end
end

-- Changes the current state
-- sName: Name of the state to change to
-- bForced: Set to true to supress the onenter/onleave events
local function StateMachineChangeState(sm,sName,bForced)
	if sName == nil then
		BotEcho('statemachine:ChangeState ('..sm.sName..') Attempted to change to nil state')
		return false
	end
	
	local stateNext = sm:FindState(sName)
	
	if stateNext == nil then
		BotEcho('statemachine:ChangeState ('..sm.sName..') Could not find a state named '..sName)
		return false
	end
	
	local statePrevious = sm.stateCurrent
	
	if not bForced then
		if statePrevious ~= nil then
			if statePrevious.onleave ~= nil then
				statePrevious:onleave(stateNext)
			end
		end
	end
	
	sm.stateCurrent = stateNext
	
	if not bForced then
		if stateNext.onenter ~= nil then
			stateNext:onenter(statePrevious)
		end
	end
	
	if not bForced and sm.onstatechange ~= nil then
		sm.onstatechange(statePrevious,stateNext)
	end
	
	if sm.bLogStateChanges then
		local sPreviousStateName = '[nil]'
		if statePrevious ~= nil then
			sPreviousStateName = statePrevious.sName
		end
		BotEcho('statemachine:ChangeState ('..sm.sName..') Change successful from state '..sPreviousStateName..' to '..stateNext.sName)
	end
	
	return true
end

-- Checks if the state machine has a state of the given name and if so, returns it
-- sName: Name of the state to look for
local function StateMachineFindState(sm, sName)
	return sm.tStates[sName]
end

-- Creates a new state
-- sName: Name of the state
-- Events expected (all pass the state as the first arg):
-- onupdate: Function to be called each time the state machine update is called while in this state (no other args)
-- onenter: Function to be called when entering the state (args: stateFrom)
-- onleave: Function to be called when leaving the state (args: stateTo)
function StateMachineCreateState(sm, sName)
	if sName == nil then
		BotEcho('statemachine.CreateState Attempted to create a state with no name')
		return nil
	end

	local stateNew = {}
	stateNew.sName = sName
	stateNew.onupdate = nil
	stateNew.onenter = nil
	stateNew.onleave = nil
	sm.tStates[sName] = stateNew
	return stateNew
end

-- Creates a new state machine
-- name: Name of the state machine
-- Events expected:
-- onstatechange: Function to be called when a new state has been entered (args: stateFrom, stateTo)
function statemachinelib.CreateStateMachine(sName)
	local smNew = {}
	smNew.sName = sName
	smNew.bLogStateChanges = false
	smNew.stateCurrent = nil
	smNew.tStates = {}
	
	smNew.Update = StateMachineUpdate
	smNew.ChangeState = StateMachineChangeState
	smNew.FindState = StateMachineFindState
	smNew.CreateState = StateMachineCreateState
	
	smNew.onstatechange = nil
	
	BotEcho('statemachinelib.CreateStateMachine Created new state machine '..sName..' successfully')
	
	return smNew
end

BotEcho('finished loading statemachinelib')