local _G = getfenv(0);
local object = _G.object;

object.libWarding = object.libWarding or {};
local core, lib = object.core, object.libWarding;

if not _G.table.indexOf then
	-- Find the index of the item within this table.
	-- table			The table to search within.
	-- item				The item to look for.
	-- RETURN			Returns the index of the item, or nil if the item couldn't be found.
	function _G.table.indexOf(table, item)
		for key, value in pairs(table) do
			if value == item then
				return key;
			end
		end
		
		return nil;
	end
end
local tindexOf, tinsert, tsort, type, pi, ceil, BotEcho = _G.table.indexOf, _G.table.insert, _G.table.sort, _G.type, _G.math.pi, _G.math.ceil, core.BotEcho;

-- Load dependencies
runfile '/bots/Libraries/LibWarding/WardSpot.class.lua';
runfile '/bots/Libraries/LibWarding/mapdatalib.lua';

-- Library specific values
local WardSpot, WardType = lib.WardSpot, lib.WardType;

---------------------------------------------------------------------------------------------------------------
--------------------------------------------- LibWarding v1.0rc1 ----------------------------------------------
--- The following settings can be changed:																	---
--- 	nMaxWards			The max amount of wards up at one time. Defaults to 3 (having more then 		---
---							3 wards up at the same time would mean there would be a ward shortage later).	---
---		tJungleHeroes		A table containing all jungle heroes.											---
--- The following methods are available:																	---
--- 	GetBestWardSpots(nWards)																				---
---			Get the best nWards amount of ward spots. Returns two values; a table with the ward spots to 	---
---			ward (sorted by distance) and a table containing all ward spots.								---
---		ShouldWard()																						---
---			Returns true if wards should be placed, false if not.											---
---		GetNumWards()																						---
---			Get the amount of wards currently placed by my team.											---
---		HasJungler(nTeam)																					---
---			Check if the team has a jungler.																---
---		FindGadgets(vecLocation, nRange, tTypeNames{sTypeName}, nTeam)										---
---			Find all living gadgets with one of the provided tTypeNames within range of the provided 		---
---			location. If no team is provided gadgets for both teams will be included.						---
---		FindWardsInRange(vecLocation, nTeam)																---
---			Find all vision granting gadgets within range of the provided location. This includes Wards of 	---
---			Sight, Electric Eyes, Overgrowth, Spider Mines and Terror Mounds. If no team is provided 		---
---			gadgets for both teams will be included.														---
---		IsLocationWarded(vecLocation)																		---
---			Check if the provided location is warded. This function is 99% accurate, but occasionally badly ---
---			placed wards may be considered valid.															---
---		IsAnyLocationWarded(tLocations{vecLocation})														---
---			Check if any one of the provided locations has been warded.										---
---------------------------------------------------------------------------------------------------------------

-- Settings
lib.nMaxWards = 4; -- Max amount of wards up at a time. If more then 3 wards are up at once there will likely be a ward shortage afterwards.
lib.tJungleHeroes = {
	'Hero_Cthulhuphant', -- Cthulhuphant
	'Hero_Legionnaire', -- Legionnaire
	'Hero_Ophelia', -- Ophelia
	'Hero_Parasite', -- Parasite
	--'Hero_Predator', -- Predator
	'Hero_Solstice', -- Solstice
	'Hero_Tempest', -- Tempest
	'Hero_Treant', -- Keeper of the Forest
	'Hero_WolfMan', -- War Beast
	'Hero_Yogi', -- Wildsoul
	'Hero_Zephyr', -- Zephyr
};
lib.tPointsOfInterest = {};
lib.tWardSpots = {};
lib.tGankHeroes = { -- heroes that can snowball with succesful ganks and need wards to be countered
	'Hero_BabaYaga', -- Wretched Hag
	'Hero_Dampeer', -- Dampeer
	'Hero_Deadwood', -- Deadwood
	'Hero_Devourer', -- Devourer
	'Hero_DoctorRepulsor', -- Doctor Repulsor
	--'Hero_Dreadknight', -- Lord Salforis
	'Hero_Fade', -- Fayde
	'Hero_Fairy', -- Nymphora
	--'Hero_Gauntlet', -- Gauntlet
	'Hero_Grinex', -- Grinex
	--'Hero_Hantumon', -- Night Hound -- can't really see NH coming, so no point considering him a ganker
	'Hero_Hunter', -- Blood Hunter
	'Hero_Kunas', -- Thunger Bringer
	'Hero_MonkeyKing', -- Monkey King
	'Hero_Mumra', -- Pharaoh
	'Hero_Nomad', -- Nomad
	'Hero_Parasite', -- Parasite
	'Hero_Rampage', -- Rampage
	'Hero_Rocky', -- Pebbles
	'Hero_Tremble', -- Tremble
	'Hero_Tundra', -- Tundra
};
-- How long a delay to invoke after a ward is placed before the next ward may be placed. This is most important early game when 2 bots are warding so they don't both place the same wards at the exact same time.
lib.nConsecutiveWardPlacementDelayMS = 1000;

--[[ function SetTableValueAtIndexFromString(table, string, value)
description:		Sets the provided value at the in the string specified table location.
					E.g. "Structures.Legion.Fountain" turns into table['Structure']['Legion']['Fountain'].
parameters:			table			(table) The table in which to set the value.
					indexString		(string) The string indicating the index for the value.
					value			(*) The value to set at the location.
]]
local function SetTableValueAtIndexFromString(table, indexString, value)
	local keys = Explode('.', indexString);
	
	local currentPosInTable = table;
	
	-- Go through all keys, stepping down in the table until we reach the last key which is the spot we've been looking for
	for i = 1, #keys do
		if not currentPosInTable[keys[i]] then
			if i == #keys then
				currentPosInTable[keys[i]] = value;
			else
				currentPosInTable[keys[i]] = {};
			end
		end
		
		currentPosInTable = currentPosInTable[keys[i]];
	end
end

local function GetTableValueAtIndexFromString(table, indexString)
	local keys = Explode('.', indexString);
	
	local currentPosInTable = table;
	
	-- Go through all keys, stepping down in the table until we reach the last key which is the spot we've been looking for
	for i = 1, #keys do
		if not currentPosInTable[keys[i]] then
			return nil;
		end
		
		currentPosInTable = currentPosInTable[keys[i]];
	end
	
	return currentPosInTable;
end

local taaBehavior;
lib.bInitialized = false;
-- Initialize the library and load all the required data
function lib:Initialize()
	core.VerboseLog('Initializing LibWarding');
	
	
	core.VerboseLog('Loading points of interest');
	local mdlPointsOfInterest = object.mapdatalib.GetMapDataLayerFromFile('/bots/Libraries/LibWarding/PointsOfInterest.botmetadata');
	local tNodes = mdlPointsOfInterest:GetNodes();
	
	for _, item in pairs(tNodes) do
		local sName = item:GetName();
		local vecPosition = item:GetPosition();
		local nRadius = item:GetProperty('radius');
		
		local poi = {
			Name = sName,
			Location = vecPosition,
			Radius = nRadius
		};
		
		SetTableValueAtIndexFromString(self.tPointsOfInterest, sName, poi);
	end
	core.VerboseLog('Finished loading ' .. core.NumberElements(self.tPointsOfInterest) .. ' points of interest');
	
	--Dump(self.tPointsOfInterest);
	
	core.VerboseLog('Loading WardSpots');
	local sFactionFilename = (core.myTeam == HoN.GetLegionTeam()) and '/bots/Libraries/LibWarding/WardSpots-Legion.botmetadata' or '/bots/Libraries/LibWarding/WardSpots-Hellbourne.botmetadata';
	local mdlWardSpots = object.mapdatalib.GetMapDataLayerFromFile(sFactionFilename);
	
	local tNodes = mdlWardSpots:GetNodes();
	
	for _, item in pairs(tNodes) do
		local sIdentifier = item:GetName();
		local vecPosition = item:GetPosition();
		local nPriority = item:GetProperty('priority');
		local sWardTypes = item:GetProperty('wardTypes');
		local sPointOfInterestKey = item:GetProperty('pointofinterest');
		
		-- Convert the ward spot type strings to WardType enum values
		local tWardSpotTypes = {};
		for _, v in pairs(Explode(',', sWardTypes)) do
			if not WardType[v] then
				BotEcho('^rLibWarding: WardType "' .. v .. '" of ward spot #' .. sIdentifier .. ' doesn\'t exist (' .. sWardTypes .. ').');
			end
			tWardSpotTypes[WardType[v]] = true;
		end
		--BotEcho('Matched ' .. sWardTypes .. ' to ' .. Dump(tWardSpotTypes, true));
		
		-- Convert the point of interest keyname to the actual point of interest
		local oPointOfInterest = nil;
		if sPointOfInterestKey then
			oPointOfInterest = GetTableValueAtIndexFromString(self.tPointsOfInterest, sPointOfInterestKey);
			
			if not oPointOfInterest then
				BotEcho('^rLibWarding: Point of Interest "' .. sPointOfInterestKey .. '" of ward spot #' .. sIdentifier .. ' doesn\'t exist.');
			end
			
			--BotEcho('Matched ' .. sPointOfInterestKey .. ' to ' .. Dump(oPointOfInterest, true));
		end
		
		tinsert(self.tWardSpots, WardSpot.Create(sIdentifier, vecPosition, nPriority, tWardSpotTypes, oPointOfInterest));
	end
	--core.VerboseLog('Finished loading ' .. core.NumberElements(self.tWardSpots) .. ' WardSpots');
	BotEcho('Finished loading ' .. core.NumberElements(self.tWardSpots) .. ' WardSpots'); --TODO: Change this back into VerboseLog when ready to submit
	
	if not core.teamBotBrain.Modules or not core.teamBotBrain.Modules.TeamAggressionAnalyzation then
		Dump(core.teamBotBrain.Modules)
		runfile "/bots/Modules/TeamAggressionAnalyzationModule.lua";
	end
	if not core.teamBotBrain.Modules.TeamAggressionAnalyzation:IsEnabled() then
		core.teamBotBrain.Modules.TeamAggressionAnalyzation:Enable();
	end
	taaBehavior = core.teamBotBrain.Modules.TeamAggressionAnalyzation;
	
	lib.bInitialized = true;
end

lib.nPriorityThreshold = 70;
--[[ function lib:GetBestWardSpots(nWards)
description:		Get the best ward spots for the amount of available wards.
parameters:			nWards				(Number) The available amount of wards. This is needed if you wish to sort the wards on distance from current hero.
return:				(Table) Returns at most nWards of ward spots sorted on distance from current hero. May also return an empty table!
]]
function lib:GetBestWardSpots(nWards, bDebug)
	if type(nWards) ~= 'number' then nWards = 1; end
	
	if lib.bInitialized == false then
		self:Initialize();
	end
	
	-- Reduce the amount of ward spots returned if placing more wards would mean we'd have too many wards up
	local nWardsCurrentlyUp = self:GetNumWards();
	if nWards > (self.nMaxWards - nWardsCurrentlyUp) then
		if (self.nMaxWards - nWardsCurrentlyUp) > 0 then
			nWards = (self.nMaxWards - nWardsCurrentlyUp);
		else
			nWards = 0; -- we're not returning here since the second return value might still be useful while the first is empty (see the return statement)
		end
	end
	
	local tAllWardSpots = self:GetAllWardSpots();
	
	-- Filter the sorted ward spots on already warded places, and limit the amount of results to the amount of wards available
	
	local tLocationsAlreadyWarded = self:GetExistingWardLocations();
	
	local tFinalWardSpots = {};
	--local tTempPriorities = {};
	if nWards > 0 then
		local remaining = nWards;
		for i = 1, #tAllWardSpots do
			local item = tAllWardSpots[i];
			local vecPoI, nRadius = item.WardSpot:GetPointOfInterest();
			
			-- Check if we are already planting a ward near this ward spot
			local bAlreadyPlantingNearbyWard = false;
			for _, v in pairs(tLocationsAlreadyWarded) do
				if Vector3.Distance2DSq(vecPoI, v) < (nRadius * nRadius) then -- check if there is already a ward planted within the radius of this wards point of interest
					bAlreadyPlantingNearbyWard = true;
					break;
				end
			end
			
			if not bAlreadyPlantingNearbyWard and not self:IsLocationWarded(vecPoI) then
				if remaining ~= 0 and item.Priority >= lib.nPriorityThreshold then
					tinsert(tFinalWardSpots, item.WardSpot);
					
					tLocationsAlreadyWarded[vecPoI] = vecPoI;
					tLocationsAlreadyWarded[item.WardSpot:GetPosition()] = item.WardSpot:GetPosition();
					--tTempPriorities[item.WardSpot.Identifier] = item.Priority;
					
					remaining = remaining - 1;
					if remaining == 0 and not bDebug then
						break;
					end
				end
			else
				tinsert(item.Reason, ('-%d for nearby ward'):format(item.Priority));
				item.Priority = 0;
			end
		end
	end
	
	local vecMyPosition = core.unitSelf:GetPosition();
	-- Sort the wards we should place on the distance so we place the closest ward first (minimize walking around)
	tsort(tFinalWardSpots, function (a, b)
		return Vector3.Distance2DSq(vecMyPosition, a:GetPosition()) < Vector3.Distance2DSq(vecMyPosition, b:GetPosition());
	end);
	
	return tFinalWardSpots, tAllWardSpots;
end

--[[ function lib:GetAllWardSpots()
description:		Get all ward spots sorted on priority.
]]
function lib:GetAllWardSpots()
	-- Collect all information needed to calculate priorities
	
	-- General conditions we want to know about
	local nMatchTimeMS = HoN.GetMatchTime();
	local vecMyPosition = core.unitSelf:GetPosition();
	local nEnemyHeroes = core.NumberElements(HoN.GetHeroes(core.enemyTeam));
	
	-- We need my lane to increase prio on wards nearby it
	local tMyLanePath = core.teamBotBrain:GetDesiredLane(core.unitSelf);
	
	-- We need the location of the tower we're pushing if we're pushing
	local vecTowerPushLocation;
	if core.teamBotBrain.nPushState == 2 and tMyLanePath then
		local unitNextTower = core.GetClosestLaneTower(tMyLanePath, core.bTraverseForward, core.enemyTeam);
		if unitNextTower and unitNextTower.GetPosition then
			vecTowerPushLocation = unitNextTower:GetPosition();
		end
	end
	
	-- We need the location of the tower that the enemy team is pushing
	local tDefenseInfos = core.teamBotBrain.tDefenseInfos;
	local vecTowerDefendLocation;
	for _, v in pairs(tDefenseInfos) do
		if core.NumberElements(v[3]) >= ceil(nEnemyHeroes * 0.6) then -- if most of the enemy team is pushing this tower
			vecTowerDefendLocation = v[1]:GetPosition();
		end
	end
	
	-- We need the aggression of my team to see what ward spots are relevant
	local myTeamAggressionState = taaBehavior:GetState(core.myTeam, 15 * 1000, true);
	if myTeamAggressionState == taaBehavior.AggressionStates.Neutral then
		-- If we're neutral at 15 seconds, check if we spent over 50% of the past 5 minutes in hostile territory, then assume we will be again
		
		local nTimeSpanMS = 5 * 60 * 1000;
		local myTeamAggressionStateHits = taaBehavior:GetStateHits(core.myTeam, nTimeSpanMS);
		-- Unknowns for our own team means we were dead, so we might as well include those in the threshold (unlike with the enemy team)
		local nTotalKnownStateHits = nTimeSpanMS / taaBehavior.nAnalyzationIntervalMS;
		local stateHitsThreshold = nTotalKnownStateHits * 0.5;
		
		-- Defensive is more important since it will keep us closer to our base while aggressive will put us very far out (which would be bad if we're in fact defensive).
		if myTeamAggressionStateHits[taaBehavior.AggressionStates.Defensive] >= stateHitsThreshold then
			myTeamAggressionState = taaBehavior.AggressionStates.Defensive;
		elseif myTeamAggressionStateHits[taaBehavior.AggressionStates.Aggressive] >= stateHitsThreshold then
			myTeamAggressionState = taaBehavior.AggressionStates.Aggressive;
		--else
			-- Still neutral
		end
	end
	
	-- We need the aggression of the enemy team to see if we can ward further away
	local enemyTeamAggressionState = taaBehavior:GetState(core.enemyTeam, 15 * 1000, true);
	if enemyTeamAggressionState == taaBehavior.AggressionStates.Neutral then
		-- If we're neutral at 15 seconds, check if we spent over 50% of the past 5 minutes in hostile territory, then assume we will be again
		
		local nTimeSpanMS = 5 * 60 * 1000;
		local enemyTeamAggressionStateHits = taaBehavior:GetStateHits(core.enemyTeam, nTimeSpanMS);
		-- Enemy team is likely to have several unknowns when they're not visible, don't include those in the total state hits
		local nTotalKnownStateHits = enemyTeamAggressionStateHits[taaBehavior.AggressionStates.Aggressive] + enemyTeamAggressionStateHits[taaBehavior.AggressionStates.Defensive] + enemyTeamAggressionStateHits[taaBehavior.AggressionStates.Neutral];
		local stateHitsThreshold = nTotalKnownStateHits * 0.5;
		
		-- Aggressive is more important since it will keep us closer to our base
		if stateHitsThreshold > 0 and enemyTeamAggressionStateHits[taaBehavior.AggressionStates.Aggressive] >= stateHitsThreshold then
			enemyTeamAggressionState = taaBehavior.AggressionStates.Aggressive;
		elseif stateHitsThreshold > 0 and enemyTeamAggressionStateHits[taaBehavior.AggressionStates.Defensive] >= stateHitsThreshold then
			enemyTeamAggressionState = taaBehavior.AggressionStates.Defensive;
		--else
			-- Still neutral
		end
	end
	
	local tGetPriorityParameters = {
		bIsAggressive = (myTeamAggressionState == taaBehavior.AggressionStates.Aggressive), -- could also check if there are specific heroes with a big kill lead (e.g. a Fayde with 10/4 should be considered aggressive) | or calculate kills per minute
		bIsDefensive = (myTeamAggressionState == taaBehavior.AggressionStates.Defensive),
		bIsEnemyTeamAggressive = (enemyTeamAggressionState == taaBehavior.AggressionStates.Aggressive),
		
		nMatchTime = nMatchTimeMS,
		vecPosition = vecMyPosition,
		tLanePath = tMyLanePath,
		nEnemyHeroes = nEnemyHeroes,
		vecPushingTowerLocation = vecTowerPushLocation,
		vecDefendingTowerLocation = vecTowerDefendLocation,
		bIsRuneWardUp = self:IsAnyLocationWarded(self.tPointsOfInterest.Runes),
		bIsKongorWardUp = self:IsAnyLocationWarded(self.tPointsOfInterest.Kongor),
		bHasKongorBeenKilled = false, -- is there a way to detect Kongor kills???
		bEnemyTeamHasJungler = self:HasJungler(core.enemyTeam),
	};
	
	-- Go through all ward spots to get their priorities
	local tAllWardSpots = {}
	for i = 1, #self.tWardSpots do
		local ws = self.tWardSpots[i];
		
		local prio, reason = ws:GetPriority(tGetPriorityParameters);
		if prio > 0 then
			tinsert(tAllWardSpots, {
				WardSpot = ws,
				Priority = prio,
				Reason = reason,
			});
		end
	end
	
	-- Sort the wards on their priority putting the most important ward on top of the table
	tsort(tAllWardSpots, function (a, b)
		return a.Priority > b.Priority;
	end);
	
	-- This searches the first rune and Kongor wards and then adjusts the rest of the wards priority as if this ward has already been placed, so any subsequent ward spots will have their priorities adjusted as if a runeward is already active
	-- Say we don't have a runeward up when we calculated all priorities earlier; this would increase the priority on any rune ward. If due to this priority increase the first 2 wards are runewards we may be missing out on more important wards (such as pull block wards)
	if not tGetPriorityParameters.bIsRuneWardUp or not tGetPriorityParameters.bIsKongorWardUp then
		-- Find the first rune and kongor wards
		local runeWard, kongorWard;
		for i = 1, #tAllWardSpots do
			local ws = tAllWardSpots[i].WardSpot;
			if runeWard == nil and ws.Type[WardType.Rune] then
				runeWard = ws;
				if kongorWard ~= nil then break; end
			elseif kongorWard == nil and ws.Type[WardType.Kongor] then
				kongorWard = ws;
				if runeWard ~= nil then break; end
			end
		end
		
		local oldbIsRuneWardUp = tGetPriorityParameters.bIsRuneWardUp;
		local oldbIsKongorWardUp = tGetPriorityParameters.bIsKongorWardUp;
		
		-- Update the priorities for everything but the actual rune/kongor wards
		for i = 1, #tAllWardSpots do
			local v = tAllWardSpots[i];
			tGetPriorityParameters.bIsRuneWardUp = oldbIsRuneWardUp or (runeWard and runeWard.Identifier ~= v.WardSpot.Identifier);
			tGetPriorityParameters.bIsKongorWardUp = oldbIsKongorWardUp or (kongorWard and kongorWard.Identifier ~= v.WardSpot.Identifier);
			
			local prio, reason = v.WardSpot:GetPriority(tGetPriorityParameters);
			v.Priority = prio;
			v.Reason = reason;
		end
		
		-- Sort the wards on their priority putting the most important ward on top of the table
		tsort(tAllWardSpots, function (a, b)
			return a.Priority > b.Priority;
		end);
	end
	
	return tAllWardSpots;
end

function lib:GetExistingWardLocations()
	local tLocationsAlreadyWarded = {};
	local tAllWardsPlaced = self:FindGadgets(Vector3.Create(), 99999, 'Gadget_FlamingEye', core.myTeam);
	for i = 1, #tAllWardsPlaced do
		local wardGadget = tAllWardsPlaced[i];
		
		local tExistingWardsWardSpots = self:GadgetToWardSpot(wardGadget);
		local nExistingWardsWardSpotsAmount = #tExistingWardsWardSpots;
		
		if nExistingWardsWardSpotsAmount > 0 then
			for j = 1, nExistingWardsWardSpotsAmount do
				tLocationsAlreadyWarded[tExistingWardsWardSpots[j]:GetPointOfInterest()] = tExistingWardsWardSpots[j]:GetPointOfInterest();
				tLocationsAlreadyWarded[tExistingWardsWardSpots[j]:GetPosition()] = tExistingWardsWardSpots[j]:GetPosition();
			end
		else
			tLocationsAlreadyWarded[wardGadget:GetPosition()] = wardGadget:GetPosition();
		end
	end
	
	return tLocationsAlreadyWarded;
end

lib.bAggressionStatePersisted = false;
--[[ function lib:ShouldWard()
description:		Check if we should ward now or if we should wait
return:				True if you should place a ward.
]]
function lib:ShouldWard()
	--TODO: return a value to represent the time remaining on the wards, that way the bot should get increasingly more utility value as the ward loses lifetime (eventually at around 5 seconds left the wardbehavior should have the max utility value)
	-- an API request to be able to see lifetimes has been submitted
	
	if lib.bInitialized == false then
		self:Initialize();
		lib.bInitialized = true;
	end
	
	if self:GetNumWards() < self.nMaxWards then
		-- Passed the amount of wards up-check, now making sure our aggression state hasn't change in a while
		
		if lib.bAggressionStatePersisted then
			-- If the state has persisted earlier we should continue
			return true;
		else
			local myTeamAggressionStateHits = taaBehavior:GetStateHits(core.myTeam, 15 * 1000);
			local nTotalKnownStateHits = myTeamAggressionStateHits[taaBehavior.AggressionStates.Aggressive] + myTeamAggressionStateHits[taaBehavior.AggressionStates.Defensive]
											 + myTeamAggressionStateHits[taaBehavior.AggressionStates.Neutral] + myTeamAggressionStateHits[taaBehavior.AggressionStates.Unknown];
			
			-- We must have maintained one useful aggression state for a full 15 seconds (5 scans at an interval of 3 sec) or we don't continue
			if myTeamAggressionStateHits[taaBehavior.AggressionStates.Neutral] == nTotalKnownStateHits or myTeamAggressionStateHits[taaBehavior.AggressionStates.Aggressive] == nTotalKnownStateHits or 
				myTeamAggressionStateHits[taaBehavior.AggressionStates.Defensive] == nTotalKnownStateHits then
				lib.bAggressionStatePersisted = true;
				return true;
			end
		end
	end
	
	return false;
end

--[[ function lib:UpdateRandomPriorities()
description:		Update the random priority values of all wards. This should only be done while not actively warding.
]]
function lib:UpdateRandomPriorities()
	local tWardSpots = self.tWardSpots;
	for i = 1, #tWardSpots do
		tWardSpots[i]:UpdateRandomPriority();
	end
end

lib.nWardToWardSpotRadiusSq = 250 * 250;
function lib:GadgetToWardSpot(gadget)
	local results = {};
	local tWardSpots = self.tWardSpots;
	
	local vecGadgetPosition = gadget:GetPosition();
	
	for i = 1, #tWardSpots do
		local ws = tWardSpots[i];
		
		if Vector3.Distance2DSq(ws:GetPosition(), vecGadgetPosition) < self.nWardToWardSpotRadiusSq then
			tinsert(results, ws);
		end
	end
	
	return results;
end


-- Helper functions:

--[[ function lib:GetNumWards()
description:		Get all the wards of sight currently placed by my team.
return:				(Number) The amount of wards.
]]
function lib:GetNumWards()
	-- find all wards of sight
	local tSightWards = self:FindGadgets(Vector3.Create(), 99999, 'Gadget_FlamingEye', core.myTeam);
	
	return core.NumberElements(tSightWards);
end

--[[ function lib:HasJungler(nTeam)
description:		Check if the provided team has a jungler.
parameters:			nTeam				(Number) The team identifier (either HoN.GetLegionTeam() or HoN.GetHellbourneTeam()).
return:				(Boolean) True if a likely jungler was found.
]]
function lib:HasJungler(nTeam)
	local tHeroes = HoN.GetHeroes(nTeam);
	
	for k, unitHero in pairs(tHeroes) do
		if tindexOf(self.tJungleHeroes, unitHero:GetTypeName()) then
			return true;
		end
	end
	
	return false;
end

--[[ static function lib:FindGadgets(vecLocation, nRange, tTypeNames, nTeam)
description:		Find all living gadgets within range of the location.
parameters:			vecLocation			(Vector3) Vector3 origin point
					nRange				(Number) The radius to look for gadgets
					tTypeNames			(Table) The TypeNames to look for, can be either a string or a table
					nTeam				(Number) What team to filter on. If no team is provided both teams will be accepted.
return:				(Table) The gadgets found.
]]
function lib:FindGadgets(vecLocation, nRange, tTypeNames, nTeam)
	if type(tTypeNames) ~= 'table' then tTypeNames = { tTypeNames }; end
	
	local tAllGadgets = HoN.GetUnitsInRadius(vecLocation, nRange, core.UNIT_MASK_ALIVE + core.UNIT_MASK_GADGET);
	
	local tGadgets = {};
	for _, item in pairs(tAllGadgets) do
		if tindexOf(tTypeNames, item:GetTypeName()) ~= nil then
			if nTeam == nil or nTeam == item:GetTeam() then
				tinsert(tGadgets, item);
			end
		end
	end
	
	return tGadgets;
end

-- The distance we can be away from a ward to still be able to place it
lib.vecPlacementOffset = Vector3.Create(500,0,0);
function lib:GetPlacementLocation(vecWardSpot, vecHeroPosition)
	local vec = vecWardSpot - vecHeroPosition;
	local angle = math.atan2(vec.y, vec.x) - pi;
	
	local vecRotated = core.RotateVec2DRad(self.vecPlacementOffset, angle);
	local vecPlacementLocation = vecWardSpot + vecRotated;
	
	return vecPlacementLocation;
end

--[[ static function lib:FindWardsInRange(vecLocation, nTeam)
description:		Find all vision granting gadgets within range of provided location.
parameters:			vecLocation			(Vector3) Origin point to search from
					nTeam				(Number) What team to filter on. If no team is provided both teams will be accepted.
return:				(Table) Any ward-like gadgets in range.
]]
function lib:FindWardsInRange(vecLocation, nTeam)
	local tWards = {};
	
	--TODO: Add ward expiry / lifetime checks (20 seconds or so left = act like it's not there) - there is currently no API to support this
	
	-- Check for Ward of Sight vision (yellow wards)
	local tSightWards = self:FindGadgets(vecLocation, 1600, 'Gadget_FlamingEye', nTeam);
	for i = 1, #tSightWards do
		tinsert(tWards, tSightWards[i]);
	end
	
	-- Rev wards have too short a lifetime and grant too little vision, don't count them as wards
	--[[-- Check for Ward of Revelation vision (blue wards)
	local tRevWards = self:FindGadgets(vecLocation, 200, 'Gadget_Item_ManaEye', nTeam);
	for i = 1, #tRevWards do
		tinsert(tWards, tRevWards[i]);
	end]]

	-- Check for Electric Eye vision (Scout wards) - doesn't expire
	local tScoutEyes = self:FindGadgets(vecLocation, 800, 'Gadget_Scout_Ability2', nTeam);
	for i = 1, #tScoutEyes do
		tinsert(tWards, tScoutEyes[i]);
	end

	-- Check for vision from Overgrowth (Emerald Warden), Spider Mines (Engineer) or Terror Mounds (Tremble) - all 3 share the same sight radius
	local tWardenTraps = self:FindGadgets(vecLocation, 400, { 'Gadget_EmeraldWarden_Ability3', 'Gadget_Engineer_Ability3', 'Gadget_Tremble_Ability2' }, nTeam);
	for i = 1, #tWardenTraps do
		tinsert(tWards, tWardenTraps[i]);
	end
	
	return tWards;
end

-- How close to a PoI should another PoI be for it to be considered in range? Generally nearby PoI are all in the exact same spot so this can be really low. Increasing this value may break things.
lib.nPointIfInterestRadiusSq = 100 * 100;
--[[ static function lib:FindNearbyPointsOfInterest(vecLocation)
description:		Find all WardSpots with a point of interest near the location.
return:				(Table) All WardSpots with nearby points of interest.
]]
function lib:FindNearbyPointsOfInterest(vecLocation)
	local results = {};
	local tWardSpots = self.tWardSpots;
	
	for i = 1, #tWardSpots do
		local ws = tWardSpots[i];
		
		if ws.PointOfInterest and ws:IsPoINearby(vecLocation, self.nPointIfInterestRadiusSq) then
			tinsert(results, ws);
		end
	end
	
	return results;
end

--[[ function lib:IsLocationWarded(vecLocation)
description:		Check if the provided location has been warded.
					May not be completely accurate because it only checks if there is a ward in range and if the position is visible. If there is a poorly placed ward near the location and a unit giving vision over it then it might still not be warded.
parameters:			vecLocation			(Vector3) The Vector3 location to check.
return:				(Boolean) Returns true if the location most likely has been warded, false if not.
]]
function lib:IsLocationWarded(vecLocation)
	if #self:FindWardsInRange(vecLocation, core.myTeam) > 0 and HoN.CanSeePosition(vecLocation) then
		return true;
	else
		-- Is there a Point of Interest on top of this location?
		local tWardSpots = self:FindNearbyPointsOfInterest(vecLocation);
		
		-- Yes there is! Is any of these ward spots actually warded?
		for i = 1, #tWardSpots do
			local vecWardSpotLocation = tWardSpots[i]:GetPosition();
			
			if #self:FindGadgets(vecWardSpotLocation, 800, 'Gadget_FlamingEye', core.myTeam) ~= 0 and HoN.CanSeePosition(vecWardSpotLocation) then
				return true;
			end
		end
		
		return false;
	end
end

--[[ function lib:IsAnyLocationWarded(tLocations)
description:		Pass a table with multiple locations to check if any of them has been warded.
parameters:			tLocation			(table) The table of locations (of type Vector3) to check.
return:				(Boolean) Returns true if one or more of the locations most likely has been warded, false if none have been warded.
]]
function lib:IsAnyLocationWarded(tLocations)
	for i = 1, #tLocations do
		local item = tLocations[i];
		
		if (item.Location and self:IsLocationWarded(item.Location)) then
			return true;
		elseif not item.Location then
			local sType = type(item);
			
			if sType == 'userdata' and self:IsLocationWarded(item) then
				return true;
			elseif sType == 'table' and self:IsAnyLocationWarded(item) then
				return true;
			end
		end
	end
	
	return false;
end

-- /Helper functions



--[[ function lib:PlaceWard(botBrain, itemWardOfSight, vecWardSpot)
description:		Attempt to place the ward at the provided location.
parameters:			botBrain			(CBotBrain) The botBrain of the bot.
					itemWard			(IEntityItem) The item to place.
					vecWardSpot			(Vector3) The location to place the ward.
					bDebug				(Boolean) Whether debug messages should be printed in the console.
returns:			(Boolean) True if succesful, false if not.
]]
function lib:PlaceWard(botBrain, itemWard, vecWardSpot, bDebug)
	local nGameTimeMS = HoN.GetGameTime();
	
	if core.teamBotBrain.nNextWardPlacementAllowed == nil or nGameTimeMS > core.teamBotBrain.nNextWardPlacementAllowed then
		 -- We must wait 1000ms if any other team member has warded recently so that we can take this new ward into account (if two bots are warding they may be trying to place the same ward at the exact same time)
		 -- This fixes a bug where wards don't instantly appear in the game world and 2 bots place the exact same wards in the start of the match (at 00:00)
		if bDebug then BotEcho('Placing ward...'); end
		core.OrderItemPosition(botBrain, core.unitSelf, itemWard, vecWardSpot);
		
		core.teamBotBrain.nNextWardPlacementAllowed = nGameTimeMS + self.nConsecutiveWardPlacementDelayMS;
		lib.bAggressionStatePersisted = false;
		
		return true;
	else
		if bDebug then BotEcho('Waiting for someone elses ward to appear before placing mine... (' .. (core.teamBotBrain.nNextWardPlacementAllowed - nGameTimeMS) .. 'ms left)'); end
		core.OrderHoldClamp(botBrain, core.unitSelf);
		
		return false;
	end
end

local function CanUseItem(item, unit)
	if unit == nil then unit = core.unitSelf; end
	
	if item and item:IsValid() and 
		unit:CanAccess(item) then
		return true;
	end
	
	return false;
end

lib.itemWardOfSight = nil;
-- If a ward of sight couldn't be found in the inventory these values determine when the next check will be
lib.nNextWardOfSightCheck = 0;
lib.nWardOfSightCheckIntervalMS = 3000;
--[[ function lib:GetWardOfSightItem()
description:		Get a reference to a ward spot item in the current bot's inventory.
returns:			(IEntityItem) The Ward of Sight, or nil if it's not in the bags.
]]
function lib:GetWardOfSightItem()
	if CanUseItem(self.itemWardOfSight) then
		return self.itemWardOfSight;
	else
		local nGameTimeMS = HoN.GetGameTime();
		if nGameTimeMS > self.nNextWardOfSightCheck then
			local tInventory = core.unitSelf:GetInventory();
			local tWardsOfSight = core.InventoryContains(tInventory, "Item_FlamingEye");
			
			if CanUseItem(tWardsOfSight[1]) then
				self.itemWardOfSight = tWardsOfSight[1];
				return tWardsOfSight[1];
			else
				self.nNextWardOfSightCheck = nGameTimeMS + self.nWardOfSightCheckIntervalMS - 1; -- allow for 1 ms space
				return nil;
			end
		else
			return nil;
		end
	end
end
