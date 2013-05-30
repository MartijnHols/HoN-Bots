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
local tindexOf, tinsert, tsort, type, pi = _G.table.indexOf, _G.table.insert, _G.table.sort, _G.type, _G.math.pi;

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
--- 	GetBestWardSpot(nWards)																				---
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
lib.nMaxWards = 3; -- Max amount of wards up at a time. If more then 3 wards are up at once there will likely be a ward shortage afterwards.
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

-- Initialize the library and load all the required data
function lib.Initialize()
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
		
		SetTableValueAtIndexFromString(lib.tPointsOfInterest, sName, poi);
	end
	core.VerboseLog('Finished loading ' .. core.NumberElements(lib.tPointsOfInterest) .. ' points of interest');
	
	--Dump(lib.tPointsOfInterest);
	
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
				Echo('^rLibWarding: WardType "' .. v .. '" of ward spot #' .. sIdentifier .. ' doesn\'t exist (' .. sWardTypes .. ').');
			end
			tWardSpotTypes[WardType[v]] = true;
		end
		--core.BotEcho('Matched ' .. sWardTypes .. ' to ' .. Dump(tWardSpotTypes, true));
		
		-- Convert the point of interest keyname to the actual point of interest
		local oPointOfInterest = nil;
		if sPointOfInterestKey then
			oPointOfInterest = GetTableValueAtIndexFromString(lib.tPointsOfInterest, sPointOfInterestKey);
			
			if not oPointOfInterest then
				Echo('^rLibWarding: Point of Interest "' .. sPointOfInterestKey .. '" of ward spot #' .. sIdentifier .. ' doesn\'t exist.');
			end
			
			--core.BotEcho('Matched ' .. sPointOfInterestKey .. ' to ' .. Dump(oPointOfInterest, true));
		end
		
		tinsert(lib.tWardSpots, WardSpot.Create(sIdentifier, vecPosition, nPriority, tWardSpotTypes, oPointOfInterest));
	end
	core.VerboseLog('Finished loading ' .. core.NumberElements(lib.tWardSpots) .. ' WardSpots');
	
	if not core.teamBotBrain.TeamAggressionAnalyzationBehavior then
		runfile "/bots/Behaviors/TeamAggressionAnalyzationBehavior.lua";
	end
	if not core.teamBotBrain.TeamAggressionAnalyzationBehavior:IsEnabled() then
		core.teamBotBrain.TeamAggressionAnalyzationBehavior:Enable();
	end
end
-- Override the CoreInitialize to add our own initialize to it
local oldCoreInitialize = core.CoreInitialize;
function core.CoreInitialize(...) -- override
	local returnValue = oldCoreInitialize(...);
	
	--lib.Initialize();--TODO: Evaluate: should this be in the initialize where the lib is active for ALL heroes, or in the utility so it is only activated the moment a hero gets a ward?
	
	return returnValue;
end

local bInitialized;
--[[ function lib:GetBestWardSpot(nWards)
description:		Get the best ward spots for the amount of available wards.
parameters:			nWards				(Number) The available amount of wards. This is needed if you wish to sort the wards on distance from current hero.
return:				(Table) Returns at most nWards of ward spots sorted on distance from current hero. May also return an empty table!
]]
function lib:GetBestWardSpot(nWards)
	if type(nWards) ~= 'number' then nWards = 1; end
	
	if not bInitialized then
		lib.Initialize();
		bInitialized = true;
	end
	
	-- Reduce the amount of ward spots returned if placing more wards would mean we'd have too many wards up
	local nWardsCurrentlyUp = lib.GetNumWards();
	if nWards > (lib.nMaxWards - nWardsCurrentlyUp) then
		if (lib.nMaxWards - nWardsCurrentlyUp) > 0 then
			nWards = (lib.nMaxWards - nWardsCurrentlyUp);
		else
			nWards = 0; -- we're not returning here since the second return value might still be useful while the first is empty (see the return statement)
		end
	end
	local tMyLanePath = core.teamBotBrain:GetDesiredLane(core.unitSelf);
	local vecNextTowerLocation;
	if core.teamBotBrain.nPushState == 2 and tMyLanePath then
		local unitNextTower = core.GetClosestLaneTower(tMyLanePath, core.bTraverseForward, core.enemyTeam);
		if unitNextTower and unitNextTower.GetPosition then
			vecNextTowerLocation = unitNextTower:GetPosition();
		end
	end
	
	local taaBehavior = HoN.GetTeamBotBrain().TeamAggressionAnalyzationBehavior;
	local myTeamAggressionState = taaBehavior:GetState(core.myTeam, 30 * 1000);
	
	local tGetPriorityParameters = {
		bIsAggressive = (myTeamAggressionState == taaBehavior.AggressionStates.Aggressive), -- could also check if there are specific heroes with a big kill lead (e.g. a Fayde with 10/4 should be considered aggressive) | or calculate kills per minute
		bIsDefensive = (myTeamAggressionState == taaBehavior.AggressionStates.Defensive),
		nMatchTime = HoN.GetMatchTime(),
		vecPosition = core.unitSelf:GetPosition(),
		tLanePath = tMyLanePath,
		vecPushingTowerLocation = vecNextTowerLocation,
		bIsRuneWardUp = lib.IsAnyLocationWarded(lib.tPointsOfInterest.Runes),
		bIsKongorWardUp = lib.IsAnyLocationWarded(lib.tPointsOfInterest.Kongor),
		bHasKongorBeenKilled = false, -- is there a way to detect Kongor kills???
		bEnemyTeamHasJungler = lib.HasJungler(core.enemyTeam),
		nEnemyHeroes = core.NumberElements(HoN.GetHeroes(core.enemyTeam))
	};
	
	Dump(tGetPriorityParameters);
	
	local tempWardSpots = {}
	for i = 1, #lib.tWardSpots do
		local ws = lib.tWardSpots[i];
		
		local prio, reason = ws:GetPriority(tGetPriorityParameters);
		tinsert(tempWardSpots, {
			WardSpot = ws,
			Priority = prio,
			Reason = reason,
		});
	end
	
	-- Sort the wards on their priority putting the most important ward on top of the table
	tsort(tempWardSpots, function (a, b)
		return a.Priority > b.Priority;
	end);
	
	-- This searches the first rune and Kongor wards and then adjusts the rest of the wards priority as if this ward has already been placed, so any subsequent ward spots will have their priorities adjusted as if a runeward is already active
	-- Say we don't have a runeward up when we calculated all priorities earlier; this would increase the priority on any rune ward. If due to this priority increase the first 2 wards are runewards we may be missing out on more important wards (such as pull block wards)
	if not tGetPriorityParameters.bIsRuneWardUp or not tGetPriorityParameters.bIsKongorWardUp then
		local runeWard = nil;
		local kongorWard = nil;
		
		-- Find the first rune and kongor wards
		for i = 1, #tempWardSpots do
			local ws = tempWardSpots[i].WardSpot;
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
		for i = 1, #tempWardSpots do
			local v = tempWardSpots[i];
			tGetPriorityParameters.bIsRuneWardUp = oldbIsRuneWardUp or (runeWard.Identifier ~= v.WardSpot.Identifier);
			tGetPriorityParameters.bIsKongorWardUp = oldbIsKongorWardUp or (kongorWard.Identifier ~= v.WardSpot.Identifier);
			
			local prio, reason = v.WardSpot:GetPriority(tGetPriorityParameters);
			v.Priority = prio;
			v.Reason = reason;
		end
		
		-- Sort the wards on their priority putting the most important ward on top of the table
		tsort(tempWardSpots, function (a, b)
			return a.Priority > b.Priority;
		end);
	end
	
	-- Filter the sorted ward spots on already warded places, and limit the amount of results to the amount of wards available
	local tFinalWardSpots = {};
	local tTempPriorities = {};
	if nWards > 0 then
		local remaining = nWards;
		for i = 1, #tempWardSpots do
			local item = tempWardSpots[i];
			local vecPoI, nRadius = item.WardSpot:GetPointOfInterest();
			
			-- Check if we are already planting a ward near this ward spot
			local bAlreadyPlantingNearbyWard = false;
			for j = 1, #tFinalWardSpots do
				if Vector3.Distance2DSq(vecPoI, tFinalWardSpots[j]:GetPointOfInterest()) < (nRadius * nRadius) then -- check if there is already a ward planned to be planted within the radius of this wards point of interest
					bAlreadyPlantingNearbyWard = true;
					break;
				end
			end
			
			if not bAlreadyPlantingNearbyWard and not lib.IsLocationWarded(vecPoI) then
				tinsert(tFinalWardSpots, item.WardSpot);
				tTempPriorities[item.WardSpot.Identifier] = item.Priority;
				
				remaining = remaining - 1;
				if remaining == 0 then
					break;
				end
			end
		end
	end
	
	-- Sort the wards we should place on the distance so we place the closest ward first (minimize walking around)
	tsort(tFinalWardSpots, function (a, b)
		return Vector3.Distance2DSq(tGetPriorityParameters.vecPosition, a:GetPosition()) < Vector3.Distance2DSq(tGetPriorityParameters.vecPosition, b:GetPosition());
	end);
	
	return tFinalWardSpots, tempWardSpots;
end

--[[ function lib:ShouldWard()
description:		Check if we should ward now or if we should wait
return:				True if you should place a ward.
]]
function lib:ShouldWard()
	--TODO: return a value to represent the time remaining on the wards, that way the bot should get increasingly more utility value as the ward loses lifetime (eventually at around 5 seconds left the wardbehavior should have the max utility value)
	-- an API request to be able to see lifetimes has been submitted
	
	return lib.GetNumWards() < self.nMaxWards;
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




-- Helper functions:

--[[ function lib.GetNumWards()
description:		Get all the wards of sight currently placed by my team.
return:				(Number) The amount of wards.
]]
function lib.GetNumWards()
	-- find all wards of sight
	local tSightWards = lib.FindGadgets(Vector3.Create(), 99999, 'Gadget_FlamingEye', core.myTeam);
	
	return core.NumberElements(tSightWards);
end

--[[ function lib.HasJungler(nTeam)
description:		Check if the provided team has a jungler.
parameters:			nTeam				(Number) The team identifier (either HoN.GetLegionTeam() or HoN.GetHellbourneTeam()).
return:				(Boolean) True if a likely jungler was found.
]]
function lib.HasJungler(nTeam)
	local tHeroes = HoN.GetHeroes(nTeam);
	
	for k, unitHero in pairs(tHeroes) do
		if tindexOf(lib.tJungleHeroes, unitHero:GetTypeName()) then
			return true;
		end
	end
	
	return false;
end

--[[ static function lib.FindGadgets(vecLocation, nRange, tTypeNames, nTeam)
description:		Find all living gadgets within range of the location.
parameters:			vecLocation			(Vector3) Vector3 origin point
					nRange				(Number) The radius to look for gadgets
					tTypeNames			(Table) The TypeNames to look for, can be either a string or a table
					nTeam				(Number) What team to filter on. If no team is provided both teams will be accepted.
return:				(Table) The gadgets found.
]]
function lib.FindGadgets(vecLocation, nRange, tTypeNames, nTeam)
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
function lib.GetPlacementLocation(vecWardSpot, vecHeroPosition)
	local vec = vecWardSpot - vecHeroPosition;
	local angle = math.atan2(vec.y, vec.x) - pi;
	
	local vecRotated = core.RotateVec2DRad(lib.vecPlacementOffset, angle);
	local vecPlacementLocation = vecWardSpot + vecRotated;
	
	return vecPlacementLocation;
end

--[[ static function lib.FindWardsInRange(vecLocation, nTeam)
description:		Find all vision granting gadgets within range of provided location.
parameters:			vecLocation			(Vector3) Origin point to search from
					nTeam				(Number) What team to filter on. If no team is provided both teams will be accepted.
return:				(Table) Any ward-like gadgets in range.
]]
function lib.FindWardsInRange(vecLocation, nTeam)
	local tWards = {};
	
	--TODO: Add ward expiry / lifetime checks (20 seconds or so left = act like it's not there) - there is currently no API to support this
	
	-- Check for Ward of Sight vision (yellow wards)
	local tSightWards = lib.FindGadgets(vecLocation, 1600, 'Gadget_FlamingEye', nTeam);
	for i = 1, #tSightWards do
		tinsert(tWards, tSightWards[i]);
	end
	
	-- Rev wards have too short a lifetime and grant too little vision, don't count them as wards
	--[[-- Check for Ward of Revelation vision (blue wards)
	local tRevWards = lib.FindGadgets(vecLocation, 200, 'Gadget_Item_ManaEye', nTeam);
	for i = 1, #tRevWards do
		tinsert(tWards, tRevWards[i]);
	end]]

	-- Check for Electric Eye vision (Scout wards) - doesn't expire
	local tScoutEyes = lib.FindGadgets(vecLocation, 800, 'Gadget_Scout_Ability2', nTeam);
	for i = 1, #tScoutEyes do
		tinsert(tWards, tScoutEyes[i]);
	end

	-- Check for vision from Overgrowth (Emerald Warden), Spider Mines (Engineer) or Terror Mounds (Tremble) - all 3 share the same sight radius
	local tWardenTraps = lib.FindGadgets(vecLocation, 400, { 'Gadget_EmeraldWarden_Ability3', 'Gadget_Engineer_Ability3', 'Gadget_Tremble_Ability2' }, nTeam);
	for i = 1, #tWardenTraps do
		tinsert(tWards, tWardenTraps[i]);
	end
	
	return tWards;
end

-- How close to a PoI should another PoI be for it to be considered in range? Generally nearby PoI are all in the exact same spot so this can be really low. Increasing this value may break things.
lib.nPointIfInterestRadiusSq = 100 * 100;
--[[ static function lib.FindNearbyPointsOfInterest(vecLocation)
description:		Find all WardSpots with a point of interest near the location.
return:				(Table) All WardSpots with nearby points of interest.
]]
function lib.FindNearbyPointsOfInterest(vecLocation)
	local results = {};
	local tWardSpots = lib.tWardSpots;
	
	for i = 1, #tWardSpots do
		local ws = tWardSpots[i];
		
		if ws.PointOfInterest and ws:IsPoINearby(vecLocation, lib.nPointIfInterestRadiusSq) then
			tinsert(results, ws);
		end
	end
	
	return results;
end

--[[ function lib.IsLocationWarded(vecLocation)
description:		Check if the provided location has been warded.
					May not be completely accurate because it only checks if there is a ward in range and if the position is visible. If there is a poorly placed ward near the location and a unit giving vision over it then it might still not be warded.
parameters:			vecLocation			(Vector3) The Vector3 location to check.
return:				(Boolean) Returns true if the location most likely has been warded, false if not.
]]
function lib.IsLocationWarded(vecLocation)
	if #lib.FindWardsInRange(vecLocation, core.myTeam) > 0 and HoN.CanSeePosition(vecLocation) then
		return true;
	else
		-- Is there a Point of Interest on top of this location?
		local tWardSpots = lib.FindNearbyPointsOfInterest(vecLocation);
		
		-- Yes there is! Is any of these ward spots actually warded?
		for i = 1, #tWardSpots do
			local vecWardSpotLocation = tWardSpots[i]:GetPosition();
			
			if #lib.FindWardsInRange(vecWardSpotLocation, core.myTeam) > 0 and HoN.CanSeePosition(vecWardSpotLocation) then
				return true;
			end
		end
		
		return false;
	end
end

--[[ function lib.IsAnyLocationWarded(tLocations)
description:		Pass a table with multiple locations to check if any of them has been warded.
parameters:			tLocation			(table) The table of locations (of type Vector3) to check.
return:				(Boolean) Returns true if one or more of the locations most likely has been warded, false if none have been warded.
]]
function lib.IsAnyLocationWarded(tLocations)
	for i = 1, #tLocations do
		local item = tLocations[i];
		
		if (item.Location and lib.IsLocationWarded(item.Location)) then
			return true;
		elseif not item.Location then
			local sType = type(item);
			
			if sType == 'userdata' and lib.IsLocationWarded(item) then
				return true;
			elseif sType == 'table' and lib.IsAnyLocationWarded(item) then
				return true;
			end
		end
	end
	
	return false;
end

-- /Helper functions

