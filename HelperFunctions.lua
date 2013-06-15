local _G = getfenv(0);
local object = _G.object;

local min, max, Vector3 = _G.math.min, _G.math.max, _G.Vector3;

object.HelperFunctions = object.HelperFunctions or {};

local mod = object.HelperFunctions;

do -- Memory
	mod.Memory = {};
	mod.Memory.tMemory = {};
	
	--[[ function mod.Memory.Store(unit, category, val)
	description:		Store the value in a table specific for the unit and it's category.
	parameters:			unit					(IEntityUnit) The relevant unit.
						category				(String) The category of the data.
						val						(*) The value to store. Can be any type.
	]]
	function mod.Memory.Store(unit, category, val)
		mod.Memory.tMemory[unit] = mod.Memory.tMemory[unit] or {};
		mod.Memory.tMemory[unit][category] = val;
	end
	
	--[[ function mod.Memory.Retrieve(unit, category)
	description:		Retrieve a value from the memory.
	parameters:			unit					(IEntityUnit) The relevant unit.
						category				(String) The category of the data.
	returns:			(*) The value in the category.
	]]
	function mod.Memory.Retrieve(unit, category)
		return mod.Memory.tMemory[unit] and mod.Memory.tMemory[unit][category];
	end
	
	-- Now we set up a metatable with __call for mod.Memory so we can call mod.Memory(unit, category[, val]) to either store or retrieve a value
	local function MemoryStoreAndRetrieve(table, unit, category, val)
		if val then
			table.Store(unit, category, val);
		else
			table.Retrieve(unit, category);
		end
	end
	local metatable = { __call = MemoryStoreAndRetrieve };
	setmetatable(mod.Memory, metatable);
end

do -- CanSeeUnit
	--[[ function mod.CanSeeUnit(unit)
	description:		Returns whether the unit is visible.
	]]
	function mod.CanSeeUnit(unit)
		return (unit:GetHealth() ~= nil);
	end
end

do -- Position
	mod.vecVeryFarAway = Vector3.Create(20000, 20000);
	mod.tEnemyPositions = {};
	--[[ function mod.GetEnemyPosition(unitEnemy)
	description:		Returns the position of the provided unit. If the unit is not visible this returns the previous position instead if he was seen less then 10 seconds ago.
	parameters:			unitEnemy				(IEntityUnit) The unit to get the position for.
	returns:			(Vector3) The current position of the unit, the last known position of the unit or a location far away if the position is unknown.
						(Boolean) Returns whether the data is live or from memory.
	]]
	function mod.GetEnemyPosition(unitEnemy)
		local tPosFromMemory = mod.Memory(unitEnemy, 'Position');
		local nNow = HoN.GetGameTime();
		
		local vecPosition = unitEnemy:GetPosition();
		if vecPosition then
			-- Enemy is visible; store position
			if tPosFromMemory then -- update memory instead of creating a new table
				tPosFromMemory[1] = vecPosition;
				tPosFromMemory[2] = nNow;
			else
				mod.Memory(unitEnemy, 'Position', { vecPosition, nNow });
			end
			
			return vecPosition, true;
		elseif tPosFromMemory ~= nil and (tPosFromMemory[2] + 10000) > nNow then
			-- Enemy is not visible, return previous position
			return tPosFromMemory[1], false;
		else
			return mod.vecVeryFarAway, false;
		end
	end
end

do -- Damage amplifiers
	mod.sGrimoireOfPowerTypeName = 'Item_GrimoireOfPower';
	--[[ function mod.GetDamageAmplifiers(inflictor, target)
	description:		Get the general damage amplifier when inflictor attacks target.
	parameters:			inflictor				(IEntityUnit) The attacker.
						target					(IEntityUnit) The target.
	returns:			The damage amplifier that should be used to multiply with the damage. Defaults to 1.
	]]
	function mod.GetDamageAmplifiers(inflictor, target)
		local nNow = HoN.GetGameTime(); -- remains the same for the entire duration of a frame
		
		local tInflictorMemory = mod.Memory(inflictor, 'DamageAmplifier');
		
		if tInflictorMemory and tInflictorMemory[target] and tInflictorMemory[target][2] == nNow then
			-- If we already calculated this info earlier this frame we should re-use it
			return tInflictorMemory[target][1];
		end
		
		if mod.CanSeeUnit(target) then
			local nDamageMul = 1;
			
			-- Consider Grimoire of Power on the inflictor
			if mod.GetItem(inflictor, mod.sGrimoireOfPowerTypeName) then
				nDamageMul = nDamageMul * 1.15;
			end
			
			-- Consider Elder Parasite on the target
			if target:HasState('State_ElderParasite') then
				nDamageMul = nDamageMul * 1.15;
			end
			
			if tInflictorMemory == nil then
				mod.Memory(inflictor, 'DamageAmplifier', { nDamageMul, nNow });
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
	--[[ function mod.GetDPS(unit)
	description:		Returns the DPS of the provided unit. If the unit is not visible this returns the previous DPS instead.
	parameters:			unit					(IEntityUnit) The unit to get the DPS for.
	returns:			(Number) The damage per second via unmodified auto attacks.
						(Boolean) Returns whether the data is live or from memory.
	]]
	function mod.GetDPS(unit)
		if mod.CanSeeUnit(unit) then
			local nDamage = mod.GetFinalAttackDamageAverage(unit);
			local nAttacksPerSecond = mod.GetAttacksPerSecond(unit);
			local nDPS = nDamage * nAttacksPerSecond;
			
			-- We could consider Savage Mace here (attacks/sec * 35% * 100 physical damage), but would it be useful enough?
			
			mod.Memory(unit, 'DPS', nDPS);
			
			return nDPS, true;
		elseif mod.Memory(unit, 'DPS') then
			return mod.Memory(unit, 'DPS'), false;
		else
			return 0, false;
		end
	end
	
	--[[ function mod.GetFinalAttackDamageAverage(unit)
	description:		Get the final attack damage (total of base, bonus, multipliers, etc.) average of the unit.
	]]
	function mod.GetFinalAttackDamageAverage(unit)
		if mod.CanSeeUnit(unit) then
			local nAverageAttackDamage = (unit:GetFinalAttackDamageMin() + unit:GetFinalAttackDamageMax()) * 0.5;
			
			mod.Memory(unit, 'FinalAttackDamageAverage', nAverageAttackDamage);
			
			return nAverageAttackDamage, true;
		elseif mod.Memory(unit, 'FinalAttackDamageAverage') then
			return mod.Memory(unit, 'FinalAttackDamageAverage'), false;
		else
			return 0, false;
		end
	end
	
	--[[ function mod.GetAttacksPerSecond(unit)
	description:		Get the amount of attacks per second of the unit.
	]]
	function mod.GetAttacksPerSecond(unit)
		if mod.CanSeeUnit(unit) then
			local nAttackCooldown = unit:GetAdjustedAttackCooldown() or 0;
			
			local nAttacksPerSecond = 1 / (nAttackCooldown / 1000);
			
			mod.Memory(unit, 'AttacksPerSecond', nAttacksPerSecond);
			
			return nAttacksPerSecond, true;
		elseif mod.Memory(unit, 'AttacksPerSecond') then
			return mod.Memory(unit, 'AttacksPerSecond'), false;
		else
			return 0, false;
		end
	end
end

do -- Mana
	--[[ function mod.GetMana(unit)
	description:		Returns the mana of the provided unit. If the unit is not visible this returns the previous mana instead.
	parameters:			unit					(IEntityUnit) The unit to get the mana for.
						nManaRegenDuration		(Number) How long mana regeneration is likely to continue before the mana pool becomes relevant. Defaults to 5 seconds.
	returns:			(Number) The amount of mana for the hero, plus 5 seconds of mana regeneration.
						(Boolean) Returns whether the data is live or from memory.
	]]
	function mod.GetMana(unit, nManaRegenDuration)
		local unitMana = unit:GetMana();
		if unitMana ~= nil then -- nil if unit is not visible
			local nMana = unitMana + unit:GetManaRegen() * (nManaRegenDuration or 5);
			
			mod.Memory(unit, 'Mana', nMana);
			
			return nMana, true;
		elseif mod.Memory(unit, 'Mana') then
			-- We could calculate the regenerated mana while a hero wasn't visible, but this sort of accuracy is useless for our usage
			return mod.Memory(unit, 'Mana'), false;
		else
			return 0, false;
		end
	end
end

do -- Mana consumption
	--[[ function mod.GetAbilityManaConsumption(ability)
	description:		Returns the mana consumption of the ability when it is fully utilized.
	parameters:			ability					(IEntityAbility) The ability for which to check the mana consumption.
	returns:			(Number) The max mana consumption of this ability.
	]]
	function mod.GetAbilityManaConsumption(ability)
		-- Using GetMaxCharges instead would mean our bot wouldn't remember if someone used one of the charges, while this might seem fair it would be 
		-- further from a realistic scenario as players DO remember if a charge, such as a Rocket from Chipper or Flurry from Panda, was used
		local nCharges = ability:GetCharges();
		if nCharges and nCharges > 1 then
			return ability:GetManaCost() * nCharges;
		else
			return ability:GetManaCost();
		end
	end

	--[[ function mod.GetTotalManaConsumption(unit)
	description:		Returns the total mana consumption of the unit if he were to use all his abilities.
	parameters:			unit					(IEntityUnit) The unit for which to check the mana consumption.
	returns:			(Number) The max mana consumption of this unit.
	]]
	function mod.GetTotalManaConsumption(unit)
		local nMana = 0;
		for i = 0, 7 do -- 8 is Taunt which doesn't use mana
			if i ~= 4 then -- 4 is Stats which doesn't use mana
				local ability = unit:GetAbility(i);
				
				if ability then
					nMana = nMana + mod.GetAbilityManaConsumption(ability);
				end
			end
		end
		
		return nMana;
	end
end

do -- Magic Resistance
	function mod.GetMagicArmor(unit)
		local nMagicArmor = unit:GetMagicArmor();
		if nMagicArmor ~= nil then -- nil if unit is not visible
			mod.Memory(unit, 'MagicArmor', nMagicArmor);
			
			return nMagicArmor, true;
		elseif mod.Memory(unit, 'MagicArmor') then
			return mod.Memory(unit, 'MagicArmor'), false;
		else
			return 0, false;
		end
	end
	
	function mod.MagicArmorToMagicReduction(magicArmor)
		return 1 - (1 / (1 + magicArmor * .06));
	end
	
	function mod.GetPredictedMagicDamage(inflictor, target, nOriginalDamage)
		local nMagicArmor = mod.GetMagicArmor(target);
		
		-- Consider Spellshards
		local itemSpellShards = mod.GetItem(inflictor, 'Item_SpellShards');
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
		
		local nMagicReduction = mod.MagicArmorToMagicReduction(nMagicArmor);
		
		return mod.GetDamageAmplifiers(inflictor, target) * (nOriginalDamage * (1 - nMagicReduction));
	end
end

do -- Physical Resistance
	function mod.GetPhysicalResistance(unit)
		local unitResistance = unit:GetPhysicalResistance();
		if unitResistance ~= nil then -- nil if unit is not visible
			mod.Memory(unit, 'PhysicalResistance', unitResistance);
			
			return unitResistance, true;
		elseif mod.Memory(unit, 'PhysicalResistance') then
			return mod.Memory(unit, 'PhysicalResistance'), false;
		else
			return 0, false;
		end
	end

	function mod.GetPredictedPhysicalDamage(inflictor, target, nOriginalDamage)
		local nResistance = mod.GetPhysicalResistance(target);
		
		--TODO: Shieldbreaker's debuff is applied BEFORE the first attack lands, so if inflictor has a SB we should consider that
		-- Source: http://forums.heroesofnewerth.com/showthread.php?391477-Is-Shieldbreaker-applied-on-attack&p=14881968&viewfull=1#post14881968
		
		return mod.GetDamageAmplifiers(inflictor, target) * (nOriginalDamage * (1 - nResistance));
	end
end

do -- Health
	mod.nMagicReductionMul = 0.5; -- This should be about equal to the percentage of physical damage our hero does
	mod.nPhysicalRdeuctionMud = 0.5; -- This should be about equal to the percentage of magic damage our hero does
	function mod.GetEffectiveHealthPool(unit, nHealthRegenDuration)
		local unitHealth = unit:GetHealth();
		if unitHealth ~= nil then -- nil if unit is not visible
			-- Get the health pool plus some regen as this fight is likely to last a few seconds
			local nHealth = (unitHealth + unit:GetHealthRegen() * (nHealthRegenDuration or 5));
			
			-- Get the average reduction
			local nMagicReduction = mod.MagicArmorToMagicReduction(mod.GetMagicArmor(unitHero));
			local nPhysicalReduction = mod.GetMagicResistance(unitHero);
			local nTotalReductionMult = 1 + (nMagicReduction * mod.nMagicReductionMul + nPhysicalReduction * mod.nPhysicalRdeuctionMud);
			
			-- Apply the total magic/physical resistance
			nHealth = nHealth * nTotalReductionMult;
			
			-- Remember it
			mod.Memory(unit, 'EffectiveHealthPool', nHealth);
			
			return nHealth, true;
		elseif mod.Memory(unit, 'EffectiveHealthPool') then
			return mod.Memory(unit, 'EffectiveHealthPool'), false;
		else
			return 0, false;
		end
	end

	--[[ function mod.GetHealthPercentage(unit)
	description:		Returns the health percentage of the provided unit. If the unit is not visible this returns the previous health percentage instead.
	parameters:			unit					(IEntityUnit) The unit to get the health percentage for.
						nHealthRegenDuration	(Number) How long health regeneration is likely to continue before the health pool becomes relevant. Defaults to 5 seconds.
	returns:			(Number) The health percentage of the hero, plus 5 seconds of health regeneration.
						(Boolean) Returns whether the data is live or from memory.
	]]
	function mod.GetHealthPercentage(unit, nHealthRegenDuration)
		local unitHealth = unit:GetHealth();
		if unitHealth ~= nil then -- nil if unit is not visible
			local nHealth = (unitHealth + unit:GetHealthRegen() * (nHealthRegenDuration or 5)) / unit:GetMaxHealth();
			
			mod.Memory(unit, 'HealthPercentage', nHealth);
			
			return nHealth, true;
		elseif mod.Memory(unit, 'HealthPercentage') then
			return mod.Memory(unit, 'HealthPercentage'), false;
		else
			return 0, false;
		end
	end
end

do -- Inventory
	--[[ function mod.GetInventory(unit)
	description:		Get the inventory of the provided unit. Does not include stash.
	]]
	function mod.GetInventory(unit)
		local inventory = unit:GetInventory(false)
		
		if inventory then
			mod.Memory(unit, 'Inventory', inventory);
			
			return inventory, true;
		elseif mod.Memory(unit, 'Inventory') then
			return mod.Memory(unit, 'Inventory'), false;
		else
			return nil, false;
		end
	end
	
	function mod.GetItem(unit, sItemTypeName, bIgnoreRecipes)
		local inventory, bUpdated = mod.GetInventory(unit);
		
		if inventory then
			for slot = 1, 6 do
				local item = inventory[slot];
				if item and item:GetTypeName() == sItemTypeName and (not item:IsRecipe() or bIgnoreRecipes == false) then
					return item;
				end
			end
		end
		
		return false;
	end
	
	--[[ function mod.GetInventoryValue(unit)
	description:		Returns the total inventory value of the unit. If the unit is not visible this returns the previous inventory value instead.
	parameters:			unit					(IEntityUnit) The unit to look into.
	returns:			(Number) The total value of the unit's inventory. --TODO: Does not include consumables.
						(Boolean) Returns whether the data is live or from memory.
	]]
	function mod.GetInventoryValue(unit)
		local nTotalWorth = 1; -- start with a value of 1 gold to avoid dividing by 0
		
		local inventory, bUpdated = mod.GetInventory(unit);
		if bUpdated == true or (inventory ~= nil and mod.Memory(unit, 'InventoryValue') == nil) then
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
			
			mod.Memory(unit, 'InventoryValue', nTotalWorth);
			
			return nTotalWorth, true;
		elseif mod.Memory(unit, 'InventoryValue') then
			return mod.Memory(unit, 'InventoryValue'), false;
		else
			return 0, false;
		end
	end
end
