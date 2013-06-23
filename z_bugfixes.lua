local _G = getfenv(0)
local object = _G.object

object.behaviorLib = object.behaviorLib or {}
local core, eventsLib, behaviorLib, metadata = object.core, object.eventsLib, object.behaviorLib, object.metadata

local print, ipairs, pairs, string, table, next, type, tinsert, tremove, tsort, format, tostring, tonumber, strfind, strsub
	= _G.print, _G.ipairs, _G.pairs, _G.string, _G.table, _G.next, _G.type, _G.table.insert, _G.table.remove, _G.table.sort, _G.string.format, _G.tostring, _G.tonumber, _G.string.find, _G.string.sub
local ceil, floor, pi, tan, atan, atan2, abs, cos, sin, acos, max, random
	= _G.math.ceil, _G.math.floor, _G.math.pi, _G.math.tan, _G.math.atan, _G.math.atan2, _G.math.abs, _G.math.cos, _G.math.sin, _G.math.acos, _G.math.max, _G.math.random

local nSqrtTwo = math.sqrt(2)

local BotEcho, VerboseLog, Clamp = core.BotEcho, core.VerboseLog, core.Clamp

-- Fix PathLogic: if bot moves out of range of next path node, make a new path
-- http://forums.heroesofnewerth.com/showthread.php?497454-Patch-behaviorLib-PathLogic-make-new-path-when-next-node-is-way-out-of-range

--[[
description:		Check if the first Vector is further away from the base then the second.
]]
function core.IsFirstFurthestAwayFromBase(vecCreepWave, vecNode)
	--TODO: Replace distance calculations with a cheaper formula
	local vecWell = core.allyWell:GetPosition();
	local nBaseCreepWaveDistanceSq = Vector3.Distance2DSq(vecWell, vecCreepWave);
	local nBaseCurrentNodeDistanceSq = Vector3.Distance2DSq(vecWell, vecNode);
	
	if nBaseCreepWaveDistanceSq > nBaseCurrentNodeDistanceSq then
		return true;
	else
		return false;
	end
end

--[[ function core.GetLaneSafeZoneEdge(tLanePath)
description:		Returns the location to which the lane is safe.
returns:			(Vector3) The location in the lane where the lane stops being safe.
]]
function core.GetLaneSafeZoneEdge(tLanePath)
	local vecCreepWavePos = core.GetFurthestCreepWavePos(tLanePath, core.bTraverseForward)
	
	local vecFurthestTower = core.GetFurthestLaneTower(tLanePath, core.bTraverseForward, core.myTeam);
	if vecFurthestTower and core.IsFirstFurthestAwayFromBase(vecFurthestTower:GetPosition(), vecCreepWavePos) then
		return vecFurthestTower:GetPosition();
	else
		return vecCreepWavePos;
	end
end

-- The value of this should be the max distance between two nodes in the test.botmetadata file + nPathDistanceToleranceSq
behaviorLib.nRepathIfFurtherAwayThenSq = 3500 * 3500
behaviorLib.nPathEnemyCreepWaveMul = 3.0
behaviorLib.nPathMyLaneMul = -0.2 -- must be between -0 and -1 (above 0 would mean we punish for walking through our lane, which isn't what we want). After testing different values -0.2 seemed to be just enough to get the bot to favour his lane path slightly while not increasing the path length by much.
behaviorLib.nPathHeroRangeThresholdSq = 750 * 750;
behaviorLib.nPathHeroMul = 4.0
function behaviorLib.PathLogic(botBrain, vecDesiredPosition)
	local bDebugLines = false
	local bDebugEchos = false
	local bMarkProperties = false
	
	--if object.myName == "GlaciusSupportBot" then bDebugLines = true end
	
	local bRepath = false
	if Vector3.Distance2DSq(vecDesiredPosition, behaviorLib.vecGoal) > behaviorLib.nGoalToleranceSq then
		bRepath = true
	elseif behaviorLib.tPath and behaviorLib.tPath[behaviorLib.nPathNode] and Vector3.Distance2DSq(behaviorLib.tPath[behaviorLib.nPathNode]:GetPosition(), core.unitSelf:GetPosition()) > behaviorLib.nRepathIfFurtherAwayThenSq then
		-- If we're far away from the current path node we should repath (this can happen after a port, or when a behavior sends us elsewhere without using the PathLogic)
		bRepath = true
	end
	
	local unitSelf = core.unitSelf
	local vecMyPosition = unitSelf:GetPosition()
	
	if bRepath then
		if bDebugEchos then BotEcho("Repathing!") end
		
		local sEnemyZone = "hellbourne"
		if core.myTeam == HoN.GetHellbourneTeam() then
			sEnemyZone = "legion"
		end
		
		if bDebugEchos then BotEcho("enemy zone: "..sEnemyZone) end
		
		local nEnemyTerritoryMul = behaviorLib.nPathEnemyTerritoryMul
		local nTowerMul          = behaviorLib.nPathTowerMul
		local nBaseMul           = behaviorLib.nPathBaseMul
		local nEnemyCreepWaveMul = behaviorLib.nPathEnemyCreepWaveMul
		
		-- Look where the safe zone edges are. This data is filled the first time we need it.
		local vecTopSafeZoneEdgePos, vecMidSafeZoneEdgePos, vecBotSafeZoneEdgePos;
		
		-- Get my lane name
		local tMyLanePath = core.teamBotBrain:GetDesiredLane(core.unitSelf);
		local sMyLaneName = (tMyLanePath and tMyLanePath.sLaneName) or '';
		
		--TODO: Add remembered unit locations so heroes disappearing into the fog aren't immediately forgotten
		local tVisibleHeroes, nVisibleHeroes = {}, 0;
		for _, unit in pairs(HoN.GetUnitsInRadius(Vector3.Create(), 99999, core.UNIT_MASK_ALIVE + core.UNIT_MASK_HERO)) do
			tinsert(tVisibleHeroes, { unit:GetPosition(), (unit:GetTeam() == core.myTeam) });
			nVisibleHeroes = nVisibleHeroes + 1;
		end
		
		local function funcNodeCost(nodeParent, nodeCurrent, link, nOriginalCost)
			--TODO: local nDistance = link:GetLength()
			local nDistance = Vector3.Distance(nodeParent:GetPosition(), nodeCurrent:GetPosition())
			local nCostToParent = nOriginalCost - nDistance
			
			--BotEcho(format("nOriginalCost: %s  nDistance: %s  nSq: %s", nOriginalCost, nDistance, nDistance*nDistance))
		
			local sLaneProperty  = nodeCurrent:GetProperty("lane")
			local sZoneProperty  = nodeCurrent:GetProperty("zone")
			local bTowerProperty = nodeCurrent:GetProperty("tower")
			local bBaseProperty  = nodeCurrent:GetProperty("base")
			
			local nMultiplier = 1.0
			local bEnemyZone = false
			if sZoneProperty and sZoneProperty == sEnemyZone then
				bEnemyZone = true
			end
			
			do -- Consider hero positions
				local nHostileHeroes, nFriendlyHeroes = 0, 0;
				for i = 1, nVisibleHeroes do
					local hero = tVisibleHeroes[i];
					
					if Vector3.Distance2DSq(hero[1], nodeCurrent:GetPosition()) < behaviorLib.nPathHeroRangeThresholdSq then
						-- If this hero is within range
						if hero[2] then
							-- If the hero is friendly reduce multiplier
							nFriendlyHeroes = nFriendlyHeroes + 1;
						else
							-- If the hero is hostile increase multiplier
							nHostileHeroes = nHostileHeroes + 1;
						end
					end
				end
				
				if nHostileHeroes > 0 and nFriendlyHeroes == 0 then -- if there are 1 or more hostile heroes but no friendly heroes manning up, then try to avoid them
					nMultiplier = nMultiplier + behaviorLib.nPathHeroMul * nHostileHeroes;
				end
			end
			
			-- Consider creep wave positions
			if sLaneProperty then
				local vecSafeZoneEdge;
				if sLaneProperty == 'top' then
					if vecTopSafeZoneEdgePos == nil then
						vecTopSafeZoneEdgePos = core.GetLaneSafeZoneEdge(metadata.GetTopLane());
					end
					vecSafeZoneEdge = vecTopSafeZoneEdgePos;
				elseif sLaneProperty == 'middle' then
					if vecMidSafeZoneEdgePos == nil then
						vecMidSafeZoneEdgePos = core.GetLaneSafeZoneEdge(metadata.GetMiddleLane());
					end
					vecSafeZoneEdge = vecMidSafeZoneEdgePos;
				elseif sLaneProperty == 'bottom' then
					if vecBotSafeZoneEdgePos == nil then
						vecBotSafeZoneEdgePos = core.GetLaneSafeZoneEdge(metadata.GetBottomLane());
					end
					vecSafeZoneEdge = vecBotSafeZoneEdgePos;
				end
				
				if vecSafeZoneEdge ~= nil then
					if core.IsFirstFurthestAwayFromBase(nodeCurrent:GetPosition(), vecSafeZoneEdge) == true then
						-- This node is further out the base then the creep wave position, so it's dangerous territory
						nMultiplier = nMultiplier + nEnemyCreepWaveMul
					elseif sLaneProperty == sMyLaneName then
						-- We're behind our creep wave, if this is our own lane we give this bonus cost since it's definitely a much saver area then 
						-- cruising through forest, river and thus past wards or over mines. Plus it's probably much more like what a Human would do.
						
						nMultiplier = nMultiplier + behaviorLib.nPathMyLaneMul
					end
				end
			end
			
			-- Consider hostile tower locations
			if bEnemyZone then
				nMultiplier = nMultiplier + nEnemyTerritoryMul
				if bBaseProperty then
					nMultiplier = nMultiplier + nBaseMul
				end
				
				if bTowerProperty then
					--check if the tower is there
					local tBuildings = HoN.GetUnitsInRadius(nodeCurrent:GetPosition(), 800, core.UNIT_MASK_ALIVE + core.UNIT_MASK_BUILDING)
					
					for _, unitBuilding in pairs(tBuildings) do
						if unitBuilding:IsTower() then
							nMultiplier = nMultiplier + nTowerMul
							break
						end
					end
				end
			end
			
			return nCostToParent + nDistance * nMultiplier
		end
	
		behaviorLib.tPath = BotMetaData.FindPath(vecMyPosition, vecDesiredPosition, funcNodeCost)
		behaviorLib.vecGoal = vecDesiredPosition
		behaviorLib.nPathNode = 1
		
		--double check the first node since we have a really sparse graph
		local tPath = behaviorLib.tPath
		if #tPath > 1 then
			local vecMeToFirst = tPath[1]:GetPosition() - vecMyPosition
			local vecFirstToSecond = tPath[2]:GetPosition() - tPath[1]:GetPosition()
			if Vector3.Dot(vecMeToFirst, vecFirstToSecond) < 0 then
				--don't go backwards, skip the first
				behaviorLib.nPathNode = 2
			end
		end
	end
	
	--Follow path logic
	local vecReturn = nil
	
	local tPath = behaviorLib.tPath
	local nPathNode = behaviorLib.nPathNode
	if tPath then
		local vecCurrentNode = tPath[nPathNode]
		if vecCurrentNode then
			if Vector3.Distance2DSq(vecCurrentNode:GetPosition(), vecMyPosition) < behaviorLib.nPathDistanceToleranceSq then
				nPathNode = nPathNode + 1
				behaviorLib.nPathNode = nPathNode				
			end
			
			local nodeWaypoint = tPath[behaviorLib.nPathNode]
			if nodeWaypoint then
				vecReturn = nodeWaypoint:GetPosition()
			end
		end
	end
	
	if bDebugLines then
		if tPath ~= nil then
			local nLineLen = 300
			local vecLastNodePosition = nil
			for i, node in ipairs(tPath) do
				local vecNodePosition = node:GetPosition()
				
				if bMarkProperties then
					local sZoneProperty  = node:GetProperty("zone")
					local bTowerProperty = node:GetProperty("tower")
					local bBaseProperty  = node:GetProperty("base")
					
					local bEnemyZone = false
					local sEnemyZone = "hellbourne"
					if core.myTeam == HoN.GetHellbourneTeam() then
						sEnemyZone = "legion"
					end
					if sZoneProperty and sZoneProperty == sEnemyZone then
						bEnemyZone = true
					end				
					if bEnemyZone then
						core.DrawDebugLine(vecNodePosition, vecNodePosition + Vector3.Create(0, 1) * nLineLen, "red")

						if bBaseProperty then
							core.DrawDebugLine(vecNodePosition, vecNodePosition + Vector3.Create(1, 0) * nLineLen, "orange")
						end
						if bTowerProperty then
							--check if the tower is there
							local tBuildings = HoN.GetUnitsInRadius(node:GetPosition(), 800, core.UNIT_MASK_ALIVE + core.UNIT_MASK_BUILDING)
							
							for _, unitBuilding in pairs(tBuildings) do
								if unitBuilding:IsTower() then
									core.DrawDebugLine(vecNodePosition, vecNodePosition + Vector3.Create(-1, 0) * nLineLen, "yellow")
									break
								end
							end
						end
					end
				end
			
				if vecLastNodePosition then
					--node to node
					if bDebugLines then
						core.DrawDebugArrow(vecLastNodePosition, vecNodePosition, 'blue')
					end
				end
				vecLastNodePosition = vecNodePosition
			end
			core.DrawXPosition(vecReturn, 'yellow')
			core.DrawXPosition(behaviorLib.vecGoal, "orange")
			core.DrawXPosition(vecDesiredPosition, "teal")
			
			core.DrawXPosition(core.GetLaneSafeZoneEdge(metadata.GetTopLane()), "red")
			core.DrawXPosition(core.GetLaneSafeZoneEdge(metadata.GetMiddleLane()), "red")
			core.DrawXPosition(core.GetLaneSafeZoneEdge(metadata.GetBottomLane()), "red")
		end
	end
	
	return vecReturn
end

-- Fix MoveExecute: Stick with taking a shortcut if we have chosen to do so once
-- http://forums.heroesofnewerth.com/showthread.php?497376-Bug-MoveExecute-bug-bot-gets-stuck

local vecMoveExecuteNearbyDestination
function behaviorLib.MoveExecute(botBrain, vecDesiredPosition)
	if bDebugEchos then BotEcho("Movin'") end
	local bActionTaken = false
	
	local unitSelf = core.unitSelf
	local vecMyPosition = unitSelf:GetPosition()
	local vecMovePosition = vecDesiredPosition
	
	if vecMoveExecuteNearbyDestination then
		if Vector3.Distance2DSq(vecDesiredPosition, vecMoveExecuteNearbyDestination) > behaviorLib.nGoalToleranceSq then
			vecMoveExecuteNearbyDestination = nil
		end
	end
	
	local nDesiredDistanceSq = Vector3.Distance2DSq(vecDesiredPosition, vecMyPosition)
	if not vecMoveExecuteNearbyDestination and nDesiredDistanceSq > core.nOutOfPositionRangeSq then
		--check porting
		if bActionTaken == false then
			StartProfile("PortLogic")
				local bPorted = behaviorLib.PortLogic(botBrain, vecDesiredPosition)
			StopProfile()
			
			if bPorted then
				if bDebugEchos then BotEcho("Portin'") end
				bActionTaken = true
			end
		end
		
		if bActionTaken == false then
			--we'll need to path there
			if bDebugEchos then BotEcho("Pathin'") end
			StartProfile("PathLogic")
				local vecWaypoint = behaviorLib.PathLogic(botBrain, vecDesiredPosition)
			StopProfile()
			if vecWaypoint then
				vecMovePosition = vecWaypoint
			end
		end
	elseif not vecMoveExecuteNearbyDestination then
		vecMoveExecuteNearbyDestination = vecDesiredPosition
	end
	
	--move out
	if bActionTaken == false then
		if bDebugEchos then BotEcho("Move 'n' hold order") end
		bActionTaken = core.OrderMoveToPosAndHoldClamp(botBrain, unitSelf, vecMovePosition)
	end
	
	return bActionTaken
end

-- Fix ProcessChatMessages: TeamChat should be ChatTeam
-- http://forums.heroesofnewerth.com/showthread.php?497377-Bug-core-TeamChat-doesn-t-work

-- Each entry in core.tMessageList is {nTimeToSend, bAllChat, sMessage}
function core.ProcessChatMessages(botBrain)
	local nCurrentTime = HoN.GetGameTime()
	local tOutMessages = {}
	
	-- Current Schema:
	--{nDelayMS, bAllChat, sMessage, bLocalizeMessage, tStringTableTokens}
	
	for key, tMessageStruct in pairs(core.tMessageList) do
		if tMessageStruct[1] < nCurrentTime then
			tinsert(tOutMessages, tMessageStruct)
			core.tMessageList[key] = nil
		end
	end
	
	if #tOutMessages > 1 then	
		BotEcho("tOutMessages pre:")
		core.printTableTable(tOutMessages)
		tsort(tOutMessages, function(a,b) return (a[1] < b[1]) end)
		BotEcho("tOutMessages post:")
		core.printTableTable(tOutMessages)
	end
	
	for i, tMessageStruct in ipairs(tOutMessages) do
		local bAllChat = tMessageStruct[2]
		local sMessage = tMessageStruct[3]
		local bLocalizeMessage = tMessageStruct[4]
		local tStringTableTokens = tMessageStruct[5]
		
		if bLocalizeMessage == true then
			botBrain:SendBotMessage(bAllChat, sMessage, tStringTableTokens)
		else
			if bAllChat == true then
				botBrain:Chat(sMessage)
			else
				botBrain:ChatTeam(sMessage)
			end
		end
	end
end

-- Fix for BuildLanes: set bLanesBuilt to true if lanes have been build

local oldCoreInitialize = core.CoreInitialize;
function core.CoreInitialize(botBrain, ...)
	local teamBotBrain = HoN.GetTeamBotBrain();
	if not teamBotBrain.BuildLanesFixed then
		teamBotBrain.BuildLanesFixOldBuildLanes = teamBotBrain.BuildLanes;
		function teamBotBrain:BuildLanes()
			local returnValue = self:BuildLanesFixOldBuildLanes();
			self.bLanesBuilt = true;
			Echo('^y' .. teamBotBrain.myName .. ': Building lanes.');
			return returnValue;
		end
		teamBotBrain.BuildLanesFixed = true;
	end
	
	local CoreInitializeReturnValue = oldCoreInitialize(botBrain, ...);
	
	return CoreInitializeReturnValue;
end

-- Patch for denying towers
-- Source: http://forums.heroesofnewerth.com/showthread.php?492138-Denying-behavior

behaviorLib.towerToDeny = nil
function behaviorLib.DenyUtility(botBrain)
        if core.nDifficulty == core.nEASY_DIFFICULTY then
                --dont deny on easy
                return 0
        end
        for _,tower in pairs(core.localUnits["AllyTowers"]) do --There should be 1 or 0
                if tower:GetHealthPercent() < 0.10 then
                        if core.NumberElements(core.localUnits["Enemies"]) == 0 then
                                --no one here so just deny it
                                behaviorLib.towerToDeny = tower
                                return 50
                        end
                        if core.nDifficulty == core.nHARD_DIFFICULTY then
                                --On hard try deny when thers enemies near
                                if tower:GetHealth() <= core.unitSelf:GetAttackDamageMin() * (1 - tower:GetPhysicalResistance()) then
                                        --deny it NOW
                                        if core.GetAbsoluteAttackRangeToUnit(core.unitSelf, behaviorLib.towerToDeny, true) > Vector3.Distance2DSq(core.unitSelf:GetPosition(), tower:GetPosition()) then
                                                --more priority if we are actually close enought
                                                behaviorLib.towerToDeny = tower
                                                return 55
                                        end
                                        behaviorLib.towerToDeny = tower
                                        return 50
                                else
                                        if tower:GetHealthPercent() < 0.05 then
                                                if core.GetAbsoluteAttackRangeToUnit(core.unitSelf, behaviorLib.towerToDeny, true) < Vector3.Distance2DSq(core.unitSelf:GetPosition(), tower:GetPosition()) then
                                                        --To walk near and get ready
                                                        --melee heroes  particularly
                                                        behaviorLib.towerToDeny = tower
                                                        return 45
                                                end
                                        end
                                end
                        end
                end
        end
        return 0
end
 
function behaviorLib.DenyExecute(botBrain)
        actionTaken = false
        if core.NumberElements(core.localUnits["Enemies"]) == 0 then
                actionTaken = core.OrderAttack(botBrain, core.unitSelf, behaviorLib.towerToDeny)
        else
                if core.GetAbsoluteAttackRangeToUnit(core.unitSelf, behaviorLib.towerToDeny, true) >= Vector3.Distance2DSq(core.unitSelf:GetPosition(), behaviorLib.towerToDeny:GetPosition()) then
                        if behaviorLib.towerToDeny:GetHealth() <= core.unitSelf:GetAttackDamageMin() * (1 - behaviorLib.towerToDeny:GetPhysicalResistance()) then
                                actionTaken = core.OrderAttack(botBrain, core.unitSelf, behaviorLib.towerToDeny)
                        end
                else
                        actionTaken = core.OrderMoveToUnit(botBrain, core.unitSelf, behaviorLib.towerToDeny, true, false)
                end
        end
        return actionTaken
end
 
behaviorLib.DenyBehavior = {}
behaviorLib.DenyBehavior["Utility"] = behaviorLib.DenyUtility
behaviorLib.DenyBehavior["Execute"] = behaviorLib.DenyExecute
behaviorLib.DenyBehavior["Name"] = "Deny"
tinsert(behaviorLib.tBehaviors, behaviorLib.DenyBehavior)
