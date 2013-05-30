local _G = getfenv(0);
local object = _G.object;

object.libWarding = object.libWarding or {};
local lib = object.libWarding;
local tinsert, Vector3, random = _G.table.insert, _G.Vector3, _G.math.random;

local bDebug = true;

if bDebug then
	_G.tWardSpotBonusPriorities = _G.tWardSpotBonusPriorities or {};
	function SetWardSpotBonusPriority(sIdentifier, nPrio)
		_G.tWardSpotBonusPriorities[sIdentifier] = nPrio;
	end
end

-- enum WardType
-- The string values are identifiers and should all be unique. If using WardType you should ALWAYS compare to WardType.KeyName and NEVER to the value of said KeyName. The value is only meaningful to make debugging easier and may change at any time.
local WardType = {
	-- Situational types
	Aggressive = 'Aggressive', -- these wards should only be placed when playing aggresively
	Defensive = 'Defensive', -- these wards should only be placed while playing defensively
	Neutral = 'Neutral', -- these wards can be placed at any time
	
	-- Points of interest
	Rune = 'Rune', -- any ward that grants vision over rune spawns
	Kongor = 'Kongor', -- any ward giving plenty of vision to see most Kongor attempts
	
	-- Neutrals blocking
	CampBlock = 'CampBlock', -- any ward that blocks a neutral camp
	PullBlock = 'PullBlock', -- any ward that blocks a neutral camp that could otherwise be pulled into lane | any wards with this param will gain 50 priority during the first 5 minutes
	AncientsBlock = 'AncientsBlock', -- any ward that blocks the spawning of ancients | any wards with this param will gain priority after 15 minutes
	
	-- Ganking
	Ganking = 'Ganking', -- a ward to set up ganks (aggressive wards are generally considered gank wards), this is for - for example - a rune ward that also displays ancients
	GankPrevention = 'GankPrevention', -- a ward to prevent incoming ganks, for example, from people porting into towers
	JungleGankPrevention = 'JungleGankPrevention', -- a ward that allows you to see hostile junglers coming to gank
	JungleGanking = 'JungleGanking', -- a ward that allows you to follow junglers around and choose an optimal time to gank them
	
	-- Pushing wards (if pushing a lane these wards will give you appropriate vision)
	Pushing = 'Pushing', -- Connected point of interest will point to tower this is useful for
	AntiPushing = 'AntiPushing', -- See above. This ward type is for wards to stop enemies while they're pushing.
};
lib.WardType = WardType; -- expose the type to the library

-- Making our WardSpot class
-- WardSpot should have ZERO knowledge of any bot mechanics. It should be a class that can operate on it's own if enough parameters are provided.
local WardSpot = WardSpot or {};
lib.WardSpot = WardSpot; -- expose the class to the library
WardSpot.__index = WardSpot;

WardSpot.nWardSpotRadius = 1630;
WardSpot.Identifier = '';
WardSpot.Location = Vector3.Create();
WardSpot.DefaultPriority = 0;
WardSpot.Type = {};
WardSpot.PointOfInterest = nil;
WardSpot.RandomPriority = 0;

--[[ function WardSpot.Create(sIdentifier, vecLocation, nDefaultPriority, tWardTypes, oPointOfInterest)
description:		Constructor. Creates a new instance of the WardSpot class.
parameters:			sIdentifier			(string) The identifier of the WardSpot. Used to find WardSpots while debugging.
					vecLocation			(Vector3) The location of the ward.
					sDefaultPriority	(Number) The priority of the ward prior to applying priority values.
					tWardTypes			(Table) Table containing the ward types of this ward.
					oPointOfInterest	(Object) An object of the Point of Interest of this ward, or nil if it doesn't have one.
return:				(WardSpot) A new instance of the WardSpot class.
]]
function WardSpot.Create(sIdentifier, vecLocation, nDefaultPriority, tWardTypes, oPointOfInterest)
	local ws = {};
	setmetatable(ws, WardSpot);
	
	ws.Identifier = sIdentifier; -- A simple numeric identifier used to recognize wards easier (useful for debugging)
	ws.Location = vecLocation;
	ws.DefaultPriority = nDefaultPriority or 0; -- usually ranges from 0 to 100, but can be any numeric value - if GetPriority() returns 0 or below the ward spot will be ignored
	ws.Type = tWardTypes;
	ws.PointOfInterest = oPointOfInterest;
	ws:UpdateRandomPriority();
	
	--ws.AmountCountered = 0; -- remember how often this ward has been countered, if it happens more then once we can safely say this ward spot is completely useless for the remainder of the match
	--ws.LastCounteredTime = nil; -- remember the last time this ward was countered, at least don't ward until the counter ward is gone
	
	return ws;
end
function WardSpot:GetPosition()
	return self.Location;
end
function WardSpot:GetPointOfInterest()
	if self.PointOfInterest then
		return (self.PointOfInterest.Location or self.Location), (self.PointOfInterest.Radius or WardSpot.nWardSpotRadius);
	else -- if no point of interest was defined fall back to the ward spot
		return self.Location, WardSpot.nWardSpotRadius;
	end
end
function WardSpot:IsPoINearby(vecLocation, vecRadiusSq)
	if self.PointOfInterest and Vector3.Distance2DSq(vecLocation, self.PointOfInterest.Location) < vecRadiusSq then
		return true;
	end
	
	return false;
end
function WardSpot:IsWithinRadius(vecLocation)
	local nDistanceSq = Vector3.Distance2DSq(self:GetPosition(), vecLocation);
	
	return nDistanceSq < (self.nWardSpotRadius * self.nWardSpotRadius);
end
-- Mark this ward spot as countered.
function WardSpot:MarkCountered()
	self.tCounterHistory = self.tCounterHistory or {};
	
	tinsert(self.tCounterHistory, HoN.GetGameTime());
end
-- Check if this ward spot has been countered.
-- maxTimeAgo			How far back to check. Defaults to 10 minutes.
function WardSpot:HasBeenCountered(maxTimeAgo)
	maxTimeAgo = maxTimeAgo or 600000; -- default to 10 minutes
	
	if not self.tCounterHistory then
		return false;
	end
	
	local when = HoN.GetGameTime() - maxTimeAgo;
	for _, v in pairs(self.tCounterHistory) do
		if when > v then
			return true;
		end
	end
	
	return false;
end
-- Get the percentage of overlap this WardSpot has with the provided WardSpot.
function WardSpot:GetOverlapPercent(ws)
	local nDistanceSq = Vector3.Distance2DSq(self:GetPosition(), ws:GetPosition());
	local nWardSpotRadiusSq = (self.nWardSpotRadius * self.nWardSpotRadius / 2) + (ws.nWardSpotRadius * ws.nWardSpotRadius / 2);
	
	if nDistanceSq > nWardSpotRadiusSq then -- not in range
		return 0;
	else
		return ((nWardSpotRadiusSq - nDistanceSq) / nWardSpotRadiusSq);
	end
end

function WardSpot:UpdateRandomPriority()
	self.RandomPriority = random(6) - 1; -- 0-5
end

-- Get a modified priority for this WardSpot based on current game environment.
-- options				An object containing at least the following properties:
--						 - bIsRuneWardUp		True if either rune has been warded.
--						 - bIsKongorWardUp		True if either Kongor or his lair's entrance is warded.
--						 - nMatchTime			The match time (HoN.GetMatchTime()).
--						 - vecPosition			The current position of the bot.
--						 - tLanePath			The path of the bot's current lane.
--						 - vecPushingTowerLocation	The vector location of the tower currently being pushed.
--						 - bHasKongorBeenKilled	True if Kongor has been killed at least once this match.
--						 - bEnemyTeamHasJungler	True if the enemy team has a jungler.
--						 - nEnemyHeroes			The amount of enemy heroes.
function WardSpot:GetPriority(options)
	local prio = self.DefaultPriority;
	local reason = {};
	
	-- Team aggression
	if options.bIsAggressive and self.Type[WardType.Aggressive] then
		prio = prio + 20;
		tinsert(reason, '+20 for aggressive ward');
	elseif options.bIsDefensive and self.Type[WardType.Defensive] then
		prio = prio + 20;
		tinsert(reason, '+20 for defensive ward');
	elseif not options.bIsAggressive and not options.bIsDefensive and self.Type[WardType.Neutral] then
		prio = prio + 20;
		tinsert(reason, '+20 for neutral ward');
	end
	
	
	-- If no rune ward is up we increase the priority on all rune wards
	if not options.bIsRuneWardUp and self.Type[WardType.Rune] then
		prio = prio + 25;
		tinsert(reason, '+25 for rune ward');
	end
	
	-- If no Kongor ward is up we increase the priority on Kongor wards (becoming increasingly more important as the game continues)
	if not options.bIsKongorWardUp and self.Type[WardType.Kongor] then
		if options.bHasKongorBeenKilled or options.nMatchTime > 2400000 then -- after 40 minutes a kongor ward becomes important (or if he has been killed before then a repeat can happen any time)
			prio = prio + 30;
			tinsert(reason, '+30 for kongor ward (40min/death)');
		elseif options.nMatchTime > 1800000 then -- after 30 minutes we should have a kongor ward up
			prio = prio + 20;
			tinsert(reason, '+20 for kongor ward (30min)');
		elseif options.nMatchTime > 1200000 then -- after 20 minutes we may have a kongor ward up
			prio = prio + 10;
			tinsert(reason, '+10 for kongor ward (20min)');
		end
	end
	
	if options.bEnemyTeamHasJungler then
		-- Only place camp blocking wards if it would be useful. Placing camp blocking wards while the enemy team doesn't have a jungler will just make it easier for the wards to be countered.
		-- Don't prefer this wardspot if it has been countered in the past 30 minutes
		if self.Type[WardType.CampBlock] and not self:HasBeenCountered(1800000) then
			prio = prio + 10;
			tinsert(reason, '+10 for camp block ward');
		end
		
		-- Only place jungle gank prevention wards in the first 15 minutes (during the laning phase)
		if options.nMatchTime < 900000 and self.Type[WardType.JungleGankPrevention] then
			prio = prio + 5;
			tinsert(reason, '+5 for jungle gank prevention');
		end
	end
	
	-- Only pull block during the first 5 minutes of the match and when we're fighting against more then 1 hero
	if options.nMatchTime < 300000 and options.nEnemyHeroes > 1 and self.Type[WardType.PullBlock] then
		prio = prio + 50;
		tinsert(reason, '+50 for pull block ward');
	end
	
	--TODO: AncientsBlock - ancients blocking wards should happen when the enemy team is actively stacking and killing ancients. We'll wait for the jungle lib to be implemented.
	
	--TODO: GankPrevention - detect gank heroes (DW, Fayde, Nymph, Pebbles, ...) and if they're actually getting kills
	
	--TODO: Ganking - detect gank heroes (DW, Fayde, Nymph, Pebbles, ...) and if they're actually getting kills (or are able to)
	
	-- If we are pushing and this is a pushing ward we should give additional priority for this ward
	if options.vecPushingTowerLocation and self.Type[WardType.Pushing] then
		local nDistanceSq = Vector3.Distance2DSq(options.vecPushingTowerLocation, self:GetPointOfInterest());
		
		if nDistanceSq < 250000 then
			prio = prio + 20;
			tinsert(reason, '+20 push ward');
		end
	end
	
	-- If the ward is within travel distance of the current lane
	-- Ward priorities based on distance from hero do not work properly, the bot keeps changing wards and by moving he may get a different ward on top of the priority list which will cause him to be moving between two points without being able to make up his mind
	-- The best we can do for now is to ignore the current hero location and try to predict where our hero would most likely go and consider wards near that instead (i.e. lane path)
	if options.tLanePath then
		local vecWardPosition = self:GetPosition();
		
		local nHighestDistancePrioGain = 0;
		
		for _, v in pairs(options.tLanePath) do
			if v and v.GetPosition then
				local nDistanceSq = Vector3.Distance2DSq(v:GetPosition(), vecWardPosition);
				if nDistanceSq < 49000000 then -- 7000 * 7000 = 49000000
					-- Only worth prio points if the ward is within 7000 units
					if nDistanceSq < 6250000 then -- 2500 * 2500 = 6250000
						-- The first 2500 units we get a full prio bonus
						nHighestDistancePrioGain = 15;
						break;
					else
						-- 2500 - 7000 units we use a parabolic decay formula to calculate the additional prio earned
						--local nDistancePrio = -1 * 15 * ((nDistanceSq - 6250000) / 42750000)^2 + 15; -- parabolic decay
						local nDistancePrio = -1*( (15^2/42750000) * (nDistanceSq - 6250000) ) ^ (1/2) + 15; -- exponential decay
						
						if nDistancePrio > nHighestDistancePrioGain then
							nHighestDistancePrioGain = nDistancePrio;
						end
					end
				end
			end
		end
		
		if nHighestDistancePrioGain > 0 then
			prio = prio + nHighestDistancePrioGain;
			tinsert(reason, '+' .. nHighestDistancePrioGain .. ' for distance from lane');
		end
	end
	
	-- Spice it up a tiny bit, same wards every single game would get boring
	-- RandomPriority is updated when not actively warding. This is so the bot doesn't continuously change his mind when warding.
	if self.RandomPriority > 0 then
		prio = prio + self.RandomPriority;
		tinsert(reason, '+' .. self.RandomPriority .. 'RNG');
	end
	
	if bDebug and _G.tWardSpotBonusPriorities[self.Identifier] then
		prio = prio + _G.tWardSpotBonusPriorities[self.Identifier];
		tinsert(reason, '^r+' .. _G.tWardSpotBonusPriorities[self.Identifier] .. ' debug prio');
	end
	
	return prio, reason;
end
function WardSpot:__tostring()
	local sWardTypes = '';
	for sWardSpotType, _ in pairs(self.Type) do
		if sWardTypes == '' then
			sWardTypes = sWardSpotType;
		else
			sWardTypes = sWardTypes .. ',' .. sWardSpotType;
		end
	end
	
	return '<WardSpot#' .. self.Identifier .. ' ' .. tostring(self.Location) .. ' (' .. sWardTypes .. ')>';
end
