local _G = getfenv(0);
local object = _G.object;

local core = object.core;

local tinsert, tsort, min, max, Vector3, Clamp = _G.table.insert, _G.table.sort, _G.math.min, _G.math.max, _G.Vector3, core.Clamp;

runfile "/bots/HeroData.lua";
local HeroData = _G.HoNBots.HeroData;

-- Add our Unit Utilities to the bot's object
object.UnitUtils = object.UnitUtils or {};
-- Easy ref
local utils = object.UnitUtils;

do -- Memory
	utils.Memory = {};
	utils.Memory.tMemory = {};
	
	--[[ function utils.Memory.Store(unit, category, val)
	description:		Store the value in a table specific for the unit and it's category.
	parameters:			unit					(IEntityUnit) The relevant unit.
						category				(String) The category of the data.
						val						(*) The value to store. Can be any type.
	]]
	function utils.Memory.Store(unit, category, val)
		utils.Memory.tMemory[unit] = utils.Memory.tMemory[unit] or {};
		utils.Memory.tMemory[unit][category] = val;
	end
	
	--[[ function utils.Memory.Retrieve(unit, category)
	description:		Retrieve a value from the memory.
	parameters:			unit					(IEntityUnit) The relevant unit.
						category				(String) The category of the data.
	returns:			(*) The value in the category.
	]]
	function utils.Memory.Retrieve(unit, category)
		return utils.Memory.tMemory[unit] and utils.Memory.tMemory[unit][category];
	end
	
	-- Now we set up a metatable with __call for utils.Memory so we can call utils.Memory(unit, category[, val]) to either store or retrieve a value
	local function MemoryStoreAndRetrieve(table, unit, category, val)
		if val then
			table.Store(unit, category, val);
		else
			return table.Retrieve(unit, category);
		end
	end
	local metatable = { __call = MemoryStoreAndRetrieve };
	setmetatable(utils.Memory, metatable);
end

do -- CanSeeUnit
	--[[ function utils.CanSeeUnit(unit)
	description:		Returns whether the unit is visible.
	]]
	function utils.CanSeeUnit(unit)
		return (unit:IsValid() and unit:GetHealth() ~= nil);
	end
end

do -- Position
	utils.vecVeryFarAway = Vector3.Create(20000, 20000);
	--[[ function utils.GetEnemyPosition(unitEnemy)
	description:		Returns the position of the provided unit. If the unit is not visible this returns the previous position instead if he was seen less then 10 seconds ago.
	parameters:			unitEnemy				(IEntityUnit) The unit to get the position for.
	returns:			(Vector3) The current position of the unit, the last known position of the unit or a location far away if the position is unknown.
						(Boolean) Returns whether the data is live or from memory.
	]]
	function utils.GetEnemyPosition(unitEnemy)
		local tPosFromMemory = utils.Memory(unitEnemy, 'Position');
		local nNow = HoN.GetGameTime();
		
		local vecPosition = unitEnemy:GetPosition();
		if vecPosition then
			-- Enemy is visible; store position
			if tPosFromMemory then -- update memory instead of creating a new table
				tPosFromMemory[1] = vecPosition;
				tPosFromMemory[2] = nNow;
			else
				utils.Memory(unitEnemy, 'Position', { vecPosition, nNow });
			end
			
			return vecPosition, true;
		elseif tPosFromMemory ~= nil and (tPosFromMemory[2] + 10000) > nNow then
			-- Enemy is not visible, return previous position
			return tPosFromMemory[1], false;
		else
			return utils.vecVeryFarAway, false;
		end
	end
end

do -- Damage amplifiers
	utils.sGrimoireOfPowerTypeName = 'Item_GrimoireOfPower';
	utils.sElderParasiteStateName = 'State_ElderParasite';
	--[[ function utils.GetDamageMultiplier(inflictor, target)
	description:		Get the general damage amplifier when inflictor attacks target.
	parameters:			inflictor				(IEntityUnit) The attacker.
						target					(IEntityUnit) The target.
	returns:			The damage amplifier that should be used to multiply with the damage. Defaults to 1.
	]]
	function utils.GetDamageMultiplier(inflictor, target)
		local nNow = HoN.GetGameTime(); -- remains the same for the entire duration of a frame
		
		local tInflictorMemory = utils.Memory(inflictor, 'DamageAmplifier');
		
		if tInflictorMemory and tInflictorMemory[target] and tInflictorMemory[target][2] == nNow then
			-- If we already calculated this info earlier this frame we should re-use it
			return tInflictorMemory[target][1];
		end
		
		if utils.CanSeeUnit(target) then
			local nDamageMul = 1;
			
			-- Consider Grimoire of Power on the inflictor
			if utils.GetItem(inflictor, utils.sGrimoireOfPowerTypeName) then
				nDamageMul = nDamageMul * 1.15;
			end
			
			-- Consider Elder Parasite on the target
			if target:HasState(utils.sElderParasiteStateName) then
				nDamageMul = nDamageMul * 1.15;
			end
			
			if tInflictorMemory == nil then
				utils.Memory(inflictor, 'DamageAmplifier', { nDamageMul, nNow });
			elseif tInflictorMemory[target] then
				-- Update without creating a new table
				tInflictorMemory[target][1] = nDamageMul;
				tInflictorMemory[target][2] = nNow;
			else
				tInflictorMemory[target] = { nDamageMul, nNow };
			end
			
			return nDamageMul, true;
		elseif tInflictorMemory[target] then
			return tInflictorMemory[target][1], false;
		else
			return 1, false;
		end
	end
end

do -- DPS
	--[[ function utils.GetDPS(unit)
	description:		Returns the DPS of the provided unit. If the unit is not visible this returns the previous DPS instead.
	parameters:			unit					(IEntityUnit) The unit to get the DPS for.
	returns:			(Number) The damage per second via unmodified auto attacks.
						(Boolean) Returns whether the data is live or from memory.
	]]
	function utils.GetDPS(unit)
		if utils.CanSeeUnit(unit) then
			local nDamage = utils.GetFinalAttackDamageAverage(unit);
			local nAttacksPerSecond = utils.GetAttacksPerSecond(unit);
			local nDPS = nDamage * nAttacksPerSecond;
			
			-- We could consider Savage Mace here (attacks/sec * 35% * 100 physical damage), but would it be useful enough?
			
			utils.Memory(unit, 'DPS', nDPS);
			
			return nDPS, true;
		elseif utils.Memory(unit, 'DPS') then
			return utils.Memory(unit, 'DPS'), false;
		else
			return 0, false;
		end
	end
	
	--[[ function utils.GetFinalAttackDamageAverage(unit)
	description:		Get the final attack damage (total of base, bonus, multipliers, etc.) average of the unit.
	]]
	function utils.GetFinalAttackDamageAverage(unit)
		if utils.CanSeeUnit(unit) then
			local nAverageAttackDamage = (unit:GetFinalAttackDamageMin() + unit:GetFinalAttackDamageMax()) * 0.5;
			
			utils.Memory(unit, 'FinalAttackDamageAverage', nAverageAttackDamage);
			
			return nAverageAttackDamage, true;
		elseif utils.Memory(unit, 'FinalAttackDamageAverage') then
			return utils.Memory(unit, 'FinalAttackDamageAverage'), false;
		else
			return 0, false;
		end
	end
	
	--[[ function utils.GetAttacksPerSecond(unit)
	description:		Get the amount of attacks per second of the unit.
	]]
	function utils.GetAttacksPerSecond(unit)
		if utils.CanSeeUnit(unit) then
			local nAttackCooldown = unit:GetAdjustedAttackCooldown() or 0;
			
			local nAttacksPerSecond = 1 / (nAttackCooldown / 1000);
			
			utils.Memory(unit, 'AttacksPerSecond', nAttacksPerSecond);
			
			return nAttacksPerSecond, true;
		elseif utils.Memory(unit, 'AttacksPerSecond') then
			return utils.Memory(unit, 'AttacksPerSecond'), false;
		else
			return 0, false;
		end
	end
end

do -- Mana
	--[[ function utils.GetMana(unit)
	description:		Returns the mana of the provided unit. If the unit is not visible this returns the previous mana instead.
	parameters:			unit					(IEntityUnit) The unit to get the mana for.
						nManaRegenDuration		(Number) How long mana regeneration is likely to continue before the mana pool becomes relevant. Defaults to 5 seconds.
	returns:			(Number) The amount of mana for the hero, plus 5 seconds of mana regeneration.
						(Boolean) Returns whether the data is live or from memory.
	]]
	function utils.GetMana(unit, nManaRegenDuration)
		local unitMana = unit:GetMana();
		if unitMana ~= nil then -- nil if unit is not visible
			local nMana = unitMana + unit:GetManaRegen() * (nManaRegenDuration or 5);
			
			utils.Memory(unit, 'Mana', nMana);
			
			return nMana, true;
		elseif utils.Memory(unit, 'Mana') then
			-- We could calculate the regenerated mana while a hero wasn't visible, but this sort of accuracy is useless for our usage
			return utils.Memory(unit, 'Mana'), false;
		else
			return 0, false;
		end
	end
end

do -- Mana consumption
	--[[ function utils.GetAbilityManaConsumption(ability)
	description:		Returns the mana consumption of the ability when it is fully utilized.
	parameters:			ability					(IEntityAbility) The ability for which to check the mana consumption.
	returns:			(Number) The max mana consumption of this ability.
	]]
	function utils.GetAbilityManaConsumption(ability)
		-- Using GetMaxCharges instead would mean our bot wouldn't remember if someone used one of the charges, while this might seem fair it would be 
		-- further from a realistic scenario as players DO remember if a charge, such as a Rocket from Chipper or Flurry from Panda, was used
		local nCharges = ability:GetCharges();
		if nCharges and nCharges > 1 then
			return ability:GetManaCost() * nCharges;
		else
			return ability:GetManaCost();
		end
	end

	--[[ function utils.GetTotalManaConsumption(unit)
	description:		Returns the total mana consumption of the unit if he were to use all his abilities.
	parameters:			unit					(IEntityUnit) The unit for which to check the mana consumption.
	returns:			(Number) The max mana consumption of this unit.
	]]
	function utils.GetTotalManaConsumption(unit)
		local nMana = 0;
		for i = 0, 7 do -- 8 is Taunt which doesn't use mana
			if i ~= 4 then -- 4 is Stats which doesn't use mana
				local ability = unit:GetAbility(i);
				
				if ability then
					nMana = nMana + utils.GetAbilityManaConsumption(ability);
				end
			end
		end
		
		return nMana;
	end
end

do -- Magic Resistance
	function utils.GetMagicArmor(unit)
		local nMagicArmor = unit:GetMagicArmor();
		if nMagicArmor ~= nil then -- nil if unit is not visible
			utils.Memory(unit, 'MagicArmor', nMagicArmor);
			
			return nMagicArmor, true;
		elseif utils.Memory(unit, 'MagicArmor') then
			return utils.Memory(unit, 'MagicArmor'), false;
		else
			return 0, false;
		end
	end
	
	function utils.MagicArmorToMagicReduction(magicArmor)
		return 1 - (1 / (1 + magicArmor * .06));
	end
	
	function utils.GetPredictedMagicDamage(inflictor, target, nOriginalDamage)
		local nMagicArmor = utils.GetMagicArmor(target);
		
		-- Consider Spellshards
		local itemSpellShards = utils.GetItem(inflictor, 'Item_SpellShards');
		if itemSpellShards then
			--local nLevel = itemSpellShards:GetLevel(); -- This only works if the item is our own, if the item is owned by another unit this returns nil. Workaround:
			local nLevel = (itemSpellShards:GetValue() == 1187 and 1) or (itemSpellShards:GetValue() == 1587 and 2) or (itemSpellShards:GetValue() == 1987 and 3);
			
			if nLevel == 1 then
				nMagicArmor = max(0, nMagicArmor - 2); -- can't drop below 0
			elseif nLevel == 2 then
				nMagicArmor = max(0, nMagicArmor - 4);
			elseif nLevel == 3 then
				nMagicArmor = max(0, nMagicArmor - 6);
			end
		end
		
		-- No need to consider Harkon's Blade since that is a debuff that automatically lowers the value returned by GetMagicArmor
		
		local nMagicReduction = utils.MagicArmorToMagicReduction(nMagicArmor);
		
		return utils.GetDamageMultiplier(inflictor, target) * (nOriginalDamage * (1 - nMagicReduction));
	end
end

do -- Physical Resistance
	function utils.GetPhysicalResistance(unit)
		local unitResistance = unit:GetPhysicalResistance();
		if unitResistance ~= nil then -- nil if unit is not visible
			utils.Memory(unit, 'PhysicalResistance', unitResistance);
			
			return unitResistance, true;
		elseif utils.Memory(unit, 'PhysicalResistance') then
			return utils.Memory(unit, 'PhysicalResistance'), false;
		else
			return 0, false;
		end
	end

	function utils.GetPredictedPhysicalDamage(inflictor, target, nOriginalDamage)
		local nResistance = utils.GetPhysicalResistance(target);
		
		--TODO: Shieldbreaker's debuff is applied BEFORE the first attack lands, so if inflictor has a SB we should consider that
		-- Source: http://forums.heroesofnewerth.com/showthread.php?391477-Is-Shieldbreaker-applied-on-attack&p=14881968&viewfull=1#post14881968
		
		return utils.GetDamageMultiplier(inflictor, target) * (nOriginalDamage * (1 - nResistance));
	end
end

do -- Health
	utils.nMagicReductionMul = 0.5; -- This should be about equal to the percentage of physical damage our hero does
	utils.nPhysicalReductionMul = 0.5; -- This should be about equal to the percentage of magic damage our hero does
	function utils.GetEffectiveHealthPool(unit, nHealthRegenDuration)
		local unitHealth = unit:GetHealth();
		if unitHealth ~= nil then -- nil if unit is not visible
			-- Get the health pool plus some regen as this fight is likely to last a few seconds
			local nHealth = (unitHealth + unit:GetHealthRegen() * (nHealthRegenDuration or 5));
			
			-- Get the average reduction
			local nMagicReduction = utils.MagicArmorToMagicReduction(utils.GetMagicArmor(unitHero));
			local nPhysicalReduction = utils.GetMagicResistance(unitHero);
			local nTotalReductionMult = 1 + (nMagicReduction * utils.nMagicReductionMul + nPhysicalReduction * utils.nPhysicalReductionMul);
			
			-- Apply the total magic/physical resistance
			nHealth = nHealth * nTotalReductionMult;
			
			-- Remember it
			utils.Memory(unit, 'EffectiveHealthPool', nHealth);
			
			return nHealth, true;
		elseif utils.Memory(unit, 'EffectiveHealthPool') then
			return utils.Memory(unit, 'EffectiveHealthPool'), false;
		else
			return 0, false;
		end
	end

	--[[ function utils.GetHealthPercentage(unit)
	description:		Returns the health percentage of the provided unit. If the unit is not visible this returns the previous health percentage instead.
	parameters:			unit					(IEntityUnit) The unit to get the health percentage for.
						nHealthRegenDuration	(Number) How long health regeneration is likely to continue before the health pool becomes relevant. Defaults to 5 seconds.
	returns:			(Number) The health percentage of the hero, plus 5 seconds of health regeneration.
						(Boolean) Returns whether the data is live or from memory.
	]]
	function utils.GetHealthPercentage(unit, nHealthRegenDuration)
		local unitHealth = unit:GetHealth();
		if unitHealth ~= nil then -- nil if unit is not visible
			local nHealth = (unitHealth + unit:GetHealthRegen() * (nHealthRegenDuration or 5)) / unit:GetMaxHealth();
			
			utils.Memory(unit, 'HealthPercentage', nHealth);
			
			return nHealth, true;
		elseif utils.Memory(unit, 'HealthPercentage') then
			return utils.Memory(unit, 'HealthPercentage'), false;
		else
			return 0, false;
		end
	end
end

do -- Inventory
	--[[ function utils.GetInventory(unit)
	description:		Get the inventory of the provided unit. Does not include stash.
	]]
	function utils.GetInventory(unit)
		local inventory = unit:GetInventory(false)
		
		if inventory then
			utils.Memory(unit, 'Inventory', inventory);
			
			return inventory, true;
		elseif utils.Memory(unit, 'Inventory') then
			return utils.Memory(unit, 'Inventory'), false;
		else
			return nil, false;
		end
	end
	
	function utils.GetItem(unit, sItemTypeName, bIgnoreRecipes)
		local inventory, bUpdated = utils.GetInventory(unit);
		
		if inventory then
			for slot = 1, 6 do
				local item = inventory[slot];
				if item and item:GetTypeName() == sItemTypeName and (not item:IsRecipe() or bIgnoreRecipes == false) then
					return item;
				end
			end
		end
		
		return nil;
	end
	
	--[[ function utils.GetInventoryValue(unit)
	description:		Returns the total inventory value of the unit. If the unit is not visible this returns the previous inventory value instead.
	parameters:			unit					(IEntityUnit) The unit to look into.
	returns:			(Number) The total value of the unit's inventory. --TODO: Does not include consumables.
						(Boolean) Returns whether the data is live or from memory.
	]]
	function utils.GetInventoryValue(unit)
		local nTotalWorth = 1; -- start with a value of 1 gold to avoid dividing by 0
		
		local inventory, bUpdated = utils.GetInventory(unit);
		if bUpdated == true or (inventory ~= nil and utils.Memory(unit, 'InventoryValue') == nil) then
			-- If the inventory has been updated OR (it hasn't been updated and the inventory is NOT nil and we DON'T have a remembered inventory value) then:
			-- GetInventory is likely to be called more often then this function, therefore it may be possible that the unit is not visible and no inventory-value was stored yet but his actual inventory was stored in the past
			for slot = 1, 6 do
				local item = inventory[slot];
				
				if item then
					--TODO: Ignore consumables
					local nValue = item:GetValue();
					if nValue == item:GetTotalCost() then
						nValue = nValue * 0.5; -- this item is still in it's sell-for-full value period, reduce it's value
					end
					
					nTotalWorth = nTotalWorth + nValue;
				end
			end
			
			utils.Memory(unit, 'InventoryValue', nTotalWorth);
			
			return nTotalWorth, true;
		elseif utils.Memory(unit, 'InventoryValue') then
			return utils.Memory(unit, 'InventoryValue'), false;
		else
			return 0, false;
		end
	end
end

do -- GetDangerRadius
	local sqrtTwo = _G.math.sqrt(2);
	
	function utils.GetAttackRange(unit)
		local nAttackRange = unit:GetAttackRange()
		
		if nAttackRange then
			utils.Memory(unit, 'AttackRange', nAttackRange);
			
			return nAttackRange, true;
		elseif utils.Memory(unit, 'AttackRange') then
			return utils.Memory(unit, 'AttackRange'), false;
		else
			return 0, false;
		end
	end
	
	function utils.GetMoveSpeed(unit)
		local nMoveSpeed = unit:GetMoveSpeed()
		
		if nMoveSpeed then
			utils.Memory(unit, 'MoveSpeed', nMoveSpeed);
			
			return nMoveSpeed, true;
		elseif utils.Memory(unit, 'MoveSpeed') then
			return utils.Memory(unit, 'MoveSpeed'), false;
		else
			return 0, false;
		end
	end
	
	utils.sPortalKeyTypeName = 'Item_PortalKey';
	utils.sTabletOfCommandTypeName = 'Item_PushStaff';
	utils.nTabletOfCommandPushDistance = 500;
	function utils.GetDangerRadius(unit)
		if utils.CanSeeUnit(unit) then
			-- Default to 261 units to consider turn rate (at worst 0.5sec to turn 180deg, at a movespeed of 522 (max) that would be 261 units traveled by the target while we were turning)
			local nTravelRange = 261;
			
			-- Consider Portal Key (obtained on heroes with dangerous abilities)
			local itemPortalKey = utils.GetItem(unit, utils.sPortalKeyTypeName);
			if itemPortalKey then
				nTravelRange = nTravelRange + itemPortalKey:GetRange();
			end
			
			-- Consider Tablet of Command
			local itemTabletOfCommand = utils.GetItem(unit, utils.sTabletOfCommandTypeName);
			if itemTabletOfCommand then
				nTravelRange = nTravelRange + utils.nTabletOfCommandPushDistance;
			end
			
			-- Default to auto attack range (don't think this will ever be used over ability range)
			local nAttackRange = utils.GetAttackRange(unit) + unit:GetBoundsRadius() * sqrtTwo;
			
			-- Consider ability ranges for stuns, blinks and hooks/swaps
			local heroData = HeroData:GetHeroData(unit:GetTypeName());
			
			for i = 0, 8 do
				local abilInfo = heroData and heroData:GetAbility(i);
				
				if not heroData or ( -- if here data is unavailable OR
						abilInfo and abilInfo.Threat > 0 and -- ...the ability is worth threat (filters any abilities that are considered useless) AND
						( (abilInfo.CanStun and abilInfo.StunDuration > 999) or -- ...((if the ability can stun AND it lasts long enough to be useful) OR
							abilInfo.CanDispositionHostiles or  -- ...if the ability can disposition hostiles (hook, swap) OR
							abilInfo.CanDispositionSelf ) -- ...if the ability can disposition self (MB/Hag's flash, Chronos' Time Leap, Pharaoh's ult etc.))
					) then
					
					local abil = unit:GetAbility(i);
					local bCanActivate = abil and abil:CanActivate();
					
					if abil and (bCanActivate or bCanActivate == nil) then --TODO: CanActivate currently returns nil for hostile heroes which is why we need to do this secondary check. If it becomes possible to track enemy hero cooldowns then this should be changed.
						local nRange = abil:GetRange();
						if nRange < 2501 then -- A maximum range so that global abilities don't get added (e.g. Benzington ult) and we don't stay too far out.
							if abilInfo and abilInfo.CanDispositionSelf then
								-- If this is a blink then consider it as travel range
								if nRange > nTravelRange then
									nTravelRange = nRange;
								end
							else
								-- Otherwise consider it as attack range
								if nRange > nAttackRange then
									nAttackRange = nRange;
								end
							end
						end
					end
				end
			end
			
			local nTotalRange = nTravelRange + nAttackRange;
			
			utils.Memory(unit, 'DangerRadius', nTotalRange);
			
			return nTotalRange;
		elseif utils.Memory(unit, 'DangerRadius') then
			return utils.Memory(unit, 'DangerRadius'), false;
		else
			return 0, false;
		end
	end
end

do -- GetThreat
	utils.nBaseThreat = 2 -- Base threat. Level differences and distance alter the actual threat level.
	utils.nFullHealthPoolThreat = 3;--TODO: Determine optimal value
	utils.nCanUseSkillsThreat = 3;--TODO: Determine optimal value
	utils.nMaxLevelDifferenceThreat = 6 -- The max threat for level difference (negative OR positive)
	function utils.GetThreat(unitSelf, target, bDebug)
		-- If the target is dead his threat is 0
		if not target or not target:IsAlive() then
			return 0;
		end
		
		-- Make sure our units aren't wrapped in tables
		unitSelf = unitSelf.object or unitSelf;
		target = target.object or target;
		
		-- If we're checking myself we can skip some calculations
		local bIsSelf = (unitSelf == target);
		
		-- Get the enemy position and if it is "VeryFarAway" the skip calculating everything else
		local vecTargetPosition = utils.GetEnemyPosition(target);
		if vecTargetPosition == utils.vecVeryFarAway then return 0; end
		
		-- Get the dangerous radius around the hero.
		local nDangerRadius = utils.GetDangerRadius(target);
		--Dump(target:GetTypeName() .. ': ' .. nDangerRadius);
		-- Multiply the difference in movement speed by 400 and add that to the danger radius. This considers the target's overtaking speed. Add 0 units if the target's movement speed is equal to or lower then unitSelf's speed.
		nDangerRadius = nDangerRadius + 400 * (max(1, utils.GetMoveSpeed(target) / unitSelf:GetMoveSpeed()) - 1);
		
		local nDangerRadiusSq = nDangerRadius * nDangerRadius;
		
		-- Ignore the target if he is out of range
		local nDistanceSq;
		if not bIsSelf then
			nDistanceSq = Vector3.Distance2DSq(unitSelf:GetPosition(), vecTargetPosition);
			if nDistanceSq > max(4000000, nDangerRadiusSq) then -- 4000000 = 2000 units
				-- Ignore units further then (2000 and nDangerRadiusSq) units away
				return 0;
			end
		end
		
		local nTargetMana = utils.GetMana(target);
		
		local heroData = HeroData:GetHeroData(target:GetTypeName());
		
		-- Get the base threat for this hero
		local nThreat = heroData and heroData.Threat or 2;
		
		if bDebug then
			print(unitSelf:GetDisplayName() .. ': Threat for ^y' .. target:GetTypeName() .. '^*: ^y' .. nThreat .. '^*');
		end
		
		-- Get the threat for each abilitiy
		for i = 0, 8 do
			local abilInfo;
			if heroData then
				abilInfo = heroData:GetAbility(i);
			elseif i == 0 or i == 1 or i == 2 or i == 3 then
				abilInfo = { Threat = 1 };
			end
			
			if abilInfo and abilInfo.Threat > 0 then
				local abil = target:GetAbility(i);
				local bCanActivate = abil and abil:CanActivate(); -- returns nil for hostile units
				local bHaveMana = abil and (nTargetMana >= abil:GetManaCost());
				
				if bCanActivate or (bCanActivate == nil and bHaveMana) then --TODO: If it becomes possible to track enemy hero cooldowns then this should be changed.
					nThreat = nThreat + abilInfo.Threat;
					
					if bDebug then
						print(',+abil' .. i .. ': ^y' .. string.format("%.2f", nThreat) .. '^*');
					end
				end
			end
		end
		
		do -- Consider HP (0 - 3)
			nThreat = nThreat + utils.nFullHealthPoolThreat * Clamp((utils.GetHealthPercentage(target) - 0.1) / 0.9, 0, 1);
			
			if bDebug then
				print(',+health (' .. string.format("%.2f", utils.GetHealthPercentage(target)) .. '): ^y' .. string.format("%.2f", nThreat) .. '^*');
			end
		end
		
		do -- Consider mana (0 - 3)
			local nEnemyManaConsumption = utils.GetTotalManaConsumption(target);
			nThreat = nThreat + utils.nCanUseSkillsThreat * min(1, (nTargetMana / nEnemyManaConsumption));
			
			if bDebug then
				--BotEcho(target:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after enemy mana (' .. string.format("%.2f", (nTargetMana / nEnemyManaConsumption)) .. ')');
				print(',+mana (' .. string.format("%.2f", (nTargetMana / nEnemyManaConsumption)) .. '): ^y' .. string.format("%.2f", nThreat) .. '^*');
			end
		end
		
		if not bIsSelf then
			do -- Consider levels (-4 - 4)
				local nMyLevel = unitSelf:GetLevel();
				local nEnemyLevel = target:GetLevel();
				
				nThreat = nThreat + Clamp(nEnemyLevel - nMyLevel, -utils.nMaxLevelDifferenceThreat, utils.nMaxLevelDifferenceThreat);
				
				if bDebug then
					--BotEcho(target:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after levels (' .. nEnemyLevel .. 'vs' .. nMyLevel .. ')');
					print(',+levels (' .. nEnemyLevel .. 'vs' .. nMyLevel .. '): ^y' .. string.format("%.2f", nThreat) .. '^*');
				end
			end
			
			do -- Consider attack DPS differences (-4 - 4)
				local nDPSThreatMultiplier = utils.GetDPS(target) / utils.GetDPS(unitSelf); -- fall back to my own DPS if the target's DPS couldn't be calculated
				
				if nDPSThreatMultiplier > 1 then
					nThreat = nThreat + Clamp((nDPSThreatMultiplier - 1) * 1.5, 0, 4); -- enemy has more DPS
				else
					nThreat = nThreat - Clamp((1 / nDPSThreatMultiplier - 1) * 1.5, 0, 4); -- I have more DPS
				end
				
				if bDebug then
					--BotEcho(target:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after DPS multiplier (' .. string.format("%.2f", utils.GetDPS(target)) .. 'vs' .. string.format("%.2f", utils.GetDPS(unitSelf)) .. ')');
					print(',+DPS multiplier (' .. string.format("%.2f", nDPSThreatMultiplier) .. '): ^y' .. string.format("%.2f", nThreat) .. '^*');
				end
			end
			
			do -- Consider items (-4 - 4)
				local nInventoryValueMult = utils.GetInventoryValue(target) / utils.GetInventoryValue(unitSelf);
				
				if nInventoryValueMult > 1 then
					nThreat = nThreat + Clamp((nInventoryValueMult - 1) * 2, 0, 4); -- enemy has more items
				else
					nThreat = nThreat - Clamp((1 / nInventoryValueMult - 1) * 2, 0, 4); -- I have more items
				end
				
				if bDebug then
					--BotEcho(target:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after inventory value (' .. string.format("%.2f", nInventoryValueMult) .. ')');
					print(',+inventory value (' .. string.format("%.2f", nInventoryValueMult) .. '): ^y' .. string.format("%.2f", nThreat) .. '^*');
				end
			end
			
			do -- Consider range
				-- Graph for this formula: https://www.google.com/search?q=1+%2B+1+*+%28902%5E2+-+x%5E2%29+%2F+902%5E2 - where 902 is the nDangerRadiusSq
				nThreat = nThreat * Clamp(1 + 1 * (nDangerRadiusSq - nDistanceSq) / nDangerRadiusSq, 0.5, 2); -- within Dangerradius is 1-2, outside it is 0.5-1
				
				if bDebug then
					--BotEcho(target:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after distance');
					print(',+distance (' .. string.format("%.2f", math.sqrt(nDistanceSq)) .. 'vs' .. string.format("%.2f", math.sqrt(nDangerRadiusSq)) .. '): ^y' .. string.format("%.2f", nThreat) .. '^*\n');
				end
			end
		else
			nThreat = nThreat * 1;
			
			if bDebug then
				--BotEcho(target:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after distance');
				print(',+self: ^y' .. string.format("%.2f", nThreat) .. '^*\n');
			end
		end
		
		return nThreat;
	end
end

do -- GetEnemyTeam
	-- Table look up is faster then if-elseif statements
	utils.tEnemyTeams = {
		[HoN.GetLegionTeam()] = HoN.GetHellbourneTeam(),
		[HoN.GetHellbourneTeam()] = HoN.GetLegionTeam()
	};
	function utils.GetEnemyTeam(unit)
		return utils.tEnemyTeams[unit:GetTeam()];
	end
end

do -- IsMagicImmune
	function utils.IsMagicImmune(unit)
		return unit:IsInvulnerable() or
			unit:HasState('State_Item3E') or -- Shrunken Head
			unit:HasState('State_Jereziah_Ability2') or -- Jeraziah's Protective Charm
			unit:HasState('State_Predator_Ability2'); -- Predator's Stone Hide
	end
	function utils.HasNullStoneEffect(unit)
		-- Null Store
		local item = utils.GetItem(unit, 'Item_Protect');
		
		if item and item:GetRemainingCooldownTime() <= 0 then
			return true;
		end
		
		return --unit:HasState('State_NullStone_Active') or --TODO: Null Stone can't be detected right now by bots, make API request
			unit:HasState('State_Moraxus_Ability2_Buff'); -- Moraxus' Arcane Shield
	end
end

do
	function utils.IsPorting(unit)
		return unit:HasState('State_Boots_Source') or
			unit:HasState('State_HomecomingStone_Source_Short') or
			unit:HasState('State_HomecomingStone_Source_Med') or
			unit:HasState('State_HomecomingStone_Source_Long');
	end
end

do
	-- ShouldX functions are suggestive. They may be ignored. Do note that even though their names are similar, they may all return completely different types and values. Don't presume they share the same input and output.
	-- In addition to ShouldX functions, several of these have an additional MayHaveToX function that you can use to see if the ability may be cast at a later time. This can help when deciding items, or saving special abilities.
	
	-- This should be known before anything is happening, so check if enemy has any abilities with this property
	function utils.ShouldSpread(unit)
		local tAbilities = HeroData:GetAllAbilities(utils.GetEnemyTeam(unit), 'ShouldSpread');
		
		if #tAbilities > 0 then
			return tAbilities;
		end
		
		return false;
	end
	
	-- May be used to decide if we want to save an ability that can interrupt to prevent an offensive ability from being cast, or to buy an item like a Tablet of Command
	-- You should probably have an additional checks to make sure the unit(s) with this ability aren't visible far away on the map
	function utils.MayHaveToInterrupt(unit)
		local tAbilities = HeroData:GetAllAbilities(utils.GetEnemyTeam(unit), 'ShouldInterrupt');
		
		if #tAbilities > 0 then
			return tAbilities;
		end
		
		return false;
	end
	-- May be used to decide if and who we should interrupt
	function utils.ShouldInterrupt(unitSelf, bIncludePorts)
		local enemyTeam = utils.GetEnemyTeam(unitSelf);
		local tAbilities = HeroData:GetAllAbilities(enemyTeam, 'ShouldInterrupt');
		
		local nAbilities = #tAbilities;
		if nAbilities == 0 then
			return false;
		end
		
		-- Go through all enemy heroes
		local tInterruptTargets;
		for _, unitEnemy in pairs(HoN.GetHeroes(enemyTeam)) do
			if unitEnemy:IsChanneling() and Vector3.Distance2DSq(unitSelf:GetPosition(), unitEnemy:GetPosition()) < 6250000 then -- 6250000 = 2500 units
				local bIsPorting = bIncludePorts and utils.IsPorting(unitEnemy);
				
				if bIsPorting then
					-- If the unit is porting
					tInterruptTargets = tInterruptTargets or {}; -- we only create the table here since 99% of the time doing this outside the loop would be 100% overhead
					tinsert(tInterruptTargets, unitEnemy);
				elseif not bIsPorting then
					-- Go through all abilities that should be interrupted
					for i = 1, nAbilities do
						local abilInfo = tAbilities[i];
						
						if abilInfo:IsFrom(unitEnemy) then
							-- This ability is from this hero!
							
							local abil = unitEnemy:GetAbility(abilInfo:GetSlot());
							
							-- Check if the ability is being cast. GetIsChanneling currently returns true is the hero is casting ANYTHING. It does NOT check if the ability is being channeled.
							if abil:GetIsChanneling() and (not abilInfo.ChannelingState or unitEnemy:HasState(abilInfo.ChannelingState)) then
								tInterruptTargets = tInterruptTargets or {}; -- we only create the table here since 99% of the time doing this outside the loop would be 100% overhead
								tinsert(tInterruptTargets, unitEnemy);
							end
						end
					end
				end
			end
		end
		
		if tInterruptTargets then
			local vecMyPosition = unitSelf:GetPosition();
			-- If we have multiple interrupt targets then get the closest unit
			tsort(tInterruptTargets, function (a, b) return Vector3.Distance2DSq(a:GetPosition(), vecMyPosition) < Vector3.Distance2DSq(b:GetPosition(), vecMyPosition); end);
			
			return tInterruptTargets[1];
		end
		
		return false;
	end
	
	-- May be used to decide if we want to buy a Geometers/Shrunken Head or not
	function utils.MayHaveToBreakFree(unit)
		local tAbilities = HeroData:GetAllAbilities(utils.GetEnemyTeam(unit), 'ShouldBreakFree');
		
		if #tAbilities > 0 then
			return tAbilities;
		end
		
		return false;
	end
	-- May be used to decide if we want to use our Geometers/Shrunken/Other item or Ability. Do note you probably want additional checks to see if enemies are nearby and a teamfight is starting or has started
	function utils.ShouldBreakFree(unit)
		local tAbilities = HeroData:GetAllAbilities(utils.GetEnemyTeam(unit), 'ShouldBreakFree');
		
		for i = 1, #tAbilities do
			if unit:HasState(tAbilities[i].Debuff) then
				return tAbilities[i];
			end
		end
		
		return false;
	end
	
	-- May be used to decide if we want to buy an additional teleport stone or not, and whether we want to teleport out to farm or save the cooldown for escaping
	function utils.MayHaveToPort(unit)
		local tAbilities = HeroData:GetAllAbilities(utils.GetEnemyTeam(unit), 'ShouldPort');
		
		if #tAbilities > 0 then
			return tAbilities;
		end
		
		return false;
	end
	-- May be used to decide if we want to immediately port back to base
	function utils.ShouldPort(unit)
		local tAbilities = HeroData:GetAllAbilities(utils.GetEnemyTeam(unit), 'ShouldPort');
		
		for i = 1, #tAbilities do
			if unit:HasState(tAbilities[i].Debuff) then
				return tAbilities[i];
			end
		end
		
		return false;
	end
	
	-- May be used to decide if we want to buy a Void Talisman or a Astrolabe or a Barrier Idol or something like those items
	function utils.MayHaveToAvoidDamage(unit)
		local tAbilities = HeroData:GetAllAbilities(utils.GetEnemyTeam(unit), 'ShouldAvoidDamage');
		
		if #tAbilities > 0 then
			return tAbilities;
		end
		
		return false;
	end
	-- May be used to increase damage threat and fear
	function utils.ShouldAvoidDamage(unit)
		local tAbilities = HeroData:GetAllAbilities(utils.GetEnemyTeam(unit), 'ShouldAvoidDamage');
		
		for i = 1, #tAbilities do
			if unit:HasState(tAbilities[i].Debuff) then
				return tAbilities[i];
			end
		end
		
		return false;
	end

end

do -- HasInvis
	--[[ function utils.HasInvis(nTeamId)
	description:		Check if anyone in the provided team has an ability to turn himself or someone else invisible. Does not include items nor take into account cooldowns.
	parameters:			nTeamId				(Number) The team identifier.
	returns:			(Boolean) True if anyone in the team has an invis ability, false if not.
	]]
	function utils.HasInvis(nTeamId)
		for k, unit in pairs(HoN.GetHeroes(nTeamId)) do
			local hero = HeroData:GetHeroData(unit:GetTypeName());
			
			if hero and hero:Has('TurnInvisible') then
				return true;
			end
		end
		
		return false;
	end
end
