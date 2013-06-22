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

-- Whether teleports should also be interrupted
behavior.bIncludePorts = true;
-- Whether items should automatically be used
behavior.bAutoUseItems = true;
-- Whether abilities should automatically be used
behavior.bAutoUseAbilities = true;
-- The function to call when we need to interrupt someone
behavior.funcInterrupt = nil;

-- "Private" stuff
behavior.bDebug = true;
behavior.lastInterruptTarget = nil;
behavior.bInitialized = false;

function behavior:Initialize()
	self.bInitialized = true;
	
	-- Should we recheck this every minute? We may buy an interrupt item which should re-enable the behavior
	--local heroInfo = HeroData:GetHeroData(core.unitSelf:GetTypeName());
	--if heroInfo and not heroInfo:Has('Interrupt') then
	--	-- If we don't have an interrupt ability, disable the behavior
	--	self:Disable();
	--
	--	if self.bDebug then
	--		BotEcho('InterruptBehavior: Disabling behavior because our hero can\'t interrupt.');
	--	end
	--end
end

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
	
	if self.bDebug then
		BotEcho('InterruptBehavior: Targetting ' .. unitTarget:GetTypeName() .. ' for an interrupt.');
	end
	
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
						
						if sTargetType == 'Passive' then --TODO: Test me
							-- Passive effect, so the interrupt probably triggers on auto attack (e.g. Flint's Hollowpoint Shells)
							
							self:OrderAutoAttack(botBrain, unitSelf, unitTarget);
						elseif sTargetType == 'Self' then --TODO: Test me
							-- No target needed, stuff happens around our hero (e.g. Keeper's Root)
							
							self:OrderAbilitySelf(botBrain, abil, unitSelf, unitTarget);
						elseif sTargetType == 'AutoCast' then --TODO: Test me
							-- Autocast effect, cast it on the target
							
							self:OrderAbilityTargetUnit(botBrain, abil, unitSelf, unitTarget);
						elseif sTargetType == 'TargetUnit' then
							-- Unit targetable
							
							self:OrderAbilityTargetUnit(botBrain, abil, unitSelf, unitTarget);
						elseif sTargetType == 'TargetPosition' then
							-- Ground targetable
							
							self:OrderAbilityTargetPosition(botBrain, abil, unitSelf, unitTarget);
						elseif sTargetType == 'VectorEntity' then --TODO: Test me
							-- Vector entity, so this launches a hero(?) at the target (e.g. Rally can compell allies and himself, Grinex can stun targets)
							-- This has much more complex mechanics then most other abilities, so if a hero has an ability like this it may be better to implement a funcInterrupt and disable the bAutoUseAbilities
							
							self:OrderAbilityVectorEntity(botBrain, abil, unitSelf, unitTarget);
						else
							error(abilInfo:GetHeroInfo():GetTypeName() .. ': Unknown ability type set up in the AbilityInfo for ' .. abilInfo:GetTypeName() .. '.');
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
	
	return bActionTaken;
end

function behavior:OrderAutoAttack(botBrain, unitSelf, unitTarget)
	local nDistanceSq = Vector3.Distance2DSq(unitSelf:GetPosition(), unitTarget:GetPosition());
	
	error('OrderAutoAttack: Not yet implemented.');
end
function behavior:OrderAbilitySelf(botBrain, abil, unitSelf, unitTarget)
	local nDistanceSq = Vector3.Distance2DSq(unitSelf:GetPosition(), unitTarget:GetPosition());
	
	local nRangeSq = (abil:GetRange() + abil:GetTargetRadius() - 5) ^ 2; -- 5 units buffer
	
	if nDistanceSq > nRangeSq then
		-- Move closer
		
		core.OrderMoveToPosClamp(botBrain, unitSelf, unitTarget:GetPosition());
		
		if self.bDebug then
			BotEcho('InterruptBehavior: Moving closer to interrupt (Self).');
		end
	else
		-- We can cast the ability on top of the hero
		
		core.OrderAbility(botBrain, abil);
		
		if self.bDebug then
			BotEcho('InterruptBehavior: In range to cast on top of hero (Self).');
		end
	end
end
function behavior:OrderAbilityTargetUnit(botBrain, abil, unitSelf, unitTarget)
	local nDistanceSq = Vector3.Distance2DSq(unitSelf:GetPosition(), unitTarget:GetPosition());
	
	local nRangeSq = (abil:GetRange() - 5) ^ 2; -- 5 units buffer
	
	if nDistanceSq > nRangeSq then
		-- Move closer
		
		core.OrderMoveToPosClamp(botBrain, unitSelf, unitTarget:GetPosition());
		
		if self.bDebug then
			BotEcho('InterruptBehavior: Moving closer to interrupt (TargetUnit).');
		end
	else
		-- Cast on target
		
		core.OrderAbilityEntity(botBrain, abil, unitTarget);
		
		if self.bDebug then
			BotEcho('InterruptBehavior: In range to cast on top of hero (TargetUnit).');
		end
	end
end
function behavior:OrderAbilityTargetPosition(botBrain, abil, unitSelf, unitTarget)
	local nDistanceSq = Vector3.Distance2DSq(unitSelf:GetPosition(), unitTarget:GetPosition());
	
	local nRangeSq = (abil:GetRange() + abil:GetTargetRadius() - 5) ^ 2; -- 5 units buffer
	
	if nDistanceSq > nRangeSq then
		-- Move closer
		
		core.OrderMoveToPosClamp(botBrain, unitSelf, unitTarget:GetPosition());
		
		if self.bDebug then
			BotEcho('InterruptBehavior: Moving closer to interrupt (TargetPosition).');
		end
	else
		if nDistanceSq <= abil:GetRange() then
			-- We can cast the ability on top of the hero
			
			core.OrderAbilityPosition(botBrain, abil, unitTarget:GetPosition());
			
			if self.bDebug then
				BotEcho('InterruptBehavior: In range to cast on top of hero (TargetPosition).');
			end
		else
			-- We can cast the ability near the hero while he is inside it's radius
			
			local vecTowardsTargetPos, nDistance = Vector3.Normalize(unitSelf:GetPosition() - unitTarget:GetPosition());
			
			core.OrderAbilityPosition(botBrain, abil, unitTarget:GetPosition() + vecTowardsTargetPos * (nDistance - abil:GetRange()));
			
			if self.bDebug then
				BotEcho('InterruptBehavior: Out of range to cast on top of hero, casting within radius (TargetPosition).');
				core.DrawXPosition(unitTarget:GetPosition() + vecTowardsTargetPos * (nDistance - abil:GetRange()), 'red');
				core.DrawXPosition(unitTarget:GetPosition(), 'green');
			end
		end
	end
end
function behavior:OrderAbilityVectorEntity(botBrain, abil, unitSelf, unitTarget)
	local nDistanceSq = Vector3.Distance2DSq(unitSelf:GetPosition(), unitTarget:GetPosition());
	
	error('OrderAbilityVectorEntity: Not yet implemented.');
end
