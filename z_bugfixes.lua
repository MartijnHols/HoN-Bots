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
