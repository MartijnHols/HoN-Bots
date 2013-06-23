local _G = getfenv(0);
local object = _G.object;

object.behaviorLib = object.behaviorLib or {};

local core, eventsLib, behaviorLib, metadata = object.core, object.eventsLib, object.behaviorLib, object.metadata;

local print, ipairs, pairs, string, table, next, type, tinsert, tremove, tsort, format, tostring, tonumber, strfind, strsub
	= _G.print, _G.ipairs, _G.pairs, _G.string, _G.table, _G.next, _G.type, _G.table.insert, _G.table.remove, _G.table.sort, _G.string.format, _G.tostring, _G.tonumber, _G.string.find, _G.string.sub
local ceil, floor, pi, tan, atan, atan2, abs, cos, sin, acos, min, max, random
	= _G.math.ceil, _G.math.floor, _G.math.pi, _G.math.tan, _G.math.atan, _G.math.atan2, _G.math.abs, _G.math.cos, _G.math.sin, _G.math.acos, _G.math.min, _G.math.max, _G.math.random

local BotEcho, VerboseLog, Clamp, skills = core.BotEcho, core.VerboseLog, core.Clamp, object.skills

runfile "/bots/Libraries/LibHeroData/LibHeroData.lua";
local LibHeroData = _G.HoNBots.LibHeroData;

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
	--local heroInfo = LibHeroData:GetHeroData(core.unitSelf:GetTypeName());
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
	local utility = 0;
	self.lastInterruptTarget = UnitUtils.ShouldInterrupt(core.unitSelf, self.bIncludePorts);

	if self.lastInterruptTarget then
		utility = 80;
	end
	
	if botBrain.bDebugUtility == true and utility ~= 0 then
		BotEcho(format("  InterruptBehavior: %g", utility))
	end
	
	return utility;
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
		local heroInfoSelf = LibHeroData:GetHeroData(unitSelf:GetTypeName());
		
		if heroInfoSelf then
			for slot = 0, 8 do
				local abilInfo = heroInfoSelf:GetAbility(slot);
				
				if abilInfo and ((not bIsMagicImmune and abilInfo.CanInterrupt) or (bIsMagicImmune and abilInfo.CanInterruptMagicImmune)) then
					local abil = unitSelf:GetAbility(slot);
					
					if abil:CanActivate() then
						local sTargetType = abilInfo.TargetType;
						
						if sTargetType == 'Passive' then
							-- Passive effect, so the interrupt probably triggers on auto attack (e.g. Flint's Hollowpoint Shells)
							
							self:OrderAutoAttack(botBrain, unitSelf, unitTarget);
						elseif sTargetType == 'Self' then
							-- No target needed, stuff happens around our hero (e.g. Keeper's Root)
							
							self:OrderAbilitySelf(botBrain, abil, unitSelf, unitTarget);
						elseif sTargetType == 'AutoCast' then
							-- Autocast effect, cast it on the target
							
							self:OrderAbilityTargetUnit(botBrain, abil, unitSelf, unitTarget);
						elseif sTargetType == 'TargetUnit' then
							-- Unit targetable
							
							self:OrderAbilityTargetUnit(botBrain, abil, unitSelf, unitTarget);
						elseif sTargetType == 'TargetPosition' then
							-- Ground targetable
							
							self:OrderAbilityTargetPosition(botBrain, abil, unitSelf, unitTarget);
						elseif sTargetType == 'TargetVector' then --TODO: Test me
							-- Ground targetable in a direction (e.g. Zephyr's Gust)
							
							--self:OrderAbilityTargetPosition(botBrain, abil, unitSelf, unitTarget);
						elseif sTargetType == 'VectorEntity' then
							-- Vector entity, so this launches a hero(?) at the target (e.g. Rally can compell allies and himself, while Grinex can stun target heroes)
							-- This has much more complex mechanics then most other abilities, so if a hero has an ability like this it may be better to implement a funcInterrupt and disable the bAutoUseAbilities
							
							-- Transform the VectorEntityTarget into a table if needed
							local tVectorEntityTargets = abilInfo.VectorEntityTarget;
							if type(tVectorEntityTargets) == 'string' then
								tVectorEntityTargets = { tVectorEntityTargets };
							end
							
							local unitOrigin;
							local vecDirection;
							
							if abilInfo.CanDispositionHostiles then
								-- If this dispositions a hostile it is sure to interrupt whatever unit we disposition.
								
								unitOrigin = unitTarget;
								
								-- Get all potential targets
								local tPotentialDirections = {};
								for i = 1, #tVectorEntityTargets do
									local sPotentialTarget = tVectorEntityTargets[i];
									
									if sPotentialTarget == 'Hero' then
										-- We could filter allied heroes and hostile heroes here too, but by doing that we risk moving a hero outside of an allied heroes range. We should just keep it like this, nice and simple.
										local tHeroes = HoN.GetUnitsInRadius(unitOrigin:GetPosition(), abil:GetTargetRadius(), core.UNIT_MASK_ALIVE + core.UNIT_MASK_HERO);
										
										tPotentialDirections[sPotentialTarget] = tPotentialDirections[sPotentialTarget] or {};
										for k, v in pairs(tHeroes) do
											if v:GetUniqueID() ~= unitSelf:GetUniqueID() and v:GetUniqueID() ~= unitTarget:GetUniqueID() then
												tinsert(tPotentialDirections[sPotentialTarget], v:GetPosition());
												core.DrawXPosition(v:GetPosition(), 'yellow');
											end
										end
									elseif sPotentialTarget == 'Cliff' then
										--local tCliffs = HoN.GetUnitsInRadius(unitOrigin:GetPosition(), abil:GetTargetRadius(), core.UNIT_MASK_ALIVE + core.UNIT_MASK_BUILDING);
										--TODO: Implement cliffs once it is possible
									elseif sPotentialTarget == 'Tree' then
										local tTrees = HoN.GetTreesInRadius(unitOrigin:GetPosition(), abil:GetTargetRadius());
										
										tPotentialDirections[sPotentialTarget] = tPotentialDirections[sPotentialTarget] or {};
										for k, v in pairs(tTrees) do
											tinsert(tPotentialDirections[sPotentialTarget], v:GetPosition());
											core.DrawXPosition(v:GetPosition(), 'yellow');
										end
									elseif sPotentialTarget == 'Building' then
										local tBuildings = HoN.GetUnitsInRadius(unitOrigin:GetPosition(), abil:GetTargetRadius(), core.UNIT_MASK_ALIVE + core.UNIT_MASK_BUILDING);
										
										tPotentialDirections[sPotentialTarget] = tPotentialDirections[sPotentialTarget] or {};
										for k, v in pairs(tBuildings) do
											tinsert(tPotentialDirections[sPotentialTarget], v:GetPosition());
											core.DrawXPosition(v:GetPosition(), 'yellow');
										end
									end
								end
								
								-- Get the optimal target, heroes before cliffs before buildings before trees. This is since it's very likely that when another hero is hit we'll hurt both (e.g. Grinex's stun will stun before heroes).
								if tPotentialDirections['Hero'] and tPotentialDirections['Hero'][1] then -- this is first since for Grinex this causes both heroes to be stunned
									vecDirection = tPotentialDirections['Hero'][1];
								elseif tPotentialDirections['Cliff'] and tPotentialDirections['Cliff'][1] then -- this is second since for Grinex it causes a longer duration
									vecDirection = tPotentialDirections['Cliff'][1];
								elseif tPotentialDirections['Building'] and tPotentialDirections['Building'][1] then -- this is third since buildings are probably stronger then trees
									vecDirection = tPotentialDirections['Building'][1];
								elseif tPotentialDirections['Tree'] and tPotentialDirections['Tree'][1] then
									vecDirection = tPotentialDirections['Tree'][1];
								else
									vecDirection = core.allyWell and core.allyWell:GetPosition() or Vector3.Create(1, 0); -- fall back
								end
							elseif abilInfo.CanDispositionSelf or abilInfo.CanDispositionFriendlies then
								-- If this dispositions a self or a friendly then search for the nearest friendly hero
								
								-- Find the closest friendly hero to the target within push range
								local tHeroes = HoN.GetUnitsInRadius(unitTarget:GetPosition(), abil:GetTargetRadius(), core.UNIT_MASK_ALIVE + core.UNIT_MASK_HERO);
								
								local unitClosest;
								for k, v in pairs(tHeroes) do
									if not v:IsChanneling() then -- we wouldn't want to interrupt something important
										if (abilInfo.CanDispositionSelf and v:GetUniqueID() == unitSelf:GetUniqueID()) or (abilInfo.CanDispositionFriendlies and v:GetUniqueID() ~= unitSelf:GetUniqueID()) then
											if not unitClosest or Vector3.Distance2DSq(unitClosest:GetPosition(), unitSelf:GetPosition()) > Vector3.Distance2DSq(v:GetPosition(), unitSelf:GetPosition()) then
												-- Find whichever unit is closest to me AND within radius of the target, this will reduce travel time
												unitClosest = v;
											end
										end
									end
								end
								
								unitOrigin = unitClosest;
								vecDirection = unitTarget:GetPosition();
							end
							
							self:OrderAbilityVectorEntity(botBrain, abil, unitSelf, unitTarget, unitOrigin, vecDirection);
						else
							error(abilInfo:GetHeroInfo():GetTypeName() .. ': Unknown ability type set up in the AbilityInfo for ' .. abilInfo:GetTypeName() .. '.');
						end
						bActionTaken = true;
						break;
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

local sqrtTwo = _G.math.sqrt(2);

--[[ function behavior:OrderMove(botBrain, unit, unitTarget)
description:		Order the unit to move to the unit target.
]]
function behavior:OrderMove(botBrain, unit, unitTarget)
	--core.OrderMoveToPosClamp(botBrain, unit, unitTarget:GetPosition()); -- this vs OrderMoveToUnitClamp, what's the difference?
	core.OrderMoveToUnitClamp(botBrain, unit, unitTarget);
end
--[[ function behavior:OrderAutoAttack(botBrain, unit, unitTarget)
description:		Order the unit to start auto attacking the target or move in range to do so.
]]
function behavior:OrderAutoAttack(botBrain, unit, unitTarget)
	local nDistanceSq = Vector3.Distance2DSq(unit:GetPosition(), unitTarget:GetPosition());
	
	local nAttackRange = UnitUtils.GetAttackRange(unit) + unit:GetBoundsRadius() * sqrtTwo + unitTarget:GetBoundsRadius() * sqrtTwo;
	
	if nDistanceSq > (nAttackRange * nAttackRange) then
		-- Move closer
		
		self:OrderMove(botBrain, unit, unitTarget);
		
		if self.bDebug then
			BotEcho('OrderAutoAttack: Moving closer to interrupt.');
		end
	else
		-- We can start attacking the hero
		
		core.OrderAttackClamp(botBrain, unit, unitTarget);
		
		if self.bDebug then
			BotEcho('OrderAutoAttack: In range to start attacking the hero.');
		end
	end
end
--[[ function behavior:OrderAbilitySelf(botBrain, abil, unit, unitTarget)
description:		Order the unit to cast the ability within range of the target or move in range to do so.
]]
function behavior:OrderAbilitySelf(botBrain, abil, unit, unitTarget)
	local nDistanceSq = Vector3.Distance2DSq(unit:GetPosition(), unitTarget:GetPosition());
	
	local nRangeSq = (abil:GetRange() + abil:GetTargetRadius() - 5) ^ 2; -- 5 units buffer
	
	if nRangeSq < 10000 then
		-- If the range is less then 100 units then it's too small to use.
		
		BotEcho('OrderAbilitySelf: Range is too low for ' .. abil:GetTypeName() .. ' to be useful.');
		
		return false;
	end
	
	if nDistanceSq > nRangeSq then
		-- Move closer
		
		self:OrderMove(botBrain, unit, unitTarget);
		
		if self.bDebug then
			BotEcho('OrderAbilitySelf: Moving closer to interrupt.');
		end
	else
		-- We can cast the ability on top of the hero
		
		core.OrderAbility(botBrain, abil);
		
		if self.bDebug then
			BotEcho('OrderAbilitySelf: In range to cast on top of hero.');
		end
	end
end
--[[ function behavior:OrderAbilityTargetUnit(botBrain, abil, unit, unitTarget)
description:		Order the unit to cast the ability on the target or move in range to do so.
]]
function behavior:OrderAbilityTargetUnit(botBrain, abil, unit, unitTarget)
	local nDistanceSq = Vector3.Distance2DSq(unit:GetPosition(), unitTarget:GetPosition());
	
	local nRangeSq = (abil:GetRange() - 5) ^ 2; -- 5 units buffer
	
	if nDistanceSq > nRangeSq then
		-- Move closer
		
		self:OrderMove(botBrain, unit, unitTarget);
		
		if self.bDebug then
			BotEcho('OrderAbilityTargetUnit: Moving closer to interrupt.');
		end
	else
		-- Cast on target
		
		core.OrderAbilityEntity(botBrain, abil, unitTarget);
		
		if self.bDebug then
			BotEcho('OrderAbilityTargetUnit: In range to cast on top of hero.');
		end
	end
end
--[[ function behavior:OrderAbilityTargetPosition(botBrain, abil, unit, unitTarget)
description:		Order the unit to cast the ability in radius of the target or move in range to do so.
]]
function behavior:OrderAbilityTargetPosition(botBrain, abil, unit, unitTarget)
	local nDistanceSq = Vector3.Distance2DSq(unit:GetPosition(), unitTarget:GetPosition());
	
	local nRangeSq = (abil:GetRange() + abil:GetTargetRadius() - 5) ^ 2; -- 5 units buffer
	
	if nDistanceSq > nRangeSq then
		-- Move closer
		
		self:OrderMove(botBrain, unit, unitTarget);
		
		if self.bDebug then
			BotEcho('OrderAbilityTargetPosition: Moving closer to interrupt.');
		end
	else
		if nDistanceSq <= abil:GetRange() then
			-- We can cast the ability on top of the hero
			
			core.OrderAbilityPosition(botBrain, abil, unitTarget:GetPosition());
			
			if self.bDebug then
				BotEcho('OrderAbilityTargetPosition: In range to cast on top of hero.');
			end
		else
			-- We can cast the ability near the hero while he is inside it's radius
			
			local vecTowardsTargetPos, nDistance = Vector3.Normalize(unit:GetPosition() - unitTarget:GetPosition());
			
			core.OrderAbilityPosition(botBrain, abil, unitTarget:GetPosition() + vecTowardsTargetPos * (nDistance - abil:GetRange()));
			
			if self.bDebug then
				BotEcho('OrderAbilityTargetPosition: Out of range to cast on top of hero, casting within radius.');
				core.DrawXPosition(unitTarget:GetPosition() + vecTowardsTargetPos * (nDistance - abil:GetRange()), 'red');
				core.DrawXPosition(unitTarget:GetPosition(), 'green');
			end
		end
	end
end
--[[ function behavior:OrderAbilityVectorEntity(botBrain, abil, unit, unitTarget)
description:		Order the unit to cast the ability so it affects the target or move in range to do so.
]]
function behavior:OrderAbilityVectorEntity(botBrain, abil, unit, unitTarget, unitOrigin, vecDirection)
	local nDistanceSq = unitOrigin and Vector3.Distance2DSq(unit:GetPosition(), unitOrigin:GetPosition());
	
	local nRangeSq = (abil:GetRange() - 5) ^ 2; -- 5 units buffer
	
	if not unitOrigin or not vecDirection or nDistanceSq > nRangeSq then
		self:OrderMove(botBrain, unit, unitTarget);
		
		if self.bDebug then
			BotEcho('OrderAbilityVectorEntity: Moving closer to interrupt.');
			core.DrawXPosition(vecDirection, 'green');
		end
	else
		core.OrderAbilityEntityVector(botBrain, abil, unitOrigin, vecDirection - unitOrigin:GetPosition());
		
		if self.bDebug then
			BotEcho('OrderAbilityVectorEntity: In range to interrupt.');
			core.DrawDebugArrow(unitOrigin:GetPosition(), vecDirection, 'red');
		end
	end
end
