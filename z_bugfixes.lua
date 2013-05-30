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

behaviorLib.nRepathIfFurtherAwayThenSq = 2000 * 2000
function behaviorLib.PathLogic(botBrain, vecDesiredPosition)
	local bDebugLines = false
	local bDebugEchos = false
	local bMarkProperties = false
	
	--if object.myName == "ShamanBot" then bDebugLines = true bDebugEchos = true end
	
	local bRepath = false
	if Vector3.Distance2DSq(vecDesiredPosition, behaviorLib.vecGoal) > behaviorLib.nGoalToleranceSq then
		bRepath = true
	elseif behaviorLib.tPath and behaviorLib.tPath[behaviorLib.nPathNode] and Vector3.Distance2DSq(behaviorLib.tPath[behaviorLib.nPathNode]:GetPosition(), core.unitSelf:GetPosition()) > behaviorLib.nRepathIfFurtherAwayThenSq then
		-- If we're far away from the current path node we should repath
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
		
		local function funcNodeCost(nodeParent, nodeCurrent, link, nOriginalCost)
			--TODO: local nDistance = link:GetLength()
			local nDistance = Vector3.Distance(nodeParent:GetPosition(), nodeCurrent:GetPosition())
			local nCostToParent = nOriginalCost - nDistance
			
			--BotEcho(format("nOriginalCost: %s  nDistance: %s  nSq: %s", nOriginalCost, nDistance, nDistance*nDistance))
		
			local sZoneProperty  = nodeCurrent:GetProperty("zone")
			local bTowerProperty = nodeCurrent:GetProperty("tower")
			local bBaseProperty  = nodeCurrent:GetProperty("base")
			
			local nMultiplier = 1.0
			local bEnemyZone = false
			if sZoneProperty and sZoneProperty == sEnemyZone then
				bEnemyZone = true
			end
			
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

