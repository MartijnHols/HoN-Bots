local _G = getfenv(0);
local object = _G.object;

object.behaviorLib = object.behaviorLib or {};

local core, eventsLib, behaviorLib, metadata = object.core, object.eventsLib, object.behaviorLib, object.metadata;

local print, ipairs, pairs, string, table, next, type, tinsert, tremove, tsort, format, tostring, tonumber, strfind, strsub
	= _G.print, _G.ipairs, _G.pairs, _G.string, _G.table, _G.next, _G.type, _G.table.insert, _G.table.remove, _G.table.sort, _G.string.format, _G.tostring, _G.tonumber, _G.string.find, _G.string.sub
local ceil, floor, pi, tan, atan, atan2, abs, cos, sin, acos, min, max, random
	= _G.math.ceil, _G.math.floor, _G.math.pi, _G.math.tan, _G.math.atan, _G.math.atan2, _G.math.abs, _G.math.cos, _G.math.sin, _G.math.acos, _G.math.min, _G.math.max, _G.math.random

local BotEcho, VerboseLog, Clamp, skills = core.BotEcho, core.VerboseLog, core.Clamp, object.skills

runfile "/bots/UnitUtils.lua";
local UnitUtils = object.UnitUtils;

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
behavior.bDebug = true;
UnitUtils.bEnemyThreatDebug = behavior.bDebug;

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
	
	--calculate the threat-value and increase utility value
	local nEnemyThreat = 0;
	for id, unit in pairs(HoN.GetHeroes(core.enemyTeam)) do
		if unit ~= nil and unit:IsAlive() then
			if behavior.bDebug then
				core.DrawXPosition(UnitUtils.GetEnemyPosition(unit), 'red')
			end
			local nThreat = UnitUtils.GetThreat(core.unitSelf, unit);
			nEnemyThreat = nEnemyThreat + nThreat;
			if nThreat ~= 0 then
				tinsert(self.lastRetreatEnemies, unit);
			end
		end
	end
	if nEnemyThreat > 0 then
		for id, unit in pairs(HoN.GetHeroes(core.myTeam)) do
			if unit ~= nil and unit:IsAlive() then
				nEnemyThreat = nEnemyThreat - UnitUtils.GetThreat(core.unitSelf, unit);
			end
		end
		
		nUtility = nUtility + nEnemyThreat;
		if behavior.bDebug then
			BotEcho('Total threat: ' .. nUtility);
		end
	end
	
	return Clamp(nUtility, 0, 100)
end
object.RetreatFromThreatUtilityOld =  behaviorLib.RetreatFromThreatUtility

behavior.retreatIceImprisonmentThreshold = 50;
function behavior:Execute(botBrain)
	if behavior.bDebug then
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

