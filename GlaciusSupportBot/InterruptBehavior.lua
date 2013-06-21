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

runfile "/bots/UnitUtils.lua";
local UnitUtils = object.UnitUtils;

runfile "/bots/Classes/Behavior.class.lua"; --TODO: turn into require when development for this class is finished

local classes = _G.HoNBots.Classes;

local behavior = classes.Behavior.Create('Interrupt');

-- This also makes the reference: behaviorLib.Behaviors.InterruptBehavior
behavior:AddToLegacyBehaviorRunner(behaviorLib);

-- Settings

behavior.bDebug = true;
-- Whether teleports should also be interrupted
behavior.bIncludePorts = true;
-- Whether items should automatically be used
behavior.bAutoUseItems = true;
-- Whether abilities should automatically be used
behavior.bAutoUseAbilities = true;
-- The function to call when we need to interrupt someone
behavior.funcInterrupt = nil;

-- "Private" stuff

behavior.lastInterruptTarget = nil;

function behavior:Utility(botBrain)
	self.lastInterruptTarget = UnitUtils.ShouldInterrupt(core.unitSelf, self.bIncludePorts);
	if self.lastInterruptTarget then
		return 80;
	end
	
	return 0;
end

function behavior:Execute(botBrain)
	local unitSelf = core.unitSelf;
	local unitTarget = self.lastInterruptTarget;
	if not unitTarget then return true; end
	Dump(unitTarget:GetTypeName())
	
	local bIsMagicImmune = UnitUtils.IsMagicImmune(unitTarget);
	local bHasNullStoneEffect = UnitUtils.HasNullStoneEffect(unitTarget);
	
	local bActionTaken = false;
	if not bActionTaken and self.bAutoUseItems then
		
		-- GetItem(tablet), GetItem(Stormspirit), GetItem(Kuldra's Sheepstick), GetItem(Hellflower)
	end
	
	if not bActionTaken and self.bAutoUseAbilities then
		local heroInfoSelf = HeroData:GetHeroData(unitSelf:GetTypeName());
		
		if heroInfoSelf then
			for slot = 0, 8 do
				local abilInfo = heroInfoSelf:GetAbility(slot);
				
				if abilInfo and ((not bIsMagicImmune and abilInfo.CanInterrupt) or (bIsMagicImmune and abilInfo.CanInterruptMagicImmune)) then
					local abil = unitSelf:GetAbility(slot);
					
					if abil:CanActivate() then
						local sTargetType = abilInfo.TargetType;
						local nDistanceSq = Vector3.Distance2DSq(unitSelf:GetPosition(), unitTarget:GetPosition());
						
						if sTargetType == 'Passive' then --TODO: Test me
							--TODO: Auto attack
						elseif sTargetType == 'Self' then --TODO: Test me
							-- No target needed, stuff happens around our hero
							
							local nRangeSq = (abil:GetRange() + abil:GetTargetRadius() - 5) ^ 2; -- 5 units buffer
							
							if nDistanceSq > nRangeSq then
								-- Move closer
								BotEcho('Moving closer to interrupt (Self).');
								core.OrderMoveToPosClamp(botBrain, unitSelf, unitTarget:GetPosition());
							else
								if nDistanceSq <= abil:GetRange() then
									-- We can cast the ability on top of the hero
									BotEcho('In range to cast on top of hero (Self).');
									core.OrderAbilityPosition(botBrain, abil, unitTarget:GetPosition());
								else
									-- We can cast the ability near the hero while he is inside it's radius
									local vecTowardsTargetPos, nDistance = Vector3.Normalize(unitSelf:GetPosition() - unitTarget:GetPosition());
									
									core.OrderAbilityPosition(botBrain, abil, unitTarget:GetPosition() + vecTowardsTargetPos * (nDistance - abil:GetRange()));
									
									-- Debug
									BotEcho('Out of range to cast on top of hero, casting within radius (TargetPosition).');
									core.DrawXPosition(unitTarget:GetPosition() + vecTowardsTargetPos * (nDistance - abil:GetRange()), 'red');
									core.DrawXPosition(unitTarget:GetPosition(), 'green');
								end
							end
						elseif sTargetType == 'AutoCast' then --TODO: Test me
							--TODO: Auto attack
						elseif sTargetType == 'TargetUnit' then
							-- Unit targetable
							
							local nRangeSq = (abil:GetRange() - 5) ^ 2; -- 5 units buffer
							
							if nDistanceSq > nRangeSq then
								-- Move closer
								BotEcho('Moving closer to interrupt (TargetUnit).');
								core.OrderMoveToPosClamp(botBrain, unitSelf, unitTarget:GetPosition());
							else
								BotEcho('In range to cast on top of hero (TargetUnit).');
								core.OrderAbilityEntity(botBrain, abil, unitTarget);
							end
						elseif sTargetType == 'TargetPosition' then
							-- Ground targetable
							
							local nRangeSq = (abil:GetRange() + abil:GetTargetRadius() - 5) ^ 2; -- 5 units buffer
							
							if nDistanceSq > nRangeSq then
								-- Move closer
								BotEcho('Moving closer to interrupt (TargetPosition).');
								core.OrderMoveToPosClamp(botBrain, unitSelf, unitTarget:GetPosition());
							else
								if nDistanceSq <= abil:GetRange() then
									-- We can cast the ability on top of the hero
									BotEcho('In range to cast on top of hero (TargetPosition).');
									core.OrderAbilityPosition(botBrain, abil, unitTarget:GetPosition());
								else
									-- We can cast the ability near the hero while he is inside it's radius
									local vecTowardsTargetPos, nDistance = Vector3.Normalize(unitSelf:GetPosition() - unitTarget:GetPosition());
									
									core.OrderAbilityPosition(botBrain, abil, unitTarget:GetPosition() + vecTowardsTargetPos * (nDistance - abil:GetRange()));
									
									-- Debug
									BotEcho('Out of range to cast on top of hero, casting within radius (TargetPosition).');
									core.DrawXPosition(unitTarget:GetPosition() + vecTowardsTargetPos * (nDistance - abil:GetRange()), 'red');
									core.DrawXPosition(unitTarget:GetPosition(), 'green');
								end
							end
							break;
						elseif sTargetType == 'VectorEntity' then --TODO: Test me
							
						else
							error(abilInfo:GetHeroInfo():GetTypeName() .. ': ' .. abilInfo:GetTypeName() .. ': Unknown ability type set up in it\'s AbilityInfo.');
						end
						bActionTaken = true;
					end
				end
			end
		end
	end
	
	if not bActionTaken and self.funcInterrupt then
		return self.funcInterrupt(unitTarget);
	end
	bActionTaken = true;
	return bActionTaken;
end
