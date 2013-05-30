--GlaciusSupportBot v1.0

local _G = getfenv(0)
local object = _G.object

object.myName = object:GetName()

object.bRunLogic 		= true
object.bRunBehaviors	= true
object.bUpdates 		= true
object.bUseShop 		= true

object.bRunCommands 	= true
object.bMoveCommands 	= true
object.bAttackCommands 	= true
object.bAbilityCommands = true
object.bOtherCommands 	= true

object.bReportBehavior = false
object.bDebugUtility = true
object.bDebugExecute = false


object.logger = {}
object.logger.bWriteLog = false
object.logger.bVerboseLog = false

object.core 		= {}
object.eventsLib 	= {}
object.metadata 	= {}
object.behaviorLib 	= {}
object.skills 		= {}

runfile "bots/core.lua"
runfile "bots/botbraincore.lua"
runfile "bots/eventsLib.lua"
runfile "bots/metadata.lua"
runfile "bots/behaviorLib.lua"
runfile "/bots/Behaviors/WardBehavior.lua"

local core, eventsLib, behaviorLib, metadata, skills = object.core, object.eventsLib, object.behaviorLib, object.metadata, object.skills

local print, ipairs, pairs, string, table, next, type, tinsert, tremove, tsort, format, tostring, tonumber, strfind, strsub
	= _G.print, _G.ipairs, _G.pairs, _G.string, _G.table, _G.next, _G.type, _G.table.insert, _G.table.remove, _G.table.sort, _G.string.format, _G.tostring, _G.tonumber, _G.string.find, _G.string.sub
local ceil, floor, pi, tan, atan, atan2, abs, cos, sin, acos, max, random
	= _G.math.ceil, _G.math.floor, _G.math.pi, _G.math.tan, _G.math.atan, _G.math.atan2, _G.math.abs, _G.math.cos, _G.math.sin, _G.math.acos, _G.math.max, _G.math.random

local BotEcho, VerboseLog, BotLog = core.BotEcho, core.VerboseLog, core.BotLog
local Clamp = core.Clamp

local sqrtTwo = math.sqrt(2)

BotEcho('loading glacius_main...')

object.heroName = 'Hero_Frosty'

-------------------------------------------------------------------------------------
-- This ugly workaround is meant to prevent this bot from being sent to a solo lane. In order to do that we need to override teamBotBrain.FindBestLaneSolo.
-- HOWEVER! Loading of bots is currently bugged where the first bot will be loaded BEFORE the TeamBotBrain. This means attempting to override a TeamBotBrain
-- function would not work. Therefore we need to do this when the bot is about to be initialized (which always happens AFTER the team bot brain has been initialized).

local oldCoreInitialize = core.CoreInitialize;
function core.CoreInitialize(botBrain, ...)
	local returnValue = oldCoreInitialize(botBrain, ...);
	
	core.BotEcho('CoreInitialize-override running');
	
	local teamBotBrain = HoN.GetTeamBotBrain();
	-- Override teamBotBrain.FindBestLaneSolo to prevent Glacius from going mid unless there is nobody else
	if not teamBotBrain.bGlaciusFindBestLaneSoloOverridden then
		local oldFindBestLaneSolo = teamBotBrain.FindBestLaneSolo;
		function teamBotBrain.FindBestLaneSolo(tAvailableHeroes)
			local tempAvailableHeroes = {};
			local unitGlacius = nil;
			for k, unit in pairs(tAvailableHeroes) do
				if unit:GetTypeName() ~= 'Hero_Frosty' then
					table.insert(tempAvailableHeroes, unit);
				else
					unitGlacius = unit; -- remember our Glacius so that we can always fallback
				end
			end
			
			local unitBestSolo = oldFindBestLaneSolo(tempAvailableHeroes);
			
			return unitBestSolo or unitGlacius;
		end
		teamBotBrain.bGlaciusFindBestLaneSoloOverridden = true;
	end
	
	-- One time check to see if we have a human ally, alternatively we could run (core.NumberElements(self.tAllyHumanHeroes) > 0) to check this, but I'm pretty sure a bool is quicker
	core.bHaveHumanAlly = false;
	for _, v in pairs(HoN.GetHeroes(core.myTeam)) do
		if not v:IsBotControlled() then
			core.bHaveHumanAlly = true;
			core.BotEcho('We have a human ally in our team!');
			break;
		end
	end
	
	return returnValue;
end

--------------------------------
-- Skills
--------------------------------
function object:SkillBuild()
local unitSelf = self.core.unitSelf

	if skills.abilTundraBlast == nil then
		skills.abilTundraBlast		= unitSelf:GetAbility(0)
		skills.abilIceImprisonment	= unitSelf:GetAbility(1)
		skills.abilChillingPresence	= unitSelf:GetAbility(2)
		skills.abilGlacialDownpour	= unitSelf:GetAbility(3)
		skills.abilAttributeBoost	= unitSelf:GetAbility(4)
	end

	if unitSelf:GetAbilityPointsAvailable() <= 0 then
		return
	end
	
	--speicific level 1 and two skills
	if skills.abilTundraBlast:GetLevel() < 1 then
		skills.abilTundraBlast:LevelUp()
	elseif skills.abilIceImprisonment:GetLevel() < 1 then
		skills.abilIceImprisonment:LevelUp()
	--max in this order {glacial downpour, chilling presence, ice imprisonment, tundra blast, stats}
	elseif skills.abilGlacialDownpour:CanLevelUp() then
		skills.abilGlacialDownpour:LevelUp()
	elseif skills.abilChillingPresence:CanLevelUp() then
		skills.abilChillingPresence:LevelUp()
	elseif skills.abilIceImprisonment:CanLevelUp() then
		skills.abilIceImprisonment:LevelUp()
	elseif skills.abilTundraBlast:CanLevelUp() then
		skills.abilTundraBlast:LevelUp()
	else
		skills.abilAttributeBoost:LevelUp()
	end	
end

---------------------------------------------------
--                   Overrides                   --
---------------------------------------------------

--[[for testing
function object:onthinkOverride(...)
	self:onthinkOld(...)
	
	--
end
object.onthinkOld = object.onthink
object.onthink 	= object.onthinkOverride
--]]

----------------------------------
--	Glacius specific harass bonuses
--
--  Abilities off cd increase harass util
--  Ability use increases harass util for a time
----------------------------------

object.nTundraBlastUpBonus = 8
object.nIceImprisonmentUpBonus = 10
object.nGlacialDownpourUpBonus = 18
object.nSheepstickUp = 12

object.nTundraBlastUseBonus = 12
object.nIceImprisonmentUseBonus = 17.5
object.nGlacialDownpourUseBonus = 35
object.nSheepstickUse = 16

object.nTundraBlastThreshold = 30
object.nIceImprisonmentThreshold = 35
object.nGlacialDownpourThreshold = 40
object.nSheepstickThreshold = 30

local function AbilitiesUpUtilityFn()
	local nUtility = 0
	
	if skills.abilTundraBlast:CanActivate() then
		nUtility = nUtility + object.nTundraBlastUpBonus
	end
	
	if skills.abilIceImprisonment:CanActivate() then
		nUtility = nUtility + object.nIceImprisonmentUpBonus
	end
		
	if skills.abilGlacialDownpour:CanActivate() then
		nUtility = nUtility + object.nGlacialDownpourUpBonus
	end
	
	if object.itemSheepstick and object.itemSheepstick:CanActivate() then
		nUtility = nUtility + object.nSheepstickUp
	end
	
	return nUtility
end

--ability use gives bonus to harass util for a while
function object:oncombateventOverride(EventData)
	self:oncombateventOld(EventData)
	
	local nAddBonus = 0
	
	if EventData.Type == "Ability" then
		--BotEcho("ABILILTY EVENT!  InflictorName: "..EventData.InflictorName)		
		if EventData.InflictorName == "Ability_Frosty1" then
			nAddBonus = nAddBonus + object.nTundraBlastUseBonus
		elseif EventData.InflictorName == "Ability_Frosty2" then
			nAddBonus = nAddBonus + object.nIceImprisonmentUseBonus
		elseif EventData.InflictorName == "Ability_Frosty4" then
			nAddBonus = nAddBonus + object.nGlacialDownpourUseBonus
		end
	elseif EventData.Type == "Item" then
		if core.itemSheepstick ~= nil and EventData.SourceUnit == core.unitSelf:GetUniqueID() and EventData.InflictorName == core.itemSheepstick:GetName() then
			nAddBonus = nAddBonus + self.nSheepstickUse
		end
	end
	
	if nAddBonus > 0 then
		--decay before we add
		core.DecayBonus(self)
	
		core.nHarassBonus = core.nHarassBonus + nAddBonus
	end
end
object.oncombateventOld = object.oncombatevent
object.oncombatevent 	= object.oncombateventOverride

--Utility calc override
local function CustomHarassUtilityOverride(hero)
	local nUtility = AbilitiesUpUtilityFn()
	
	return nUtility
end
behaviorLib.CustomHarassUtility = CustomHarassUtilityOverride  


----------------------------------
--	Glacius harass actions
----------------------------------
function object.GetTundraBlastRadius()
	return 400
end

function object.GetGlacialDownpourRadius()
	return 635
end

local function HarassHeroExecuteOverride(botBrain)
	local bDebugEchos = false
	
	local unitTarget = behaviorLib.heroTarget
	if unitTarget == nil then
		return false --can not execute, move on to the next behavior
	end
	
	local unitSelf = core.unitSelf
	local vecMyPosition = unitSelf:GetPosition()
	local nMyExtraRange = core.GetExtraRange(unitSelf)
	
	local vecTargetPosition = unitTarget:GetPosition()
	local nTargetExtraRange = core.GetExtraRange(unitTarget)
	local nTargetDistanceSq = Vector3.Distance2DSq(vecMyPosition, vecTargetPosition)
	local bTargetRooted = unitTarget:IsStunned() or unitTarget:IsImmobilized() or unitTarget:GetMoveSpeed() < 200
	
	local nLastHarassUtil = behaviorLib.lastHarassUtil
	local bCanSee = core.CanSeeUnit(botBrain, unitTarget)	
	
	if bDebugEchos then BotEcho("Glacius HarassHero at "..nLastHarassUtil) end
	local bActionTaken = false
	
	if unitSelf:IsChanneling() then
		--continue to do so
		--TODO: early break logic
		return
	end

	--since we are using an old pointer, ensure we can still see the target for entity targeting
	if core.CanSeeUnit(botBrain, unitTarget) then
		local bTargetVuln = unitTarget:IsStunned() or unitTarget:IsImmobilized()

		--Sheepstick
		if not bActionTaken and not bTargetVuln then
			local itemSheepstick = core.itemSheepstick
			if itemSheepstick then
				local nRange = itemSheepstick:GetRange()
				if itemSheepstick:CanActivate() and nLastHarassUtil > object.nSheepstickThreshold then
					if nTargetDistanceSq < (nRange * nRange) then
						bActionTaken = core.OrderItemEntityClamp(botBrain, unitSelf, itemSheepstick, unitTarget)
					end
				end
			end
		end

		
		--ice imprisonment
		if not bActionTaken and not bTargetRooted and nLastHarassUtil > botBrain.nIceImprisonmentThreshold and bCanSee then
			if bDebugEchos then BotEcho("  No action yet, checking ice imprisonment") end
			local abilIceImprisonment = skills.abilIceImprisonment
			if abilIceImprisonment:CanActivate() then
				local nRange = abilIceImprisonment:GetRange()
				if nTargetDistanceSq < (nRange * nRange) then
					bActionTaken = core.OrderAbilityEntity(botBrain, abilIceImprisonment, unitTarget)
				end
			end
		end
	end
	
	--tundra blast
	if not bActionTaken and nLastHarassUtil > botBrain.nTundraBlastThreshold then
		if bDebugEchos then BotEcho("  No action yet, checking tundra blast") end
		local abilTundraBlast = skills.abilTundraBlast
		if abilTundraBlast:CanActivate() then
			local abilTundraBlast = skills.abilTundraBlast
			local nRadius = botBrain.GetTundraBlastRadius()
			local nRange = skills.abilTundraBlast and skills.abilTundraBlast:GetRange() or nil
			local vecTarget = core.AoETargeting(unitSelf, nRange, nRadius, true, unitTarget, core.enemyTeam, nil)
				
			if vecTarget then
				bActionTaken = core.OrderAbilityPosition(botBrain, abilTundraBlast, vecTarget)
			end
		end
	end
	
	--ult
	if not bActionTaken and nLastHarassUtil > botBrain.nGlacialDownpourThreshold then
		if bDebugEchos then BotEcho("  No action yet, checking glacial downpour.") end
		local abilGlacialDownpour = skills.abilGlacialDownpour
		if abilGlacialDownpour:CanActivate() then
			--get the target well within the radius for maximum effect
			local nRadius = botBrain.GetGlacialDownpourRadius()
			local nHalfRadiusSq = nRadius * nRadius * 0.25
			if nTargetDistanceSq <= nHalfRadiusSq then
				bActionTaken = core.OrderAbility(botBrain, abilGlacialDownpour)
			elseif not unitSelf:IsAttackReady() then
				--move in when we aren't attacking
				core.OrderMoveToUnit(botBrain, unitSelf, unitTarget)
				bActionTaken = true
			end
		end
	end
		
	if not bActionTaken then
		if bDebugEchos then BotEcho("  No action yet, proceeding with normal harass execute.") end
		return object.harassExecuteOld(botBrain)
	end
end
object.harassExecuteOld = behaviorLib.HarassHeroBehavior["Execute"]
behaviorLib.HarassHeroBehavior["Execute"] = HarassHeroExecuteOverride


----------------------------------
--  FindItems Override
----------------------------------
local function funcFindItemsOverride(botBrain)
	object.FindItemsOld(botBrain)

	if core.itemAstrolabe ~= nil and not core.itemAstrolabe:IsValid() then
		core.itemAstrolabe = nil
	end
	if core.itemSheepstick ~= nil and not core.itemSheepstick:IsValid() then
		core.itemSheepstick = nil
	end
	if core.itemWardOfSight ~= nil and not core.itemWardOfSight:IsValid() then
		core.itemWardOfSight = nil
	end

	--only update if we need to
	if core.itemSheepstick and core.itemAstrolabe and core.itemWardOfSight then
		return
	end

	local inventory = core.unitSelf:GetInventory(false)
	for slot = 1, 6, 1 do -- DO NOTICE! Default bots loop through slots 1 through 12; this is errorous as it will act like items in the stash are available.
		local curItem = inventory[slot]
		if curItem then
			if core.itemAstrolabe == nil and curItem:GetName() == "Item_Astrolabe" then
				core.itemAstrolabe = core.WrapInTable(curItem)
				core.itemAstrolabe.nHealValue = 200
				core.itemAstrolabe.nRadius = 600
				--Echo("Saving astrolabe")
			elseif core.itemSheepstick == nil and curItem:GetName() == "Item_Morph" then
				core.itemSheepstick = core.WrapInTable(curItem)
			elseif core.itemWardOfSight == nil and curItem:GetName() == "Item_FlamingEye" then
				core.itemWardOfSight = core.WrapInTable(curItem);
			end
		end
	end
end
object.FindItemsOld = core.FindItems
core.FindItems = funcFindItemsOverride


--TODO: extract this out to behaviorLib
----------------------------------
--	Glacius's Help behavior
--	
--	Utility: 
--	Execute: Use Astrolabe
----------------------------------
behaviorLib.nHealUtilityMul = 0.8
behaviorLib.nHealHealthUtilityMul = 1.0
behaviorLib.nHealTimeToLiveUtilityMul = 0.5

function behaviorLib.HealHealthUtilityFn(unitHero)
	local nUtility = 0
	
	local nYIntercept = 100
	local nXIntercept = 100
	local nOrder = 2

	nUtility = core.ExpDecay(unitHero:GetHealthPercent() * 100, nYIntercept, nXIntercept, nOrder)
	
	return nUtility
end

function behaviorLib.TimeToLiveUtilityFn(unitHero)
	--Increases as your time to live based on your damage velocity decreases
	local nUtility = 0
	
	local nHealthVelocity = unitHero:GetHealthVelocity()
	local nHealth = unitHero:GetHealth()
	local nTimeToLive = 9999
	if nHealthVelocity < 0 then
		nTimeToLive = nHealth / (-1 * nHealthVelocity)
		
		local nYIntercept = 100
		local nXIntercept = 20
		local nOrder = 2
		nUtility = core.ExpDecay(nTimeToLive, nYIntercept, nXIntercept, nOrder)
	end
	
	nUtility = Clamp(nUtility, 0, 100)
	
	--BotEcho(format("%d timeToLive: %g  healthVelocity: %g", HoN.GetGameTime(), nTimeToLive, nHealthVelocity))
	
	return nUtility, nTimeToLive
end

behaviorLib.nHealCostBonus = 10
behaviorLib.nHealCostBonusCooldownThresholdMul = 4.0
function behaviorLib.AbilityCostBonusFn(unitSelf, ability)
	local bDebugEchos = false
	
	local nCost =		ability:GetManaCost()
	local nCooldownMS =	ability:GetCooldownTime()
	local nRegen =		unitSelf:GetManaRegen()
	
	local nTimeToRegenMS = nCost / nRegen * 1000
	
	if bDebugEchos then BotEcho(format("AbilityCostBonusFn - nCost: %d  nCooldown: %d  nRegen: %g  nTimeToRegen: %d", nCost, nCooldownMS, nRegen, nTimeToRegenMS)) end
	if nTimeToRegenMS < nCooldownMS * behaviorLib.nHealCostBonusCooldownThresholdMul then
		return behaviorLib.nHealCostBonus
	end
	
	return 0
end

behaviorLib.unitHealTarget = nil
behaviorLib.nHealTimeToLive = nil
function behaviorLib.HealUtility(botBrain)
	local bDebugEchos = false
	
	--[[
	if object.myName == "Bot1" then
		bDebugEchos = true
	end
	--]]
	if bDebugEchos then BotEcho("HealUtility") end
	
	local nUtility = 0

	local unitSelf = core.unitSelf
	behaviorLib.unitHealTarget = nil
	
	local itemAstrolabe = core.itemAstrolabe
	
	local nHighestUtility = 0
	local unitTarget = nil
	local nTargetTimeToLive = nil
	local sAbilName = ""
	if itemAstrolabe and itemAstrolabe:CanActivate() then
		local tTargets = core.CopyTable(core.localUnits["AllyHeroes"])
		tTargets[unitSelf:GetUniqueID()] = unitSelf --I am also a target
		for key, hero in pairs(tTargets) do
			--Don't heal ourself if we are going to head back to the well anyway, 
			--	as it could cause us to retrace half a walkback
			if hero:GetUniqueID() ~= unitSelf:GetUniqueID() or core.GetCurrentBehaviorName(botBrain) ~= "HealAtWell" then
				local nCurrentUtility = 0
				
				local nHealthUtility = behaviorLib.HealHealthUtilityFn(hero) * behaviorLib.nHealHealthUtilityMul
				local nTimeToLiveUtility = nil
				local nCurrentTimeToLive = nil
				nTimeToLiveUtility, nCurrentTimeToLive = behaviorLib.TimeToLiveUtilityFn(hero)
				nTimeToLiveUtility = nTimeToLiveUtility * behaviorLib.nHealTimeToLiveUtilityMul
				nCurrentUtility = nHealthUtility + nTimeToLiveUtility
				
				if nCurrentUtility > nHighestUtility then
					nHighestUtility = nCurrentUtility
					nTargetTimeToLive = nCurrentTimeToLive
					unitTarget = hero
					if bDebugEchos then BotEcho(format("%s Heal util: %d  health: %d  ttl:%d", hero:GetTypeName(), nCurrentUtility, nHealthUtility, nTimeToLiveUtility)) end
				end
			end
		end

		if unitTarget then
			nUtility = nHighestUtility				
			sAbilName = "Astrolabe"
		
			behaviorLib.unitHealTarget = unitTarget
			behaviorLib.nHealTimeToLive = nTargetTimeToLive
		end		
	end
	
	if bDebugEchos then BotEcho(format("    abil: %s util: %d", sAbilName, nUtility)) end
	
	nUtility = nUtility * behaviorLib.nHealUtilityMul
	
	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  HelpUtility: %g", nUtility))
	end
	
	return nUtility
end

function behaviorLib.HealExecute(botBrain)
	local itemAstrolabe = core.itemAstrolabe
	
	local unitHealTarget = behaviorLib.unitHealTarget
	local nHealTimeToLive = behaviorLib.nHealTimeToLive
	
	if unitHealTarget and itemAstrolabe and itemAstrolabe:CanActivate() then 
		local unitSelf = core.unitSelf
		local vecTargetPosition = unitHealTarget:GetPosition()
		local nDistance = Vector3.Distance2D(unitSelf:GetPosition(), vecTargetPosition)
		if nDistance < itemAstrolabe.nRadius then
			core.OrderItemClamp(botBrain, unitSelf, itemAstrolabe)
		else
			core.OrderMoveToUnitClamp(botBrain, unitSelf, unitHealTarget)
		end
	else
		return false
	end
	
	return true
end

behaviorLib.HealBehavior = {}
behaviorLib.HealBehavior["Utility"] = behaviorLib.HealUtility
behaviorLib.HealBehavior["Execute"] = behaviorLib.HealExecute
behaviorLib.HealBehavior["Name"] = "Heal"
tinsert(behaviorLib.tBehaviors, behaviorLib.HealBehavior)







-----------------------------------------------------------------------------------------------------------
---------------------------------------- Pre-Game support behavior ----------------------------------------
--- Default pre-game behavior puts bots at the base tower 15 seconds before creeps spawn. This will		---
--- move Glacius there 15 seconds earlier so that our bot can be in time to ward camp blocks (at 0:00).	---
--- The utility value also needs to be lowered so the ward behavior can beat it.						---
-----------------------------------------------------------------------------------------------------------

local nLastLaneReassesTime = 0;
function behaviorLib.PreGameUtility(botBrain)
	local utility = 0;

	if HoN:GetMatchTime() <= 0 then
		utility = 50;
	end

	if botBrain.bDebugUtility == true and utility ~= 0 then
		BotEcho(format("  PreGameUtility: %g", utility));
	end

	return utility;
end
behaviorLib.PreGameBehavior["Utility"] = behaviorLib.PreGameUtility;

local bStillHaveToAnnounceRole = true;
function behaviorLib.PreGameExecute(botBrain)
	-- We need to lower the initial bot move time so the TeamBotBrain builds lanes and we have enough time to move all the way to the first ward spot
	-- Not changing this value will prevent the team bot brain from assigning a lane to Glacius which will mess up warding
	if core.teamBotBrain.nInitialBotMove < 30000 then
		core.teamBotBrain.nInitialBotMove = 30000;
	end
	local nGameTimeMS = HoN.GetGameTime();
	if core.teamBotBrain.laneReassessTime > (nGameTimeMS + HoN.GetRemainingPreMatchTime() + core.teamBotBrain.laneDoubleCheckTime) then
		-- If the next lane reasses time is set to after the pregame then we must adjust it to be earlier so that changing nInitialBotMove doesn't screw up the lane building
		BotEcho('Adjusting lane reasses time. now:' .. nGameTimeMS .. ' oldreassestime:' .. core.teamBotBrain.laneReassessTime .. ' newreassestime:' .. nGameTimeMS + core.teamBotBrain.laneDoubleCheckTime);
		core.teamBotBrain.laneReassessTime = nGameTimeMS + core.teamBotBrain.laneDoubleCheckTime
	end
	
	-- Same old
	if HoN.GetRemainingPreMatchTime() > core.teamBotBrain.nInitialBotMove then
		core.OrderHoldClamp(botBrain, core.unitSelf);
	else
		local vecTargetPos = behaviorLib.PositionSelfTraverseLane(botBrain)
		core.OrderMoveToPosClamp(botBrain, core.unitSelf, vecTargetPos, false)
	end
	
	if bStillHaveToAnnounceRole and HoN.GetRemainingPreMatchTime() < 85000 and HoN.GetRemainingPreMatchTime() > 0 then
		-- Wait a few seconds then inform the team about our role
		botBrain:ChatTeam('Greetings ladies and gentlemen! I will serve as your personal support today so please leave the warding to me. Enjoy the match. :)');
		bStillHaveToAnnounceRole = nil;
	end
end
behaviorLib.PreGameBehavior["Execute"] = behaviorLib.PreGameExecute;

	











-----------------------------------------------------------------------------------------------------------
----------------------------------------- Rune picking up behavior ----------------------------------------
--- Behavior to pick up the rune. The utility value increases based on how close we are to the rune.	---
--- See http://forums.heroesofnewerth.com/showthread.php?480575-Snippet-Rune-tracker&p=15559639			---
--TODO: move this to the behaviorlib.lua (this behavior is more important on other heroes, especially those going mid)
-----------------------------------------------------------------------------------------------------------


-- REVAMP: Refresher Rune added
-- Both rune spots get a rune, actual rune is opposite of Refresher Rune
-- Announce where a rune is to those pesky humans, pick up if I should

--TODO: Once warding behavior is done we should work on this, remove the runetracker dependency and work out an optimal way to handle the refresher rune
--runfile (object.sBotFilesRoot .. "RuneTracker/RuneTracker.lua");
--
--local runeTracker = object.runeTracker;
--
--local function PickupRune(botBrain, unitRune)
--	local vecRunePosition = unitRune:GetPosition();
--	
--	if vecRunePosition then
--		local nDistance = Vector3.Distance2DSq(core.unitSelf:GetPosition(), vecRunePosition);
--		
--		if nDistance < 10000 then
--			core.OrderTouch(botBrain, core.unitSelf, unitRune);
--		else
--			core.OrderMoveToPosClamp(botBrain, core.unitSelf, vecRunePosition, false);
--		end
--		
--		return true;
--	end
--	
--	return false;
--end
--local tRuneNames = {
--	['Powerup_Damage'] = '^bDouble damage rune',
--	['Powerup_Illusion'] = '^pIllusions rune',
--	['Powerup_MoveSpeed'] = '^rHaste rune',
--	['Powerup_Regen'] = '^gRegeneration rune',
--	['Powerup_Stealth'] = '^333Invisibility rune',
--};
--local unitLastAnnouncedRune;
--local function AnnounceRune(botBrain, unitRune, sRuneLocation)
--	if unitLastAnnouncedRune ~= unitRune then
--		local sRuneType = unitRune:GetTypeName();
--		Dump(unitRune:GetTypeName())
--		local msg = string.format('%s ^wis ^y%s^w.', tRuneNames[sRuneType] or sRuneType, sRuneLocation);
--		
--		core.BotEcho(msg);
--		--core.TeamChat(msg); -- this is dead?
--		botBrain:ChatTeam(msg);
--		
--		unitLastAnnouncedRune = unitRune;
--	end
--	
--	return false;
--end
--
--local tShouldPickupRune = {
--	['Powerup_Damage'] = function (unitRune)
--		if not core.bHaveHumanAlly then -- or nobody near or a hostile unit might take it or we have much more base damage or (humans don't have the hp and no bottle)
--			return true;
--		else
--			return false;
--		end
--	end,
--	['Powerup_Illusion'] = function (unitRune)
--		if not core.bHaveHumanAlly then -- until we have proper illusions support we shouldn't pick up this rune at all if a human could instead
--			return true;
--		else
--			return false;
--		end
--	end,
--	['Powerup_MoveSpeed'] = function (unitRune)
--		if not core.bHaveHumanAlly then -- or nobody near or we're in trouble or a hostile unit might take it
--			return true;
--		else
--			return false;
--		end
--	end,
--	['Powerup_Regen'] = function (unitRune)
--		if not core.bHaveHumanAlly then -- or we have low HP/mana and nobody else with low hp/mana is near
--			return true;
--		else
--			return false;
--		end
--	end,
--	['Powerup_Stealth'] = function (unitRune)
--		if not core.bHaveHumanAlly then -- or I am in danger or humans aren't near and humans don't have bottle
--			return true;
--		else
--			return false;
--		end
--	end,
--	['Powerup_Refresh'] = function (unitRune)
--		if not core.bHaveHumanAlly then -- or I am in danger or humans aren't near and humans don't have bottle
--			return true;
--		else
--			return false;
--		end
--	end,
--	--['Powerup_Super'] = function (unitRune) -- Mid Wars exclusive rune
--	--	-- Mid wars isn't supported
--	--end,
--	['Default'] = function (unitRune)
--		if unitRune then
--			Echo('Rune "' .. unitRune:GetTypeName() .. '" not recognized!');
--		end
--		return false;
--	end,
--};
--
--function behaviorLib.RuneUtility(botBrain)
--	runeTracker.Update();
--	
--	local nUtility = 0;
--	
--	local vecRunePosition = nil;
--	if runeTracker.IsTop() then
--		vecRunePosition = runeTracker.GetTopRunePosition();
--	elseif runeTracker.IsBottom() then
--		vecRunePosition = runeTracker.GetBottomRunePosition();
--	end
--	if vecRunePosition then
--		local nDistance = Vector3.Distance2D(core.unitSelf:GetPosition(), vecRunePosition);
--		
--		nUtility = nUtility + 10 + core.ParabolicDecayFn(nDistance, 30, 4000); -- the closer the bot gets the higher the utility value
--	end
--	
--	--if nUtility > 0 then
--	--	BotEcho('Rune utility: ' .. nUtility);
--	--end
--	
--	return nUtility;
--end
--
--function behaviorLib.RuneExecute(botBrain)
--	--runeTracker.Update(); -- we already update in utility, useless to do so twice within the same frame
--	
--	local sRuneLocation = '';
--	if runeTracker.IsTop() then
--		sRuneLocation = 'top';
--	elseif runeTracker.IsBottom() then
--		sRuneLocation = 'bot';
--	end
--	
--	local unitRune = runeTracker.GetCurrentRune();
--	
--	if unitRune then
--		local sRuneType = unitRune:GetTypeName();
--		
--		local funcShouldPickupRune = tShouldPickupRune[sRuneType] or tShouldPickupRune['Default'];
--		
--		if funcShouldPickupRune(unitRune) then
--			return PickupRune(botBrain, unitRune, sRuneLocation);
--		else
--			-- If the rune shouldn't be picked up we should announce it to the team
--			return AnnounceRune(botBrain, unitRune, sRuneLocation);
--		end
--	end
--	
--	return false;
--end
--
--behaviorLib.RuneBehavior = {};
--behaviorLib.RuneBehavior["Utility"] = behaviorLib.RuneUtility;
--behaviorLib.RuneBehavior["Execute"] = behaviorLib.RuneExecute;
--behaviorLib.RuneBehavior["Name"] = "Rune";
--tinsert(behaviorLib.tBehaviors, behaviorLib.RuneBehavior);










if not _G.table.indexOf then
	-- Find the index of the item within this table.
	-- table			The table to search within.
	-- item				The item to look for.
	-- RETURN			Returns the index of the item, or nil if the item couldn't be found.
	function table.indexOf(table, item)
		for key, value in pairs(table) do
			if value == item then
				return key;
			end
		end
		
		return nil;
	end
end
local tindexOf = table.indexOf;

local tSupportHeroes = {
	'Hero_Frosty'
};

function behaviorLib.AttackCreepsUtility(botBrain)	
	local nDenyVal = 23
	local nLastHitVal = 24
	-- When an ally hero is near we must let him last hit instead, except if there is only a support near then all bets are off
	for _, v in pairs(core.localUnits['AllyHeroes']) do
		if not tindexOf(tSupportHeroes, v['object']:GetTypeName()) then
			nLastHitVal = 0;
			break;
		end
	end

	local nUtility = 0

	--we don't want to deny if we are pushing
	local unitDenyTarget = core.unitAllyCreepTarget
	if core.GetCurrentBehaviorName(botBrain) == "Push" then
		unitDenyTarget = nil
	end
	
	local unitTarget = behaviorLib.GetCreepAttackTarget(botBrain, core.unitEnemyCreepTarget, unitDenyTarget)
	
	if unitTarget and core.unitSelf:IsAttackReady() then
		if unitTarget:GetTeam() == core.myTeam then
			nUtility = nDenyVal
		else
			nUtility = nLastHitVal
		end
		core.unitCreepTarget = unitTarget
	end

	if botBrain.bDebugUtility == true and nUtility ~= 0 then
		BotEcho(format("  AttackCreepsUtility: %g (actual)", nUtility))
	end

	return nUtility
end
behaviorLib.AttackCreepsBehavior["Utility"] = behaviorLib.AttackCreepsUtility














-----------------------------------------------------------------------------------------------------------
------------------------------------- Overriding item buying behavior -------------------------------------
--- Default item buying tables don't support buying out as many wards as possible so we override the	---
--- function that selects the next item to buy so that it follows our buying pattern, which is defined 	---
--- as the following:																					---
--- 1. IF the clock has passed 2 minutes AND (we carry 1 ward OR there are 2 wards up) THEN 			---
---		buy red boots (or wait until we can afford boots)												---
--- 2. Buy 2 wards if possible (more may be bought if no other items could be purchased)				---
--- 3. Buy whatever item is defined next in our item buying tables (e.g. behaviorLib.LaneItems[1])		---
-----------------------------------------------------------------------------------------------------------

local function IsBoots(sItemName)
	for _, bootName in ipairs(behaviorLib.BootsList) do
		if sItemName == bootName then
			return true;
		end
	end
	
	return false;
end

-- Override item buying behavior
local oldDetermineNextItemDef = behaviorLib.DetermineNextItemDef;

local nInitialWardsLimit = 2; -- 2, 1, 0
local nMainWardsLimit = 3; -- 0 for none, 1 for whenever needed, 2 for whenever gold is available (after items), 3 for whenever possible (aka all available)

function behaviorLib.DetermineNextItemDef(botBrain)
	-- if we have no boots buy boots
	-- otherwise wards wards wards
	-- finally the old behavior
	
	local nNumWards = 0;
	if core.itemWardOfSight then
		nNumWards = core.itemWardOfSight:GetCharges();
	end
	
	local nNumWardsActive = object.libWarding:GetNumWards();
	
	-- If the match lasted 2 minutes AND we have at least 1 ward in our bags OR there are at least 2 wards up we should really buy boots as the next item
	if HoN.GetMatchTime() > 120000 and (nNumWards >= 1 or nNumWardsActive >= 2) then
		-- We shouldn't buy boots any later
		
		-- Find boots
		local bHaveBoots = false;
		local inventory = core.unitSelf:GetInventory(true);
		for slot = 1, 12 do
			local curItem = inventory[slot];
			
			if curItem and IsBoots(curItem:GetName()) then
				bHaveBoots = true;
				break;
			end
		end
		
		if not bHaveBoots then
			BotEcho('Overriding DetermineNextItemDef: forcing boots purchase.');
			
			-- Remove all marchers from this item list
			for k, v in pairs(behaviorLib.curItemList) do
				local name = behaviorLib.ProcessItemCode(v);
				if name == 'Item_Marchers' then
					tremove(behaviorLib.curItemList, k);
				end
			end
			
			return HoN.GetItemDefinition('Item_Marchers');
		end
	end
	
	local nextItemDef = oldDetermineNextItemDef(botBrain);
	local nGold = botBrain:GetGold();
	local bCanAffordNextItem = nGold >= nextItemDef:GetCost() or nextItemDef:GetName() == 'Item_HomecomingStone';
	
	-- We either already have boots, we lack wards or we're still early into the match, so buy all the wards first
	local itemdefWardOfSight = HoN.GetItemDefinition('Item_FlamingEye');
	local nWardCost = itemdefWardOfSight:GetCost();
	
	if behaviorLib.buyState == behaviorLib.BuyStateStartingItems then
		for i = 1, 4 do
			if nNumWards < nInitialWardsLimit and nGold >= nWardCost then
				core.unitSelf:PurchaseRemaining(itemdefWardOfSight);
				local newGold = botBrain:GetGold();
				if newGold < nGold then -- succes!
					nNumWards = nNumWards + 1;
					nGold = newGold;
				else -- failure :(
					break;
				end
			end
		end
	else
		if nMainWardsLimit == 1 then
			-- Whenever wards are needed
			
			while (nNumWards + nNumWardsActive) < object.libWarding.nMaxWards and nGold >= nWardCost do --TODO: Also consider inventory of allies and courier
				core.unitSelf:PurchaseRemaining(itemdefWardOfSight);
				local newGold = botBrain:GetGold();
				if newGold < nGold then -- succes!
					nNumWards = nNumWards + 1;
					nGold = newGold;
				else -- failure :(
					break;
				end
			end
		elseif nMainWardsLimit == 2 then
			-- Whenever gold is available
			
			if not bCanAffordNextItem then
				-- Can't afford our next item, so spend some gold on wards if possible
				while nGold >= nWardCost do
					core.unitSelf:PurchaseRemaining(itemdefWardOfSight);
					local newGold = botBrain:GetGold();
					if newGold < nGold then -- succes!
						nNumWards = nNumWards + 1;
						nGold = newGold;
					else -- failure :(
						break;
					end
				end
			end
		elseif nMainWardsLimit == 3 then
			-- Whenever possible
			
			while nGold >= nWardCost do
				core.unitSelf:PurchaseRemaining(itemdefWardOfSight);
				local newGold = botBrain:GetGold();
				if newGold < nGold then -- succes!
					nNumWards = nNumWards + 1;
					nGold = newGold;
				else -- failure :(
					break;
				end
			end
		end
	end
	
	if HoN:GetMatchTime() <= 0 then
		-- If we have gold left after buying our items check if we can upgrade the courier
		if not bCanAffordNextItem and nGold > 200 then
			-- if a courier hasn't been identified, locate its reference    
			if not core.courier then
				core.courier = behaviorLib.GetCourier();
			end
		 
			if core.courier and core.courier:GetTypeName() == "Pet_GroundFamiliar" then
				behaviorLib.UpgradeCourier(botBrain, core.courier);
			end
		end
	end
	
	-- Finally if boots and wards aren't an option go with the default buying behavior
	return nextItemDef;
end

	
-- [Code by Naib] (with some modifications)
-- Source: http://forums.heroesofnewerth.com/showthread.php?484724-Behaviour-Support-Courier-upgrade

---------------------------------------------------------------------------
--   Courier upgrade logic
---------------------------------------------------------------------------
-- Util
behaviorLib.nUpgradeUtil = 25 -- nice low util so that it is only executed if nothing else will
function behaviorLib.UpgradeCourierUtility(botBrain)
	return behaviorLib.nUpgradeUtil
end

function behaviorLib.GetCourier()
	local allUnits = HoN.GetUnitsInRadius(Vector3.Create(), 99999, core.UNIT_MASK_ALIVE + core.UNIT_MASK_UNIT) --####
	for id,unit in pairs(allUnits) do
		if unit:GetTypeName() == "Pet_GroundFamiliar" or unit:GetTypeName() == "Pet_FlyngCourier"  then
			if unit:GetTeam() == core.myTeam then  
				if bDebugEchos then BotEcho("Found Monkey") end
				return unit;
			end
		end
	end
	
	return nil;
end
function behaviorLib.UpgradeCourier(botBrain, unitCourier)
    if unitCourier and unitCourier:GetTypeName() == "Pet_GroundFamiliar" then
		if true then BotEcho("Want to upgrade") end
		local abilUpgrade = unitCourier:GetAbility(0);
		if abilUpgrade:CanActivate() then
			return core.OrderAbility(botBrain, abilUpgrade);
		end
    end
	
	return false;
end
-- Execute
function behaviorLib.UpgradeCourierExecute(botBrain)
	local unitSelf = core.unitSelf
	local bActionTaken = false 
	local bDebugEchos = false
 
	if bDebugEchos then BotEcho("CourierCheck") end
 
	-- check if a monkey is upgraded, if it is LOWER the utility to reduce this method being called 
	if core.courier and core.courier:GetTypeName() == "Pet_FlyngCourier" then
		behaviorLib.nUpgradeUtil = 0 
		return false
	end
	
	-- if a courier hasn't been identified, locate its reference    
    if not core.courier then
		core.courier = behaviorLib.GetCourier();
    end
 
	--BotEcho(format("monkey team: %d",core.courier:GetTeam()))
    -- check if you have enough gold AND matchtime is > 3min (arbitary time) then attempt to upgrade
    if core.courier and core.courier:GetTypeName() == "Pet_GroundFamiliar" then
        if botBrain:GetGold() > 200 and (botBrain:GetGoldEarned() > 1400 or botBrain:GetGPM() > 200) then -- hold off upgrading until we are fairly sure we can buy our boots before the 8 minute mark
			bActionTaken = behaviorLib.UpgradeCourier(botBrain, core.courier);
			if bActionTaken then
				behaviorLib.nUpgradeUtil = 0
			end
        end
    end
  
	return bActionTaken 
end

behaviorLib.UpgradeCourierBehavior = {}
behaviorLib.UpgradeCourierBehavior["Utility"] = behaviorLib.UpgradeCourierUtility
behaviorLib.UpgradeCourierBehavior["Execute"] = behaviorLib.UpgradeCourierExecute
behaviorLib.UpgradeCourierBehavior["Name"] = "UpgradeCourier"
tinsert(behaviorLib.tBehaviors, behaviorLib.UpgradeCourierBehavior)

-- [/Code by Naib]



--[[behaviorLib.FountainRetreatBehavior = {}
behaviorLib.FountainRetreatBehavior["Utility"] = function (botBrain)
	return 1000;
end
local bPrepositioned = false;
behaviorLib.FountainRetreatBehavior["Execute"] = function (botBrain)
	if core.myTeam == HoN.GetLegionTeam() then
		local vecPos = core.unitSelf:GetPosition();
		
		local vecFountain = Vector3.Create(1759,1128);
		local pos1 = Vector3.Create(1602,800);
		local pos2 = Vector3.Create(1058,513);
		
		local nDistancePos1 = Vector3.Distance2DSq(pos1, vecPos);
		if bPrepositioned and nDistancePos1 > 1000 * 1000 then
			bPrepositioned = false;
		end
		
		if Vector3.Distance2DSq(vecFountain, vecPos) > 1000 * 1000 then
			BotEcho('Moving to fountain!');
			core.OrderMoveToPosAndHoldClamp(botBrain, core.unitSelf, vecFountain);
			core.DrawXPosition(vecFountain, 'blue')
		elseif not bPrepositioned and nDistancePos1 > 1000 then
			BotEcho('Moving near fountain!');
			botBrain:OrderPosition(core.unitSelf.object or core.unitSelf, "Move", pos1);
			core.DrawXPosition(pos1, 'blue')
		elseif Vector3.Distance2DSq(pos2, vecPos) > 1000 then
			bPrepositioned = true;
			BotEcho('Moving through fountain!');
			botBrain:OrderPosition(core.unitSelf.object or core.unitSelf, "Move", pos2, nil, nil, true);
			core.DrawXPosition(pos2, 'blue')
		else
			core.OrderHoldClamp(botBrain, core.unitSelf);
		end
		
		return true;
	else
		return false;
	end
end
behaviorLib.FountainRetreatBehavior["Name"] = "FountainRetreat"
tinsert(behaviorLib.tBehaviors, behaviorLib.FountainRetreatBehavior)]]

object.killMessages = {};
object.killMessages.General = {
	"If only you had the vision to see it coming...",
	"If a teammate kills you in range of one of one of my wards, do I get an assist?",
	"Oops. Sorry. Didn't mean to killsteal.",
	"Wards? Check. Flying courier? Check. Am I awesome? Check!",
	"Heh. That ward already paid off.",
};
object.killMessages.Players = {
	"Maybe next time you'll consider having me on your team.",
	"My wards predicted I could find you there, {target}.", -- {target} in messages for bots is usually silly
}
object.deathMessages = {};
object.deathMessages.General = {
	"Team! Wards?!",
	"Huh? What? Wards!",
	"Hmmm... I think that might have been a bit too far out...",
	"Kongor warded, top rune warded, enemy forest warded... What did I forget?",
	"Heh. I should have picked a carry.",
	"Hot! Hot! Hot!",
	"So the stories are true...",
};
object.deathMessages.Players = {
	"Zerotorescue warned me about you...", -- "He warned me about you..."?
	"He said to keep as many eyes on you as possible. He was right.",
	"It is uncommon for a human to life up to his reputation...",
	"{target}. I'll remember that name.",
}

local function ProcessKillChatOverride(unitTarget, sTargetPlayerName)
	local nCurrentTime = HoN.GetGameTime()
	if nCurrentTime < core.nNextChatEventTime then
		return
	end
	
	local nChance = random()
	
	if nChance < core.nKillChatChance then
		local nDelay = random(core.nChatDelayMin, core.nChatDelayMax) 
	
		local tChatMessages = (unitTarget and not unitTarget:IsBotControlled() and random() > 0.6) and object.killMessages.Players or object.killMessages.General;
		
		local nRand = random(1, #tChatMessages)
		
		core.AllChat(format(tChatMessages[nRand], sTargetPlayerName), nDelay)
	end
	
	core.nNextChatEventTime = nCurrentTime + core.nChatEventInterval
end
core.ProcessKillChat = ProcessKillChatOverride 

local function ProcessDeathChatOverride(unitSource, sSourcePlayerName)
	local nCurrentTime = HoN.GetGameTime()
	if nCurrentTime < core.nNextChatEventTime then
		return
	end
	
	local nChance = random()
	if nChance < core.nDeathChatChance then
		local nDelay = random(core.nChatDelayMin, core.nChatDelayMax)
		
		local sSourceName = sSourcePlayerName or (unitSource and unitSource:GetDisplayName())
		if sSourceName == nil or sSourceName == "" then
			sSourceName = (unitSource and unitSource:GetTypeName()) or "The Hand of God"
		end
		
		local tChatMessages = (unitSource and not unitSource:IsBotControlled() and random() > 0.6) and object.deathMessages.Players or object.deathMessages.General;
		
		local nRand = random(1, #tChatMessages)
		
		core.AllChat(format(tChatMessages[nRand], sSourceName), nDelay)
	end
	
	core.nNextChatEventTime = nCurrentTime + core.nChatEventInterval
end
core.ProcessDeathChat = ProcessDeathChatOverride

----------------------------------
--	Glacius items
----------------------------------
--[[ list code:
	"# Item" is "get # of these"
	"Item #" is "get this level of the item" --]]
behaviorLib.StartingItems = 
	{ "Item_MinorTotem", "Item_HealthPotion", "Item_RunesOfTheBlight", "Item_CrushingClaws" }
behaviorLib.LaneItems = 
	{ "Item_Marchers", "Item_Striders", "Item_Strength5" } -- Item_Strength5 is Fortified Bracer
behaviorLib.MidItems = 
	{"Item_Astrolabe", "Item_GraveLocket", "Item_SacrificialStone"} --Intelligence7 is Staff of the Master
behaviorLib.LateItems = 
	{"Item_Morph", "Item_BehemothsHeart"} --Morph is Sheepstick. Item_Damage9 is Doombringer



--[[ colors:
	red
	aqua == cyan
	gray
	navy
	teal
	blue
	lime
	black
	brown
	green
	olive
	white
	silver
	purple
	maroon
	yellow
	orange
	fuchsia == magenta
	invisible
--]]

BotEcho('finished loading glacius_main')



--function core.DrawNumber(vecPos, number, height, color)
--	height = height or 100;
--	local width = height / 2;
--	color = color or "yellow";
--	
--	number = tostring(number);
--	
--	if number:len() > 1 then
--		for i = 1, number:len() do
--			local newNumber = number:sub(i, i);
--			
--			DrawNumber(vecPos + Vector3.Create((i - 1) * (width + 20), 0), newNumber, height, color);
--		end
--		return;
--	end
--	
--	if number == "1" then
--		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height), false, color)
--	elseif number == "2" then
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(width, 0), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(0, height / 2), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(width, height / 2), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(width, height/2), vecPos + Vector3.Create(width, height), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
--	elseif number == "3" then
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(width, 0), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(width, height / 2), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height), false, color)
--	elseif number == "4" then
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(0, height / 2), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(width, height / 2), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height), false, color)
--	elseif number == "5" then
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(width, 0), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height / 2), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(width, height / 2), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(0, height), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
--	elseif number == "6" then
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(width, 0), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(0, height), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(width, height / 2), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(width, height / 2), vecPos + Vector3.Create(width, 0), false, color)
--	elseif number == "7" then
--		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
--	elseif number == "8" then
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(0, height), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(width, 0), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(width, height / 2), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
--	elseif number == "9" then
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(width, 0), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(width, height / 2), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(0, height), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
--	elseif number == "0" then
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(0, height), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(width, 0), false, color)
--		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
--	end
--end
--
--local TestBehavior = {};
--behaviorLib.nBehaviorAssessInterval = 1
--TestBehavior.Utility = function ()
--	for k, v in pairs(object.libWarding.tWardSpots) do
--		core.DrawXPosition(v:GetPosition(), 'orange', 200);
--		DrawNumber(v:GetPosition() + Vector3.Create(60,0), v.Identifier, 50);
--	end
--	return 0;
--end;
--TestBehavior.Execute = function () end;
--TestBehavior.Name = "Test"
--tinsert(object.behaviorLib.tBehaviors, TestBehavior)



