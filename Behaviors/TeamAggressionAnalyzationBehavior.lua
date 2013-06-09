local _G = getfenv(0);

local print, ipairs, pairs, string, table, next, type, tinsert, tremove, tsort, format, tostring, tonumber, strfind, strsub
	= _G.print, _G.ipairs, _G.pairs, _G.string, _G.table, _G.next, _G.type, _G.table.insert, _G.table.remove, _G.table.sort, _G.string.format, _G.tostring, _G.tonumber, _G.string.find, _G.string.sub;
local ceil, floor, pi, tan, atan, atan2, abs, cos, sin, acos, max, random, Vector3, HoN
	= _G.math.ceil, _G.math.floor, _G.math.pi, _G.math.tan, _G.math.atan, _G.math.atan2, _G.math.abs, _G.math.cos, _G.math.sin, _G.math.acos, _G.math.max, _G.math.random, _G.Vector3, _G.HoN;

if not HoN.GetTeamBotBrain() then
	error('TeamAggressionAnalyzationBehavior: Can\'t load because the TeamBotBrain hasn\'t been loaded yet!');
	return false;
end

-- object is unavailable here! We are loading in the initialize which doesn't pass a _G.object
local teambot = HoN.GetTeamBotBrain();
local core = teambot.core;

-------------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------- Team Aggression Analyzation behavior v0.1 (by Zerotorescue) ---------------------------------------------
--- This behavior does stuff. Nice stuff. Good stuff. Yeah. I could have used the time writing this to make a description. But I didn't. Deal with it. ---
-------------------------------------------------------------------------------------------------------------------------------------------------------
--- To enable this behavior add the following line to your teambot main file: runfile "/bots/Behaviors/TeamAggressionAnalyzationBehavior.lua"		---
-------------------------------------------------------------------------------------------------------------------------------------------------------

require "/bots/Behaviors/Behavior.class.lua";

local behavior = BotsNS.Behavior.Create('TeamAggressionAnalyzation');
--behavior:AddToLegacyBehaviorRunner(behaviorLib);
-- This also makes the reference: teambot.TeamAggressionAnalyzationBehavior from which the behavior needs to be enabled prior to use it
behavior:AddToLegacyTeamBotBrain(teambot);
-- Disable the behavior by default, bots that want to use it need to enable it once
behavior:Disable();

-- Fine tuning settings
behavior.bDebug = true;
-- Scan interval, more frequent is more data is more performance cost, and it doesn't really improve accuracy
behavior.nAnalyzationIntervalMS = 3 * 1000;
-- The max amount of history records.
behavior.nMaxHistoryRecords = 10 * 60 * 1000 / behavior.nAnalyzationIntervalMS; -- 10 minutes
-- Scan locations per faction, scans done from the center of each of these circles: http://i.imgur.com/olJWYNz.jpg
behavior.tScanLocations = {
	Legion = {
		{ Location = Vector3.Create(4028, 2679), RadiusSq = 4000 * 4000, MaxRadiusSq = 7000 * 7000 }, -- if the hero is further then MaxRadiusSq away from this location then he isn't in range of any of the locations
		{ Location = Vector3.Create(8022, 2010), RadiusSq = 3000 * 3000 },
		{ Location = Vector3.Create(4286, 7603), RadiusSq = 2000 * 2000 },
		{ Location = Vector3.Create(714, 5891), RadiusSq = 2500 * 2500 },
	},
	Hellbourne = {
		{ Location = Vector3.Create(13851, 12575), RadiusSq = 5500 * 5500, MaxRadiusSq = 8500 * 8500 }, -- if the hero is further then MaxRadiusSq away from this location then he isn't in range of any of the locations
		{ Location = Vector3.Create(8447, 12787), RadiusSq = 3000 * 3000 },
		{ Location = Vector3.Create(12549, 6476), RadiusSq = 1200 * 1200 },
	},
};

-- Useful stuff

-- Use as enum, e.g. behavior.AggressionStates.Aggressive - don't use the string values, they may be changed at any time without notice!
behavior.AggressionStates = {
	Unknown = 'UNKNOWN',
	Defensive = 'DEFENSIVE',
	Neutral = 'NEUTRAL',
	Aggressive = 'AGGRESSIVE',
};

-- Current state of the Legion, this is only updated if a new state persists for 2 scans
behavior.LegionState = behavior.AggressionStates.Unknown;
-- Current state of the Hellbourne, this is only updated if a new state persists for 2 scans
behavior.HellbourneState = behavior.AggressionStates.Unknown;

-- The values below are based on a split second image, the states should only be considerd changed if they are persistent for atleast 2 scans
behavior.__LegionStateActual = behavior.AggressionStates.Unknown;
behavior.__HellbourneStateActual = behavior.AggressionStates.Unknown;
-- Table containing the aggression state history of the factions, up to nMaxHistoryRecords records (default 10 minutes of data)
behavior.__tStateHistory = {
	Legion = {},
	Hellbourne = {},
};

behavior.nNextAnalyzationRun = 0;

local function BehaviorEcho(text, delay)
	Echo(('%s: TeamAggressionAnalyzation: %s'):format((core.myTeam == HoN.GetLegionTeam() and 'Legion' or 'Hellbourne'), text));
end

--[[ function behavior:TerritoryScan(tVisibleHeroes, tScanAreas)
description:		Scans the provided locations for heroes.
parameters:			tVisibleHeroes		(Table) A table containing the visible heroes seperated by faction.
					tScanAreas			(Table) A table containing the areas to scan.
returns:			(Table) The heroes found within the areas, filtered by team.
]]
function behavior:TerritoryScan(tVisibleHeroes, tScanAreas)
	local tMatches = {};
	
	for faction, tHeroes in pairs(tVisibleHeroes) do
		tMatches[faction] = tMatches[faction] or {};
		
		for _, unitHero in pairs(tHeroes) do
			local vecUnitPosition = unitHero:GetPosition();
			
			for i = 1, #tScanAreas do
				local area = tScanAreas[i];
				local nDistanceSq = Vector3.Distance2DSq(vecUnitPosition, area.Location);
				
				if area.MaxRadiusSq and nDistanceSq > area.MaxRadiusSq then
					-- If the hero is out of MaxRadiusSq then he's out of range of all our scan locations
					break;
				elseif nDistanceSq < area.RadiusSq then
					-- In range! Store for later.
					tinsert(tMatches[faction], unitHero);
					break;
				end
			end
		end
	end
	
	return tMatches;
end

--[[ function behavior:GetVisibleHeroes()
description:		Get all visible heroes.
returns:			A table with the visible heroes seperated per team and heroes merged with illusions.
]]
function behavior:GetVisibleHeroes()
	local tMatches = {};
	
	local tHeroes = HoN.GetUnitsInRadius(Vector3.Create(), 99999, core.UNIT_MASK_ALIVE + core.UNIT_MASK_HERO);
	for _, unitHero in pairs(tHeroes) do
		local nUnitTeam = unitHero:GetTeam();
		
		tMatches[nUnitTeam] = tMatches[nUnitTeam] or {};
		tMatches[nUnitTeam][unitHero:GetOwnerPlayer()] = unitHero;
	end
	
	return tMatches;
end

-- The percentage of heroes that should be in hostile territory for that team to be flagged aggressive
behavior.nHostileTerritoryHeroPercentageRequirementForAggressiveState = 3 / 5;
-- The percentage of heroes that should be in friendly territory for that team to be flagged defensive
behavior.nFriendlyTerritoryHeroPercentageRequirementForDefensiveState = 4 / 5;
-- The minimum amount of heroes that must be active to assume an aggression state
behavior.nHeroPercentageThreshold = 2 / 5;
--[[ function behavior:Analyze()
description:		Analyze the current hero locations to determine faction agression states. This is done for both teams.
					The result from just one analyze may not be very useful, you can use the time based functions instead.
returns:			LegionState				(AggressionState) The current state of the Legion (that was persistent for at least 3 seconds).
					HellbourneState			(AggressionState) The current state of the Hellbourne (that was persistent for at least 3 seconds).
					LegionStateActual		(AggressionState) The actual state of the Legion encountered during this scan. This state has not been verified yet.
					HellbourneStateActual	(AggressionState) The actual state of the Hellbourne encountered during this scan. This state has not been verified yet.
]]
function behavior:Analyze()
	local nLegion = HoN.GetLegionTeam();
	local nHellbourne = HoN.GetHellbourneTeam();
	
	local tVisibleHeroes = self:GetVisibleHeroes();
	
	local tLegionResults = self:TerritoryScan(tVisibleHeroes, self.tScanLocations.Legion);
	local tHellbourneResults = self:TerritoryScan(tVisibleHeroes, self.tScanLocations.Hellbourne);
	
	-- Legion
	local nTotalLegionHeroes = core.NumberElements(HoN.GetHeroes(nLegion));
	local nActiveLegionHeroes = core.NumberElements(tVisibleHeroes[nLegion]);
	
	local legionState = self.AggressionStates.Unknown;
	if nActiveLegionHeroes >= max(Round(behavior.nHeroPercentageThreshold * nTotalLegionHeroes), 1) then
		local nLegionHeroesInHellbourneTerritory = core.NumberElements(tHellbourneResults[nLegion]);
		local nLegionHeroesNeededForAggressive = max(Round(self.nHostileTerritoryHeroPercentageRequirementForAggressiveState * nActiveLegionHeroes), 1); -- always at least 1
		if nLegionHeroesInHellbourneTerritory >= nLegionHeroesNeededForAggressive then
			-- Many Legion heroes are currently in hostile territory, so Legion is acting aggresively right now
			legionState = self.AggressionStates.Aggressive;
		else
			-- We aren't aggressive, are we defensive?
			local nLegionHeroesInLegionTerritory = core.NumberElements(tLegionResults[nLegion]);
			local nLegionHeroesNeededForDefensive = max(Round(self.nFriendlyTerritoryHeroPercentageRequirementForDefensiveState * nActiveLegionHeroes), 1); -- always at least 1
			if nLegionHeroesInLegionTerritory >= nLegionHeroesNeededForDefensive then
				legionState = self.AggressionStates.Defensive;
			else
				-- Nope, not defensive either, so we're neutral
				
				legionState = self.AggressionStates.Neutral;
			end
		end
	end
	
	if self.bDebug then
		if legionState == self.__LegionStateActual and self.LegionState ~= legionState then
			BehaviorEcho('^gChanging Legion state from ^w' .. self.LegionState .. '^333 to ^y' .. legionState .. '^g since this new state has persisted for 2 scans.');
		elseif legionState ~= self.LegionState then
			BehaviorEcho('^333Not changing ^gLegion^333 state from ^w' .. self.LegionState .. '^333 to ^w' .. legionState .. '^333 because the state is new and may just be a hero passing through.');
		elseif legionState ~= self.__LegionStateActual and self.LegionState == LegionState then
			BehaviorEcho('^333We were right not to change ^gLegion^333 state from ^w' .. self.LegionState .. '^333 to ^w' .. self.__LegionStateActual .. '^333 since it has gone back to ^w' .. self.LegionState .. '^333.');
		end
	end
	
	-- If the state has stayed the same for 2 scans then we can assume that it is accurate, so update
	if legionState == self.__LegionStateActual then
		self.LegionState = legionState;
	end
	self.__LegionStateActual = legionState;
	
	
	
	-- Hellbourne
	local nTotalHellbourneHeroes = core.NumberElements(HoN.GetHeroes(nHellbourne));
	local nActiveHellbourneHeroes = core.NumberElements(tVisibleHeroes[nHellbourne]);
	
	local hellbourneState = self.AggressionStates.Unknown;
	if nActiveHellbourneHeroes >= max(Round(behavior.nHeroPercentageThreshold * nTotalHellbourneHeroes), 1) then
		local nHellbourneHeroesInLegionTerritory = core.NumberElements(tLegionResults[nHellbourne]);
		local nHellbourneHeroesNeededForAggressive = max(Round(self.nHostileTerritoryHeroPercentageRequirementForAggressiveState * nActiveHellbourneHeroes), 1); -- always at least 1
		if nHellbourneHeroesInLegionTerritory >= nHellbourneHeroesNeededForAggressive then
			-- Many Hellbourne heroes are currently in hostile territory, so Hellbourne is acting aggresively right now
			hellbourneState = self.AggressionStates.Aggressive;
		else
			-- We aren't aggressive, are we defensive?
			local nHellbourneHeroesInHellbourneTerritory = core.NumberElements(tHellbourneResults[nHellbourne]);
			local nHellbourneHeroesNeededForDefensive = max(Round(self.nFriendlyTerritoryHeroPercentageRequirementForDefensiveState * nActiveHellbourneHeroes), 1); -- always at least 1
			if nHellbourneHeroesInHellbourneTerritory >= nHellbourneHeroesNeededForDefensive then
				hellbourneState = self.AggressionStates.Defensive;
			else
				-- Nope, not defensive either, so we're neutral
				
				hellbourneState = self.AggressionStates.Neutral;
			end
		end
	end
	
	if self.bDebug then
		if hellbourneState == self.__HellbourneStateActual and self.HellbourneState ~= hellbourneState then
			BehaviorEcho('^gChanging ^rHellbourne^g state from ^w' .. self.HellbourneState .. '^g to ^y' .. hellbourneState .. '^g since this new state has persisted for 2 scans.');
		elseif hellbourneState ~= self.HellbourneState then
			BehaviorEcho('^333Not changing ^rHellbourne^333 state from ^w' .. self.HellbourneState .. '^333 to ^w' .. hellbourneState .. '^333 because the state is new and may just be a hero passing through.');
		elseif hellbourneState ~= self.__HellbourneStateActual and self.HellbourneState == hellbourneState then
			BehaviorEcho('^333We were right not to change ^rHellbourne^333 state from ^w' .. self.HellbourneState .. '^333 to ^w' .. self.__HellbourneStateActual .. '^333 since it has gone back to ^w' .. self.HellbourneState .. '^333.');
		end
	end
	
	-- If the state has stayed the same for 2 scans then we can assume that it is accurate, so update
	if hellbourneState == self.__HellbourneStateActual then
		self.HellbourneState = hellbourneState;
	end
	self.__HellbourneStateActual = hellbourneState;
	
	return self.LegionState, self.HellbourneState, self.__LegionStateActual, self.__HellbourneStateActual;
end

--[[ function behavior:Store(LegionState, HellbourneState)
description:		Remember the legion state for late usage.
parameters:			legionState			(AggressionState) The current aggression state of the Legion.
					hellbourneState		(AggressionState) The current aggression state of the Hellbourne.
]]
function behavior:Store(legionState, hellbourneState)
	-- Store Legion value
	tinsert(self.__tStateHistory.Legion, 1, legionState);
	-- Remove last / oldest Legion value if the history has reached the cap
	if #self.__tStateHistory.Legion > self.nMaxHistoryRecords then
		table.remove(self.__tStateHistory.Legion);
	end
	
	-- Store Hellbourne value
	tinsert(self.__tStateHistory.Hellbourne, 1, hellbourneState);
	-- Remove last / oldest Hellbourne value if the history has reached the cap
	if #self.__tStateHistory.Hellbourne > self.nMaxHistoryRecords then
		table.remove(self.__tStateHistory.Hellbourne);
	end
end

--[[ function behavior:GetStateHits(nTeam, nTimeSpanMS)
description:		Get a table with all the state hits for this team within the provided time span.
parameters:			nTeam				(number) The team id.
					nTimeSpanMS			(number) The time span to filter on - in ms.
return:				(table) A table containing all the states with the number of hits in the selected time frame.
]]
function behavior:GetStateHits(nTeam, nTimeSpanMS)
	local tStateHistory = (nTeam == HoN.GetLegionTeam() and self.__tStateHistory.Legion) or self.__tStateHistory.Hellbourne;
	
	local tStateHits = {
		[self.AggressionStates.Unknown] = 0,
		[self.AggressionStates.Defensive] = 0,
		[self.AggressionStates.Neutral] = 0,
		[self.AggressionStates.Aggressive] = 0,
	};
	
	local loopLength = #tStateHistory;
	local timeSpanRecordsEquiv = floor(nTimeSpanMS / self.nAnalyzationIntervalMS);
	if loopLength > timeSpanRecordsEquiv then
		loopLength = timeSpanRecordsEquiv;
	end
	
	for i = 1, loopLength do
		local state = tStateHistory[i];
		tStateHits[state] = tStateHits[state] + 1;
	end
	
	return tStateHits;
end

--[[ function behavior:GetState(nTeam, nTimeSpanMS, bIgnoreUnknown)
description:		Get the most common state for this team within the provided time span.
parameters:			nTeam				(number) The team id.
					nTimeSpanMS			(number) The time span to filter on - in ms.
					bIgnoreUnknown		(Boolean) True to ignore the unknown state. The unknown state may be highest when 
										heroes are often dead or not visible. This param is only effective if the provided 
										nTimeSpanMS is higher then nAnalyzationIntervalMS.
return:				(table) The most common state during the provided time span.
]]
function behavior:GetState(nTeam, nTimeSpanMS, bIgnoreUnknown)
	if nTimeSpanMS < self.nAnalyzationIntervalMS then
		return (HoN.GetLegionTeam() == nTeam and self.LegionState) or self.HellbourneState;
	end
	
	local tStateHits = self:GetStateHits(nTeam, nTimeSpanMS);
	
	local highestState = self.AggressionStates.Unknown;
	if bIgnoreUnknown then
		-- Ignore unknown aggression state by making it the absolute lowest
		tStateHits[self.AggressionStates.Unknown] = -1;
	end
	
	if tStateHits[self.AggressionStates.Neutral] > tStateHits[highestState] then
		highestState = self.AggressionStates.Neutral;
	end
	if tStateHits[self.AggressionStates.Defensive] > tStateHits[highestState] then
		highestState = self.AggressionStates.Defensive;
	end
	if tStateHits[self.AggressionStates.Aggressive] > tStateHits[highestState] then
		highestState = self.AggressionStates.Aggressive;
	end
	
	return highestState;
end

function behavior:Utility()
	local nGameTimeMS = HoN.GetGameTime();
	
	if nGameTimeMS > self.nNextAnalyzationRun and HoN:GetMatchTime() > 30000 then
		-- Wait with this first analyzation until the first creep wave has reached the T2 tower
		self.nNextAnalyzationRun = nGameTimeMS + self.nAnalyzationIntervalMS;
		
		return 100;
	end
	
	return 0;
end
local nNextDebugMessage = 0;
function behavior:Execute()
	local legionState, hellbourneState = self:Analyze();
	self:Store(legionState, hellbourneState);
	
	if self.bDebug and HoN.GetGameTime() > nNextDebugMessage then
		BehaviorEcho('My teams state: now:' .. self:GetState(core.myTeam, 0, true) .. ' 10s:' .. self:GetState(core.myTeam, 10 * 1000, true) .. ' 30s:' .. self:GetState(core.myTeam, 30 * 1000, true) .. ' 1min:' .. self:GetState(core.myTeam, 1 * 60 * 1000, true)
					 .. ' 2min:' .. self:GetState(core.myTeam, 2 * 60 * 1000, true) .. ' 5min:' .. self:GetState(core.myTeam, 5 * 60 * 1000, true) .. ' 10min:' .. self:GetState(core.myTeam, 10 * 60 * 1000, true) .. ' ');
		BehaviorEcho('Enemy teams state: now:' .. self:GetState(core.enemyTeam, 0, true) .. ' 10s:' .. self:GetState(core.enemyTeam, 10 * 1000, true) .. ' 30s:' .. self:GetState(core.enemyTeam, 30 * 1000, true) .. ' 1min:' .. self:GetState(core.enemyTeam, 1 * 60 * 1000, true)
					 .. ' 2min:' .. self:GetState(core.enemyTeam, 2 * 60 * 1000, true) .. ' 5min:' .. self:GetState(core.enemyTeam, 5 * 60 * 1000, true) .. ' 10min:' .. self:GetState(core.enemyTeam, 10 * 60 * 1000, true) .. ' ', 250);
		
		nNextDebugMessage = HoN.GetGameTime() + 60 * 1000;
	end
	
	return false;
end
