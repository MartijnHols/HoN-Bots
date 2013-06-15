local _G = getfenv(0);
local object = _G.object;

object.behaviorLib = object.behaviorLib or {};

local core, eventsLib, behaviorLib, metadata = object.core, object.eventsLib, object.behaviorLib, object.metadata;

local print, ipairs, pairs, string, table, next, type, tinsert, tremove, tsort, format, tostring, tonumber, strfind, strsub
	= _G.print, _G.ipairs, _G.pairs, _G.string, _G.table, _G.next, _G.type, _G.table.insert, _G.table.remove, _G.table.sort, _G.string.format, _G.tostring, _G.tonumber, _G.string.find, _G.string.sub
local ceil, floor, pi, tan, atan, atan2, abs, cos, sin, acos, min, max, random
	= _G.math.ceil, _G.math.floor, _G.math.pi, _G.math.tan, _G.math.atan, _G.math.atan2, _G.math.abs, _G.math.cos, _G.math.sin, _G.math.acos, _G.math.min, _G.math.max, _G.math.random

local BotEcho, VerboseLog, Clamp, skills = core.BotEcho, core.VerboseLog, core.Clamp, object.skills

runfile "/bots/HeroData.lua";
local HeroData = _G.HoNBots.HeroData;

runfile "/bots/HelperFunctions.lua";
local HelperFunctions = object.HelperFunctions;

runfile "/bots/Classes/Behavior.class.lua"; --TODO: turn into require when development for this class is finished

local classes = _G.HoNBots.Classes;

--------------------------------------------------
--          RetreatFromThreat Override          --
--------------------------------------------------
-- Original idea from: http://forums.heroesofnewerth.com/showthread.php?482309-Gravekeeper-Bot-v1-0

local behavior = classes.Behavior.Create('RetreatFromThreat');

-- Remove the legacy RetreatFromThreatBehavior
core.RemoveByValue(behaviorLib.tBehaviors, behaviorLib.RetreatFromThreatBehavior);

-- This also makes the reference: behaviorLib.Behaviors.RetreatFromThreatBehavior
behavior:AddToLegacyBehaviorRunner(behaviorLib);

behavior.nOldRetreatFactor = 0.9 -- Decrease the value of the normal retreat behavior

object.bEnemyThreatDebug = true;
object.nBaseThreat = 2 -- Base threat. Level differences and distance alter the actual threat level.
object.nFullHealthPoolThreat = 3;--TODO: Determine optimal value
object.nCanUseSkillsThreat = 3;--TODO: Determine optimal value
object.nMaxLevelDifferenceThreat = 6 -- The max threat for level difference (negative OR positive)
local function GetThreat(unit, vecMyPosition, vecUnitPosition, nMyDPS, nMyLevel, nMyItemWorth, bIsSelf)
	local nDistanceSq;
	if not bIsSelf then
		nDistanceSq = Vector3.Distance2DSq(vecMyPosition, vecUnitPosition);
		if nDistanceSq > 4622500 then -- out of PK range
			return 0;
		end
	end
	
	local heroData = HeroData:GetHeroData(unit:GetTypeName());
	
	local nThreat = heroData and heroData.Threat or 2;
	
	if object.bEnemyThreatDebug then
		print(object.myName .. ': Threat for ^y' .. unit:GetTypeName() .. '^*: ^y' .. nThreat .. '^*');
	end
	
	for i = 0, 8 do
		local abilInfo;
		if heroData then
			abilInfo = heroData:GetAbility(i);
		else
			if i == 0 or i == 1 or i == 2 or i == 3 then
				abilInfo = { Threat = 1 };
			else
				abilInfo = { Threat = 0 };
			end
		end
		
		if abilInfo and abilInfo.Threat > 0 then
			local abil = unit:GetAbility(i);
			local bCanActivate = abil and abil:CanActivate();
			
			if bCanActivate or bCanActivate == nil then --TODO: CanActivate currently returns nil for hostile heroes which is why we need to do this secondary check. If it becomes possible to track enemy hero cooldowns then this should be changed.
				nThreat = nThreat + abilInfo.Threat;
				
				if object.bEnemyThreatDebug then
					print(',+abil' .. i .. ': ^y' .. string.format("%.2f", nThreat) .. '^*');
				end
			end
		end
	end
	
	do -- Consider HP (0 - 3)
		nThreat = nThreat + object.nFullHealthPoolThreat * Clamp((HelperFunctions.GetHealthPercentage(unit) - 0.1) / 0.9, 0, 1);
		
		if object.bEnemyThreatDebug then
			print(',+health (' .. string.format("%.2f", HelperFunctions.GetHealthPercentage(unit)) .. '): ^y' .. string.format("%.2f", nThreat) .. '^*');
		end
	end
	
	do -- Consider mana (0 - 3)
		local nEnemyManaConsumption = HelperFunctions.GetTotalManaConsumption(unit);
		nThreat = nThreat + object.nCanUseSkillsThreat * min(1, (HelperFunctions.GetMana(unit) / nEnemyManaConsumption));
		
		if object.bEnemyThreatDebug then
			--BotEcho(unit:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after enemy mana (' .. string.format("%.2f", (HelperFunctions.GetMana(unit) / nEnemyManaConsumption)) .. ')');
			print(',+mana (' .. string.format("%.2f", (HelperFunctions.GetMana(unit) / nEnemyManaConsumption)) .. '): ^y' .. string.format("%.2f", nThreat) .. '^*');
		end
	end
	
	if not bIsSelf then
		do -- Consider levels (-4 - 4)
			local nMyLevel = nMyLevel;
			local nEnemyLevel = unit:GetLevel();
			
			nThreat = nThreat + Clamp(nEnemyLevel - nMyLevel, -object.nMaxLevelDifferenceThreat, object.nMaxLevelDifferenceThreat);
			
			if object.bEnemyThreatDebug then
				--BotEcho(unit:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after levels (' .. nEnemyLevel .. 'vs' .. nMyLevel .. ')');
				print(',+levels (' .. nEnemyLevel .. 'vs' .. nMyLevel .. '): ^y' .. string.format("%.2f", nThreat) .. '^*');
			end
		end
		
		do -- Consider attack DPS differences (-4 - 4)
			local nDPSThreatMultiplier = HelperFunctions.GetDPS(unit) / nMyDPS; -- fall back to my own DPS if the unit's DPS couldn't be calculated
			
			if nDPSThreatMultiplier > 1 then
				nThreat = nThreat + Clamp((nDPSThreatMultiplier - 1) * 1.5, 0, 4); -- enemy has more DPS
			else
				nThreat = nThreat - Clamp((1 / nDPSThreatMultiplier - 1) * 1.5, 0, 4); -- I have more DPS
			end
			
			if object.bEnemyThreatDebug then
				--BotEcho(unit:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after DPS multiplier (' .. string.format("%.2f", HelperFunctions.GetDPS(unit)) .. 'vs' .. string.format("%.2f", nMyDPS) .. ')');
				print(',+DPS multiplier (' .. string.format("%.2f", nDPSThreatMultiplier) .. '): ^y' .. string.format("%.2f", nThreat) .. '^*');
			end
		end
		
		do -- Consider items (-4 - 4)
			local nInventoryValueMult = HelperFunctions.GetInventoryValue(unit) / nMyItemWorth;
			
			if nInventoryValueMult > 1 then
				nThreat = nThreat + Clamp((nInventoryValueMult - 1) * 2, 0, 4); -- enemy has more items
			else
				nThreat = nThreat - Clamp((1 / nInventoryValueMult - 1) * 2, 0, 4); -- I have more items
			end
			
			if object.bEnemyThreatDebug then
				--BotEcho(unit:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after inventory value (' .. string.format("%.2f", nInventoryValueMult) .. ')');
				print(',+inventory value (' .. string.format("%.2f", nInventoryValueMult) .. '): ^y' .. string.format("%.2f", nThreat) .. '^*');
			end
		end
		
		do -- Consider range
			--Magic-Formel: Threat to Range, T(700²) = 2, T(1100²) = 1.5, T(2000²)= 0.75
			nThreat = nThreat * Clamp(3 * (112810000 - nDistanceSq) / (4 * (19 * nDistanceSq + 32810000)), 0.75, 2);
			
			if object.bEnemyThreatDebug then
				--BotEcho(unitEnemy:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after distance');
				print(',+distance (' .. string.format("%.2f", math.sqrt(nDistanceSq)) .. '): ^y' .. string.format("%.2f", nThreat) .. '^*\n');
			end
		end
	else
		nThreat = nThreat * 1;
		
		if object.bEnemyThreatDebug then
			--BotEcho(unitEnemy:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after distance');
			print(',+self: ^y' .. string.format("%.2f", nThreat) .. '^*\n');
		end
	end
	
	return nThreat;
end

behavior.lastRetreatEnemies = {};

function behavior:Utility(botBrain)
	local nUtilityOld = (behaviorLib.lastRetreatUtil - 4); -- Remember the old utility value and lower it by 4 utility value per frame (250ms) to let it decay slowly
	local nUtility = object.RetreatFromThreatUtilityOld(botBrain) * self.nOldRetreatFactor
	
	-- If the old utility value is higher then the new then use the old
	if nUtilityOld > nUtility then
		nUtility = nUtilityOld;
		behaviorLib.lastRetreatUtil = nUtilityOld;
	end
	
	-- Reset the nearby enemies
	self.lastRetreatEnemies = {};
	
	local unitSelf = core.unitSelf;
	local vecMyPosition = unitSelf:GetPosition();
	local nMyDPS = HelperFunctions.GetDPS(unitSelf);
	local nMyLevel = unitSelf:GetLevel();
	local nMyInventoryValue = HelperFunctions.GetInventoryValue(unitSelf); -- sum value of my items
	
	--calculate the threat-value and increase utility value
	local nEnemyThreat = 0;
	for id, unit in pairs(HoN.GetHeroes(core.enemyTeam)) do
		if unit ~= nil and unit:IsAlive() then
			if object.bEnemyThreatDebug then
				core.DrawXPosition(HelperFunctions.GetEnemyPosition(unit), 'red')
			end
			local nThreat = GetThreat(unit, vecMyPosition, HelperFunctions.GetEnemyPosition(unit), nMyDPS, nMyLevel, nMyInventoryValue);
			nEnemyThreat = nEnemyThreat + nThreat;
			if nThreat ~= 0 then
				tinsert(self.lastRetreatEnemies, unit);
			end
		end
	end
	if nEnemyThreat > 0 then
		for id, unit in pairs(HoN.GetHeroes(core.myTeam)) do
			if unit ~= nil and unit:IsAlive() then
				nEnemyThreat = nEnemyThreat - GetThreat(unit, vecMyPosition, unit:GetPosition(), nMyDPS, nMyLevel, nMyInventoryValue, (unit == unitSelf.object));
			end
		end
		
		nUtility = nUtility + nEnemyThreat;
		if object.bEnemyThreatDebug then
			BotEcho('Total threat: ' .. nUtility);
		end
	end
	
	return Clamp(nUtility, 0, 100)
end
object.RetreatFromThreatUtilityOld =  behaviorLib.RetreatFromThreatUtility

behavior.retreatIceImprisonmentThreshold = 50;
function behavior:Execute(botBrain)
	if object.bEnemyThreatDebug then
		core.DrawXPosition(core.unitSelf:GetPosition(), 'red'); -- draw a red cross on our hero to indicate this behavior is active
	end
	
	do -- Check if we can port out
		--TODO: Add a check if we can port out of this mess
	end
	
	do -- Ice Imprisonment
		local nIceImprisonmentRangeSq = skills.abilIceImprisonment:GetRange();
		nIceImprisonmentRangeSq = nIceImprisonmentRangeSq * nIceImprisonmentRangeSq;
		
		local vecMyPosition = core.unitSelf:GetPosition();
		local unitTarget = behaviorLib.heroTarget;
		local vecTargetPosition = unitTarget and unitTarget:GetPosition();
		if not unitTarget or not vecTargetPosition or Vector3.Distance2DSq(vecTargetPosition, vecMyPosition) > nIceImprisonmentRangeSq then
			-- If we don't have a target or he isn't visible or he is out of range, then select a different target
			for i = 1, #self.lastRetreatEnemies do
				local unitEnemy = self.lastRetreatEnemies[i];
				local vecEnemyPosition = unitEnemy:GetPosition(); -- returns nil if unit is not visible
				if vecEnemyPosition and Vector3.Distance2DSq(vecEnemyPosition, vecMyPosition) < nIceImprisonmentRangeSq then
					unitTarget = unitEnemy;
					vecTargetPosition = vecEnemyPosition;
					break;
				end
			end
		end
		
		if behaviorLib.lastRetreatUtil > behavior.retreatIceImprisonmentThreshold and unitTarget then
			local bTargetDisabled = unitTarget:IsStunned() or unitTarget:IsImmobilized();
			
			if not bTargetDisabled then
				-- Cast Ice Imprisonment
				local abilIceImprisonment = skills.abilIceImprisonment
				if abilIceImprisonment:CanActivate() then
					return core.OrderAbilityEntity(botBrain, abilIceImprisonment, unitTarget);
				end
			end
		end
	end
	
	local vecPos = behaviorLib.PositionSelfBackUp();
	
	core.DrawXPosition(vecPos, 'yellow');
	if not behaviorLib.MoveExecute(botBrain, vecPos) then
		return core.OrderMoveToPosAndHoldClamp(botBrain, core.unitSelf, vecPos, false);
	end
	return true;
end
object.RetreatFromThreatExecuteOld = behaviorLib.RetreatFromThreatExecute

