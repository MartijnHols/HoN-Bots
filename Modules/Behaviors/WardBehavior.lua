local _G = getfenv(0);
local object = _G.object;

object.behaviorLib = object.behaviorLib or {};

local core, eventsLib, behaviorLib, metadata = object.core, object.eventsLib, object.behaviorLib, object.metadata;

if not _G.table.join then
	--[[ function table.join(table, separator)
	description:		Join all items in a table into a string
	parameters:			table				The table to join together
						separator			The separator (or glue) to separate the table records within the string.
	return:				A string of the entire table contents.
	]]
	function _G.table.join(table, separator)
		local result = '';
		
		for k, v in pairs(table) do
			if result == '' then
				result = v;
			else
				result = result .. separator .. v;
			end
		end
		
		return result;
	end
end

local print, ipairs, pairs, string, table, next, type, tinsert, tremove, tsort, tjoin, format, tostring, tonumber, strfind, strsub
	= _G.print, _G.ipairs, _G.pairs, _G.string, _G.table, _G.next, _G.type, _G.table.insert, _G.table.remove, _G.table.sort, _G.table.join, _G.string.format, _G.tostring, _G.tonumber, _G.string.find, _G.string.sub;
local ceil, floor, pi, tan, atan, atan2, abs, cos, sin, acos, max, random, Vector3
	= _G.math.ceil, _G.math.floor, _G.math.pi, _G.math.tan, _G.math.atan, _G.math.atan2, _G.math.abs, _G.math.cos, _G.math.sin, _G.math.acos, _G.math.max, _G.math.random, _G.Vector3;

local BotEcho, VerboseLog, Clamp = core.BotEcho, core.VerboseLog, core.Clamp;

-- Source: http://forums.heroesofnewerth.com/showthread.php?470402-Snippet-Compedium
local function VectorDistance2D(vec1, vec2) 
	local vec = vec1 - vec2;
	
    local x = vec.x
    local y = vec.y
 
    if x==0 then return y end
    if y==0 then return x end
 
    local angle = atan2(y,x)
    return y/sin(angle)
end

-------------------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------- Warding behavior v1.0.1RC (by Zerotorescue) -----------------------------------------------------
--- A WardBehavior implementation that works on all bots. It activates if the user has a ward of sight in his bags, a ward can be placed and if		---
--- the ward spot is within reasonable range of the hero. It then proceeds to choose the most optimal ward spot available taking into account		---
--- several different factors, such as if there is a rune ward up, if we're pushing a nearby lane, if kongor should be warded, if the pull camp		---
--- should be blocked, etc. Out of a list of over 50 ward spots the best gets chosen and then placed.												---
--- Forum thread: http://forums.heroesofnewerth.com/showthread.php?498180-WardBehavior-a-general-warding-behavior (feedback is welcome)				---
-------------------------------------------------------------------------------------------------------------------------------------------------------
---  - To enable this behavior add the following line to your bot main file: runfile "/bots/Modules/Behaviors/WardBehavior.lua"						---
---  - It would probably be better to just enable it for all your bots, you can do this by adding the same line to your behaviorlib.lua file. Do	---
---		note testers of your bot may not be able to test the warding behavior without doing this also.												---
---  - Don't forget to include wards in the buying behavior (see my GlaciusSupportBot for an example of my hard support implementation)				---
---  - If you want your bot to start moving before the creeps spawn in order to place a ward (which helps him get into the lane in time and makes 	---
---		sure the pull camp creeps don't spawn) then override the behaviorLib.PreGameUtility function to return a value of 50 or less.				---
-------------------------------------------------------------------------------------------------------------------------------------------------------

runfile "/bots/Classes/Behavior.class.lua"; --TODO: turn into require when development for this class is finished

local classes = _G.HoNBots.Classes;

runfile "/bots/Libraries/LibWarding/LibWarding.lua";

local libWarding = object.libWarding;

-- Put all ward behavior stuff in a sub table of behaviorLib instead of behaviorLib itself (prevents naming conflicts with other behaviors)
local behavior = classes.Behavior.Create('Ward');

behavior:AddToLegacyBehaviorRunner(behaviorLib); -- this also makes the reference: behaviorLib.Behaviors.WardBehavior

-- Fine tuning settings
behavior.bWardDebug = true;
behavior.bWardVerboseDebug = true;
-- The max utility gain from being nearby a ward spot. Uses a exponential decay formula based on the hero's distance from the ward spot vs it's travel range (which is based on hero movement speed).
behavior.nNearbyWardUtilityGain = 20;
-- For each enemy hero near the hero the Ward-utility value will be reduced by this amount
behavior.nNearbyEnemyHeroesUtilityLoss = 20;
-- How often ShouldWard() should be refreshed. Seeing as a few seconds delay on warding often doesn't matter at all this value could be quite high.
behavior.nShouldWardCheckIntervalMS = 2000;
-- How long ward spots should be cached for. The higher this is the bigger the chances of the bot wasting time running somewhere he is later going to regret...
behavior.nWardSpotsUpdateIntervalMS = 5000;
-- The average speed gains from items - doesn't need to be exact
behavior.tSpeedGainItems = {
	['Item_PostHaste'] = 160, -- We could move faster, but currently port boots aren't used often by bots
	['Item_EnhancedMarchers'] = 90, -- 360 from boots, about 40 from activation with 50% uptime is about 380 average speed
	['Item_PlatedGreaves'] = 70,
	['Item_Steamboots'] = 60,
	['Item_Striders'] = 130, -- 50 from boots, +100 when out of combat with 80% uptime is 130 average speed
	['Item_Marchers'] = 50,
	['Item_Intelligence6'] = 25,
	['Item_Energizer'] = 25,
};

-- Useful stuff
behavior.nWardPlacementRangeSq = HoN.GetItemDefinition('Item_FlamingEye'):GetRange(0) ^ 2;
behavior.tWardSpots = {};
behavior.nNextWardSpotsUpdate = 0;
behavior.nNextShouldWardCheck = 0;
behavior.bLastShouldWardValue = false;
behavior.nNextWardTravelTime = 0;
behavior.nCurrentWardUtil = 0;
behavior.bIsPregame = true;

do -- Static functions:

-- Create a new path if the bot is currently further away from the next node then this value (e.g. after porting)
behavior.nRepathIfFurtherAwayThenSq = 3500 * 3500;
--[[ static behavior.CalculatePathDistance(botBrain, vecDestination)
description:		Calculate the distance to the destination using normal pathing. Reality might be a bit less due to bots cutting 
					corners while the pathing does not.
					! Generates a path and does a few costly calculations. Avoid using regularly. !
parameters:			botBrain			The botBrain of the bot. Is currently unused so may be nil (see behaviorLib.PathLogic).
					vecDestination		The destination of the bot, from it's current position.
return:				The distance (in units) to the destination. Might be about 10% higher then reality.
]]
function behavior.CalculatePathDistance(botBrain, vecDestination, bForceRepath)
	--TODO: Remove this when this gets implemented into PathLogic as per request: http://forums.heroesofnewerth.com/showthread.php?497454-Patch-behaviorLib-PathLogic-make-new-path-when-next-node-is-way-out-of-range
	if bForceRepath or (behaviorLib.tPath and behaviorLib.tPath[behaviorLib.nPathNode] and Vector3.Distance2DSq(behaviorLib.tPath[behaviorLib.nPathNode]:GetPosition(), core.unitSelf:GetPosition()) > behavior.nRepathIfFurtherAwayThenSq) then
		-- If we're far away from the current path node we should repath
		behaviorLib.vecGoal = Vector3.Create();
	end
	behaviorLib.PathLogic(botBrain, vecDestination);
	
	-- Calculate distance to destination, starting at our current location traversing along the path to the final destination
	local vecLastNodePosition = core.unitSelf:GetPosition();
	local nTotalDistance = 0;
	for i = behaviorLib.nPathNode, #behaviorLib.tPath do
		local vecNodePosition = behaviorLib.tPath[i]:GetPosition();
		
		--local nDistance = Vector3.Distance2D(vecLastNodePosition, vecNodePosition);
		local nDistance = VectorDistance2D(vecLastNodePosition, vecNodePosition);
		nTotalDistance = nTotalDistance + nDistance;
		
		vecLastNodePosition = vecNodePosition;
	end
	
	return nTotalDistance;
end

--[[ static behavior.CalculateTravelTime(botbrain, vecDestination, nMoveSpeed)
description:		Calculate the travel time to the destination using normal pathing. Reality might be a bit less due to bots cutting 
					corners while the pathing does not.
					! Generates a path and does a few costly calculations. Avoid using regularly. !
parameters:			botBrain			The botBrain of the bot. Is currently unused so may be nil (see behaviorLib.PathLogic).
					vecDestination		The destination of the bot, from it's current position.
					nMoveSpeed			The average movement speed the bot can maintain while traveling to the destination.
return:				The travel time (in ms) to the destination. Might be about 10% higher then reality.
]]
function behavior.CalculateTravelTime(botbrain, vecDestination, nMoveSpeed, bForceRepath)
	local nTotalDistance = behavior.CalculatePathDistance(botBrain, vecDestination, bForceRepath);
	
	return math.ceil((nTotalDistance / nMoveSpeed) * 1000); -- in ms
end

--[[ static behavior.GetEstimatedAverageMoveSpeed(unit)
description:		Get the assumed movement speed of the hero without being affected by any movement increasing stuff such as a haste 
					rune or abilities. This is done instead of using unit:GetMoveSpeed() to prevent ward priorities from jumping all 
					over the place, causing the bot one moment to be willing to place a far away ward and the next returning to lane.
parameters:			unit				The unit to check.
return:				The estimated average movement speed of the unit.
]]
function behavior.GetEstimatedAverageMoveSpeed(unit)
	local nMoveSpeed = 290;
	
	local inventory = unit:GetInventory(true);
	for slot = 1, 6 do
		local curItem = inventory[slot];
		
		if curItem then
			local sItemName = curItem:GetName();
			
			nMoveSpeed = nMoveSpeed + (behavior.tSpeedGainItems[sItemName] or 0);
		end
	end
	
	--BotEcho('MoveSpeed: ' .. nMoveSpeed);
	
	return nMoveSpeed;
end

--[[ static behavior.GetReasonableTravelDistanceSq()
description:		Get a reasonable travel distance for the hero based on its boots potential movement speed.
return:				The max distance (in units).
]]
function behavior.GetReasonableTravelDistanceSq()
	-- Calculate the maximum distance of a ward spot, at a default movespeed of 290 this would be 4930 units, striders=7140 (movespeed * max travel time in seconds = range, e.g. 290 * 17 = 4930)
	-- For every minute that passes another 100 units will be added so that at 20 minutes into the game we get a bonus range of 2000 units
	local nMoveSpeed = behavior.GetEstimatedAverageMoveSpeed(core.unitSelf);
	local nBonusDistanceFromGameTime = (HoN.GetMatchTime() / 600);
	local nMaxDistanceSq = (nMoveSpeed * nMoveSpeed * 17 * 17) + (nBonusDistanceFromGameTime * nBonusDistanceFromGameTime);
	
	return nMaxDistanceSq;
end

end -- End of static functions.

do -- Instance functions:

local selectedWardSpot;
--[[ function behavior:SelectNextWard(wardSpots)
description:		Select the next ward spot from the available ward spots, skipping any ward spots that aren't within reasonable range. 
					If a ward was selected it will be locked, so the bot will want to place it even if he moves out of range afterwards. This 
					is to ensure the bot doesn't run back and forth in and out of range of the ward spot.
parameters:			wardSpots			A table containing the ward spots selected by LibWarding.
returns:			wardSpot:			The next ward spot
					vecWardSpot: 		The next ward spot's vector location
					nDistanceSq: 		The distance to the next ward spot (squared).
]]
function behavior:SelectNextWard(wardSpots)
	-- If we have selected a ward spot earlier we need to stick with it to prevent our hero from running back and forth within and out of range
	if selectedWardSpot then
		-- Check if the ward spot is still useful
		local nSelectWardSpotIndex = 0;
		for k, v in pairs(wardSpots) do
			if v == selectedWardSpot then
				nSelectWardSpotIndex = k;
				break;
			end
		end
		
		if nSelectWardSpotIndex ~= 0 and wardSpots[nSelectWardSpotIndex] then
			return self:GetWardSpotInfo(wardSpots[nSelectWardSpotIndex]);
		end
	end
	
	local nMaxTravelDistanceSq = self.GetReasonableTravelDistanceSq();
	
	local nWardSpotIndex = 0;
	local wardSpot, vecWardSpot, nDistanceSq;
	
	-- Go through all current ward spots to find the one we should place right now
	while nWardSpotIndex == 0 or (wardSpot and nDistanceSq > nMaxTravelDistanceSq) do
		if self.bWardVerboseDebug and nWardSpotIndex ~= 0 then BotEcho('Skipping #' .. wardSpot.Identifier .. ': at ' .. math.sqrt(nDistanceSq) .. ' units it is out of range (' .. math.sqrt(nMaxTravelDistanceSq) .. ').'); end
		
		nWardSpotIndex = nWardSpotIndex + 1;
		if wardSpots[nWardSpotIndex] then
			wardSpot, vecWardSpot, nDistanceSq = self:GetWardSpotInfo(wardSpots[nWardSpotIndex]);
		else
			wardSpot, vecWardSpot, nDistanceSq = nil, nil, nil;
		end
		
		-- A ward spot was found, now lock this in place to prevent the bot from changing his mind between the available spots
		selectedWardSpot = wardSpot;
	end
	
	return wardSpot, vecWardSpot, nDistanceSq;
end

--[[ function behavior:GetWardSpotInfo(wardSpot)
description:		Get needed ward spot information from the provided ward spot.
parameters:			wardSpot			(WardSpot) The ward spot to investigate.
returns:			wardSpot			(WardSpot) The ward spot provided.
					vecWardSpot			(Vector3) The ward spot's vector location.
					nDistanceSq			(number) The distance to the next ward spot (squared).
]]
function behavior:GetWardSpotInfo(wardSpot)
	local vecPosition = core.unitSelf:GetPosition();
	
	local vecWardSpot = wardSpot:GetPosition();
	local nDistanceSq = Vector3.Distance2DSq(vecPosition, vecWardSpot);
	
	-- Alternatively the ward may be closer to the outest lane tower (which we will be extremely likely to move to), if
	-- this is the case we use that distance instead. This helps ordering the bot to move to a ward spot right from the 
	-- base, when he isn't in his lane yet but on his way.
	if core.tMyLane then
		local unitFurthestAlliedTower = core.GetFurthestLaneTower(core.tMyLane, core.bTraverseForward, core.myTeam);
		if unitFurthestAlliedTower then
			local nDistanceFromLaneTowerSq = Vector3.Distance2DSq(unitFurthestAlliedTower:GetPosition(), vecWardSpot);
			
			if nDistanceFromLaneTowerSq < nDistanceSq then -- lower is better
				nDistanceSq = nDistanceFromLaneTowerSq;
			end
		end
	end
	
	return wardSpot, vecWardSpot, nDistanceSq;
end

--[[ function behavior:ShouldWard()
description:		Ask LibWarding if we should ward. The result is cached for as long as set in behavior.nShouldWardCheckIntervalMS.
returns:			(bool) True if we should ward, false if not. This value is cached for 2 seconds.
]]
function behavior:ShouldWard()
	local nGameTime = HoN.GetGameTime();
	if nGameTime > self.nNextShouldWardCheck then
		self.bLastShouldWardValue = libWarding:ShouldWard();
		self.nNextShouldWardCheck = nGameTime + self.nShouldWardCheckIntervalMS - 1;
	end
	
	return self.bLastShouldWardValue;
end

--[[ function behavior:GetWardSpots(nWardsAvailable, bForceUpdate)
description:		Get a list of optimal ward spots. This is cached for 5 seconds to reduce load (it is refreshed right before 
					placing a ward to ensure the wards that are placed are still proper).
parameters:			nWardsAvailable		(Number) Amount of wards available. If not provided this will be looked up.
					bForceUpdate		(Boolean) If the ward spots MUST be updated. If not the returned ward spots may be up to 5 seconds old.
returns:			(Table) The best possible ward spots according to LibWarding.
]]
function behavior:GetWardSpots(nWardsAvailable, bForceUpdate)
	-- If the amount of wards available wasn't provided we look it up
	if not nWardsAvailable then
		nWardsAvailable = 0;
		local itemWardOfSight = libWarding:GetWardOfSightItem();
		if itemWardOfSight then
			nWardsAvailable = itemWardOfSight:GetCharges();
		end
	end
	
	local nGameTimeMS = HoN.GetGameTime();

	if bForceUpdate or not self.tWardSpots or nGameTimeMS >= self.nNextWardSpotsUpdate then --TODO: We shouldn't update if we're close
		-- Get new ward spots from LibWarding
		local tAllWardSpots;
		self.tWardSpots, tAllWardSpots = libWarding:GetBestWardSpots(nWardsAvailable, self.bWardDebug);
		self.nNextWardSpotsUpdate = nGameTimeMS + self.nWardSpotsUpdateIntervalMS;
		
		if self.bWardDebug and (#self.tWardSpots > 0 or #tAllWardSpots > 0) then
			BotEcho('Current ward spots (selected):');
			for i = 1, #self.tWardSpots do
				local item = self.tWardSpots[i];
				for _, v in pairs(tAllWardSpots) do
					if item.Identifier == v.WardSpot.Identifier then
						BotEcho(' - #' .. v.WardSpot.Identifier .. ' with priority ' .. v.Priority .. ' (' .. tjoin(v.Reason, ', ') .. ')');
						core.DrawXPosition(v.WardSpot:GetPosition(), "orange", 200);
						break;
					end
				end
			end
			if self.bWardVerboseDebug then
				BotEcho('Current ward spots (all):');
				for _, v in pairs(tAllWardSpots) do
					BotEcho(' - #' .. v.WardSpot.Identifier .. ' with priority ' .. v.Priority .. ' (' .. tjoin(v.Reason, ', ') .. ')');
				end
			end
		end
	end
	
	return self.tWardSpots;
end

end -- End of instance functions.

do -- Behavior functions:

local bUpdateRandomPriorities = true;
local bStillWaitingBeforeMoving = true;
--[[ function behavior:Utility(botBrain)
description:		Asks the warding library if we should ward. If this is the case the utility value returned will be 20, except during the 
					pregame where it will be 51 to beat the pregame behavior.
parameters:			botBrain			The botBrain of the bot.
returns:			0 if the ward behavior is idle, 20-40 (depending on range from ward spot) if a ward can be placed after the pregame and 51-71 if a ward can be placed during the pregame.
]]
function behavior:Utility(botBrain)
	--[[
	1. Do we have a ward in our bags?
	2. Should a ward be placed?
	3. Is the ward within range?
	 - utility value starts here at 20 (or 51 if we're still pre-game) - 
	4. Is the ward close enough to warrant bonus utility? Gains up to 7 utility value.
	5. Are we currently in range of enemy heroes? Loses 4 utility value per nearby enemy hero.
	]]
	
	local nUtility = 0;
	local itemWardOfSight = libWarding:GetWardOfSightItem();
	
	if itemWardOfSight then -- 1. Do we have a ward in our bags?
		-- We need to wait for lanes to be assigned
		if not core.teamBotBrain.bLanesBuilt then
			if self.bWardDebug then BotEcho('Aborting WardUtility: Waiting for lane asignements.'); end
			return 0;
		end
		
		if self:ShouldWard() then -- 2. Should a ward be placed?
			local tWardSpots = self:GetWardSpots(itemWardOfSight:GetCharges());
			local wardSpot, vecWardSpot, nDistanceSq = self:SelectNextWard(tWardSpots);
			
			if wardSpot then -- 3. Is any of the ward spots within range?
				-- Default utility value: (don't use a too high utility value or the bot will suicide trying to ward)
				nUtility = 21;
				
				if self.bIsPregame then
					-- If we are pre-game we should start moving exactly at the time so that we arrive when the ward should be placed (at 0:00)
					
					self.bIsPregame = (HoN:GetMatchTime() <= 0);
					--if self.bIsPregame then
					--	behaviorLib.nPathMyLaneMul = 0.99;
					--else
					--	behaviorLib.nPathMyLaneMul = 0.5;
					--end
					
					if self.bIsPregame then
						if behavior.nNextWardTravelTime == 0 then
							-- CalculateTravelTime isn't 100% accurate due to bots cutting corners, we don't really care if we're 1 or 2 seconds late so just act like we need 10% less time
							behavior.nNextWardTravelTime = self.CalculateTravelTime(botbrain, vecWardSpot, core.unitSelf:GetMoveSpeed()) * 0.9;
						end
						
						if bStillWaitingBeforeMoving and behavior.nNextWardTravelTime >= HoN.GetRemainingPreMatchTime() then
							-- Update once more before starting to move
							behavior.nNextWardTravelTime = self.CalculateTravelTime(botbrain, vecWardSpot, core.unitSelf:GetMoveSpeed(), true) * 0.9;
						end
						
						if not bStillWaitingBeforeMoving or behavior.nNextWardTravelTime >= HoN.GetRemainingPreMatchTime() then
							-- This value should be able to beat the pre-game utility value, however if it is set too high the bot will become an easy gank target. By default the 
							-- pre-game utility value is set at 98, if we were to set our utility above that we would break shopping (meaning no wards so that would be fatal).
							-- Instead we recommend developers who want their bot to start moving to a ward spot before the game start to override the PreGameUtility function so it 
							-- uses a utility value of 50 instead. This should still be high enough to beat most other utility functions, but not too high to prevent the bot from
							-- doing useful stuff.
							nUtility = 52;
							
							if self.bWardDebug and bStillWaitingBeforeMoving then
								BotEcho('Starting to move to the ward spot to arrive there at the 0:00 mark. (travel time: ' .. behavior.nNextWardTravelTime .. ', time remaining: ' .. HoN.GetRemainingPreMatchTime() .. ')');
							end
							bStillWaitingBeforeMoving = nil;
						end
					end
				else
					-- Increase utility value if the ward is nearby
					-- Don't do this pre-game since the distance doesn't matter then as we can just start moving before creeps spawn
					--TODO: Decide on a formula
					--local nDistanceUtility = core.ParabolicDecayFn(nDistanceSq, self.nNearbyWardUtilityGain, self.GetReasonableTravelDistanceSq());
					local nDistanceUtility = core.ExpDecay(nDistanceSq, self.nNearbyWardUtilityGain, self.GetReasonableTravelDistanceSq(), 2);
					
					if nDistanceUtility > 0 then
						nUtility = nUtility + nDistanceUtility;
						
						--if self.bWardVerboseDebug then BotEcho('Distance util: ' .. nDistanceUtility .. ' - distance:' .. math.sqrt(nDistanceSq) .. ' - reasonable:' .. math.sqrt(self.GetReasonableTravelDistanceSq())); end
					end
				end
				
				-- Because the distance to a ward spot might increase due to pathing around objects (such as trees), we need to remember the highest ward utility and apply that (or 
				-- the utility value might drop below another behavior and the bot starts moving in circles switching between this and that other behavior).
				if nUtility > self.nCurrentWardUtil then
					self.nCurrentWardUtil = nUtility;
				else
					nUtility = self.nCurrentWardUtil;
				end
				
				-- Lower utility value for the amount of enemy heroes in range. When the bot encounters an enemy hero on his way to ward then the task becomes dangerous and should be suspended.
				local nEnemyHeroesNear = core.NumberElements(core.localUnits.EnemyHeroes);
				if nEnemyHeroesNear == 1 then
					nUtility = nUtility - self.nNearbyEnemyHeroesUtilityLoss;
				elseif nEnemyHeroesNear > 1 then
					nUtility = nUtility - (self.nNearbyEnemyHeroesUtilityLoss + (self.nNearbyEnemyHeroesUtilityLoss - 1) * 0.5); -- first hero counts full, follow ups half
				end
				
				-- We currently have a ward and a new ward should be placed, when done we should update the random priorities
				bUpdateRandomPriorities = true;
			end
		end
	end
	
	if bUpdateRandomPriorities and nUtility == 0 then
		libWarding:UpdateRandomPriorities()
		bUpdateRandomPriorities = false;
	end
	
	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  WardUtility: %g", nUtility))
	end
	
	return nUtility;
end

local bMovedToClosestNode = false;
function behavior:Execute(botBrain)
	local itemWardOfSight = libWarding:GetWardOfSightItem();
	if not itemWardOfSight then
		return false;
	end
	
	if self.bWardDebug then
		core.DrawXPosition(core.unitSelf:GetPosition(), 'cyan');
	end
	
	local nGameTimeMS = HoN.GetGameTime();
	local tWardSpots = self.tWardSpots;
	
	if tWardSpots and #tWardSpots > 0 then
		local wardSpot, vecWardSpot, nDistanceSq = self:SelectNextWard(tWardSpots);
		if not wardSpot then
			if self.bWardVerboseDebug then BotEcho('Next ward is out of range, returning false.'); end
			return false;
		end
		
		if nDistanceSq <= self.nWardPlacementRangeSq and not self.bIsPregame then
			-- We're within warding range, so place ward (if we're pre-game we must wait before warding to avoid wasted ward lifetime)
			
			libWarding:PlaceWard(botBrain, itemWardOfSight, vecWardSpot, self.bWardDebug);
		
			-- We placed a ward so update the list before moving on to the next spot
			self.tWardSpots = nil;
			--core.RemoveByValue(tWardSpots, wardSpot);
			self.nNextWardSpotsUpdate = 0;
			self.nCurrentWardUtil = 0;
			self.nNextShouldWardCheck = 0;
			bMovedToClosestNode = false;
		else
			-- Outside of warding range, move closer
			
			if nDistanceSq > core.nOutOfPositionRangeSq then
				-- If we're still out of the OutOfPositionRange
				if not behaviorLib.MoveExecute(botBrain, vecWardSpot) then
					core.OrderMoveToPosAndHoldClamp(botBrain, core.unitSelf, vecWardSpot, false);
					if self.bWardDebug then BotEcho('MoveExecute returned false. Falling back to OrderMoveToPosAndHoldClamp.'); end
				end
			else
				-- Within OutOfPositionRange, MoveExecute will now try to use OrderMoveToPosAndHoldClamp which is clumsy for some wards
				
				local vecClosestNode = BotMetaData.GetClosestNode(vecWardSpot):GetPosition();
				
				-- Debug stuff
				core.DrawXPosition(vecClosestNode, 'blue');
				core.DrawXPosition(vecWardSpot, 'yellow');
				
				local vecMyPosition = core.unitSelf:GetPosition();
				
				if not bMovedToClosestNode and Vector3.Distance2DSq(vecClosestNode, vecMyPosition) > 100 * 100 then--TODO: THIS DOESN'T WORK. 
					-- Move to the closest node next to the ward spot
					
					if not behaviorLib.MoveExecute(botBrain, vecClosestNode) then
						core.OrderMoveToPosAndHoldClamp(botBrain, core.unitSelf, vecClosestNode, false);
						if self.bWardDebug then BotEcho('MoveExecute returned false. Falling back to OrderMoveToPosAndHoldClamp.'); end
					end
				else
					-- We're as close as we can get but it isn't close enough, let's try something else
					
					bMovedToClosestNode = true;
					local vecPlacementLocation = libWarding:GetPlacementLocation(vecWardSpot, vecClosestNode);
					
					core.DrawXPosition(vecPlacementLocation, 'red');
					core.OrderMoveToPosAndHoldClamp(botBrain, core.unitSelf, vecPlacementLocation, false);
				end
			end
		end
		
		return true;
	end
	
	return false;
end

end -- End of behavior functions.

runfile "/bots/z_bugfixes.lua";
