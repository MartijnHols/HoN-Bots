local _G = getfenv(0);
local object = _G.object;

local core = object.core;

local min, max, Vector3, Clamp = _G.math.min, _G.math.max, _G.Vector3, core.Clamp;

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
			table.Retrieve(unit, category);
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
		return (unit:GetHealth() ~= nil);
	end
end

do -- Position
	utils.vecVeryFarAway = Vector3.Create(20000, 20000);
	utils.tEnemyPositions = {};
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
			if target:HasState('State_ElderParasite') then
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
	utils.nPhysicalRdeuctionMud = 0.5; -- This should be about equal to the percentage of magic damage our hero does
	function utils.GetEffectiveHealthPool(unit, nHealthRegenDuration)
		local unitHealth = unit:GetHealth();
		if unitHealth ~= nil then -- nil if unit is not visible
			-- Get the health pool plus some regen as this fight is likely to last a few seconds
			local nHealth = (unitHealth + unit:GetHealthRegen() * (nHealthRegenDuration or 5));
			
			-- Get the average reduction
			local nMagicReduction = utils.MagicArmorToMagicReduction(utils.GetMagicArmor(unitHero));
			local nPhysicalReduction = utils.GetMagicResistance(unitHero);
			local nTotalReductionMult = 1 + (nMagicReduction * utils.nMagicReductionMul + nPhysicalReduction * utils.nPhysicalRdeuctionMud);
			
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
		
		return false;
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
	
	utils.sPortalKeyTypeName = 'Item_PortalKey';
	utils.sTabletOfCommandTypeName = 'Item_PushStaff';
	function utils.GetDangerRadius(unit)
		-- Default to auto attack range
		local nRange = unit:GetAttackRange() + unit:GetBoundsRadius() * sqrtTwo;
		
		-- Consider Portal Key (obtained on heroes with dangerous abilities)
		local itemPortalKey = utils.GetItem(unit, utils.sPortalKeyTypeName);
		if itemPortalKey and itemPortalKey:GetRange() > nRange then
			nRange = itemPortalKey:GetRange();
		end
		
		-- Consider Tablet of Command (don't add it to PK range if we have both, the range would become too high then and it is fairly difficult to follow a PK up with a tablet and then stunning without being disabled yourself first)
		local itemTabletOfCommand = utils.GetItem(unit, utils.sTabletOfCommandTypeName);
		if itemTabletOfCommand and itemTabletOfCommand:GetRange() > nRange then
			nRange = itemTabletOfCommand:GetRange();
		end
		
		-- Consider ability ranges for stuns, blinks and hooks/swaps
		local heroData = HeroData:GetHeroData(unit:GetTypeName());
		if heroData then
			for i = 0, 8 do
				local abilInfo = heroData:GetAbility(i);
				
				if abilInfo and abilInfo.Threat > 0 and -- if the ability is worth threat (filters any abilities that are considered useless)
					((abilInfo.CanStun and abilInfo.StunDuration > 999) or -- if the ability can stun AND it lasts long enough to be useful
					(abilInfo.CanDispositionHostiles) or  -- if the ability can disposition hostiles (hook, swap)
					(abilInfo.CanDispositionSelf)) then -- if the ability can disposition self (MB/Hag's flash, Chronos' Time Leap, Pharaoh's ult etc.)
					
					local abil = unit:GetAbility(i);
					local bCanActivate = abil and abil:CanActivate();
					
					if bCanActivate or bCanActivate == nil then --TODO: CanActivate currently returns nil for hostile heroes which is why we need to do this secondary check. If it becomes possible to track enemy hero cooldowns then this should be changed.
						local nAbilRange = abil:GetRange();
						if nAbilRange < 2501 then -- A maximum range so that global abilities don't get added (e.g. Benzington ult) and we don't stay too far out.
							nRange = nRange + nAbilRange;
						end
					end
				end
			end
		end
		
		return nRange;
	end
end

do -- GetThreat
	utils.bEnemyThreatDebug = false;
	utils.nBaseThreat = 2 -- Base threat. Level differences and distance alter the actual threat level.
	utils.nFullHealthPoolThreat = 3;--TODO: Determine optimal value
	utils.nCanUseSkillsThreat = 3;--TODO: Determine optimal value
	utils.nMaxLevelDifferenceThreat = 6 -- The max threat for level difference (negative OR positive)
	function utils.GetThreat(unitSelf, target)
		-- If the target is dead his threat is 0
		if not target or not target:IsAlive() then
			return 0;
		end
		
		-- Make sure our units aren't wrapped in tables
		unitSelf = unitSelf.object or unitSelf;
		target = target.object or target;
		
		-- If we're checking myself we can skip some calculations
		local bIsSelf = (unitSelf == target);
		
		-- If the target is out of PK range, ignore him
		local nDistanceSq;
		if not bIsSelf then
			nDistanceSq = Vector3.Distance2DSq(unitSelf:GetPosition(), utils.GetEnemyPosition(target));
			if nDistanceSq > 4622500 then -- out of PK range
				return 0;
			end
		end
		
		local heroData = HeroData:GetHeroData(target:GetTypeName());
		
		-- Get the base threat for this hero
		local nThreat = heroData and heroData.Threat or 2;
		
		if utils.bEnemyThreatDebug then
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
				local bCanActivate = abil and abil:CanActivate();
				
				if bCanActivate or bCanActivate == nil then --TODO: CanActivate currently returns nil for hostile heroes which is why we need to do this secondary check. If it becomes possible to track enemy hero cooldowns then this should be changed.
					nThreat = nThreat + abilInfo.Threat;
					
					if utils.bEnemyThreatDebug then
						print(',+abil' .. i .. ': ^y' .. string.format("%.2f", nThreat) .. '^*');
					end
				end
			end
		end
		
		do -- Consider HP (0 - 3)
			nThreat = nThreat + utils.nFullHealthPoolThreat * Clamp((utils.GetHealthPercentage(target) - 0.1) / 0.9, 0, 1);
			
			if utils.bEnemyThreatDebug then
				print(',+health (' .. string.format("%.2f", utils.GetHealthPercentage(target)) .. '): ^y' .. string.format("%.2f", nThreat) .. '^*');
			end
		end
		
		do -- Consider mana (0 - 3)
			local nEnemyManaConsumption = utils.GetTotalManaConsumption(target);
			nThreat = nThreat + utils.nCanUseSkillsThreat * min(1, (utils.GetMana(target) / nEnemyManaConsumption));
			
			if utils.bEnemyThreatDebug then
				--BotEcho(target:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after enemy mana (' .. string.format("%.2f", (utils.GetMana(target) / nEnemyManaConsumption)) .. ')');
				print(',+mana (' .. string.format("%.2f", (utils.GetMana(target) / nEnemyManaConsumption)) .. '): ^y' .. string.format("%.2f", nThreat) .. '^*');
			end
		end
		
		if not bIsSelf then
			do -- Consider levels (-4 - 4)
				local nMyLevel = unitSelf:GetLevel();
				local nEnemyLevel = target:GetLevel();
				
				nThreat = nThreat + Clamp(nEnemyLevel - nMyLevel, -utils.nMaxLevelDifferenceThreat, utils.nMaxLevelDifferenceThreat);
				
				if utils.bEnemyThreatDebug then
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
				
				if utils.bEnemyThreatDebug then
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
				
				if utils.bEnemyThreatDebug then
					--BotEcho(target:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after inventory value (' .. string.format("%.2f", nInventoryValueMult) .. ')');
					print(',+inventory value (' .. string.format("%.2f", nInventoryValueMult) .. '): ^y' .. string.format("%.2f", nThreat) .. '^*');
				end
			end
			
			do -- Consider range
				--Magic-Formel: Threat to Range, T(700²) = 2, T(1100²) = 1.5, T(2000²)= 0.75
				nThreat = nThreat * Clamp(3 * (112810000 - nDistanceSq) / (4 * (19 * nDistanceSq + 32810000)), 0.75, 2);
				
				if utils.bEnemyThreatDebug then
					--BotEcho(target:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after distance');
					print(',+distance (' .. string.format("%.2f", math.sqrt(nDistanceSq)) .. '): ^y' .. string.format("%.2f", nThreat) .. '^*\n');
				end
			end
		else
			nThreat = nThreat * 1;
			
			if utils.bEnemyThreatDebug then
				--BotEcho(target:GetTypeName() .. ': ' .. string.format("%.2f", nThreat) .. ' after distance');
				print(',+self: ^y' .. string.format("%.2f", nThreat) .. '^*\n');
			end
		end
		
		return nThreat;
	end
end