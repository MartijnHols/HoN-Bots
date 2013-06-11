
--do -- StateInfo class
--	local StateInfo = {};
--	StateInfo.__index = StateInfo;
--
--	-- Private
--	StateInfo.__Name = nil;
--
--	-- Public properties
--	-- These properties may also be tables containing different values per level, e.g. abil.CanStun = { false,false,false,true }
--	StateInfo.Duration = 0;
--	StateInfo.IsStun = false;
--	StateInfo.IsSlow = false;
--	StateInfo.IsRoot = false;
--	StateInfo.CanBePurged = true; -- most abilities can be purged
--	StateInfo.Radius = 0; -- in units - radius of the DPS
--	StateInfo.MagicDPS = 0;
--	StateInfo.PhysicalDPS = 0;
--
--	function StateInfo.Create(sName)
--		local instance = {};
--		setmetatable(instance, StateInfo);
--		
--		instance.__Name = sName;
--		
--		return instance;
--	end
--
--	function StateInfo:GetName()
--		return self.__Name;
--	end
--	function StateInfo:GetValue(val, nAbilityLevel)
--		if type(val) == 'table' then
--			return val[nAbilityLevel - 1];
--		end
--		
--		return val;
--	end
--end -- StateInfo class



-- Example instance:

-- Accursed
local hero = HeroInfo.Create('Hero_Accursed');
hero.Threat = 2;

-- Cauterize
local abilCauterize = AbilityInfo.Create(0, 'Ability_Accursed1');
abilCauterize.Threat = 2;
abilCauterize.IsSingleTarget = true;
abilCauterize.MagicDamage = { 100, 150, 200, 250 };
hero:AddAbility(abilCauterize);

-- Fire Shield
local abilFireShield = AbilityInfo.Create(1, 'Ability_Accursed2');
abilFireShield.Threat = 2;
abilFireShield.Radius = 700;
abilFireShield.MagicDamage = { 110, 140, 170, 200 }; --TODO: should we really consider this?
abilFireShield.Buff = 'State_Accursed_Ability2';
hero:AddAbility(abilFireShield);

-- Sear
local abilSear = AbilityInfo.Create(2, 'Ability_Accursed3');
abilSear.Threat = 0;
hero:AddAbility(abilSear);

-- Flame Consumption
local abilFlameConsumption = AbilityInfo.Create(3, 'Ability_Accursed4');
abilFlameConsumption.Threat = 0;
hero:AddAbility(abilFlameConsumption);

_G.SomeGlobalVariableAsToNotLoadThisSeperatelyForEverySingleBot = _G.SomeGlobalVariableAsToNotLoadThisSeperatelyForEverySingleBot or {};
_G.SomeGlobalVariableAsToNotLoadThisSeperatelyForEverySingleBot[hero:GetTypeName()] = hero;











-- This table contains a table for each hero with values that represent the threat of each ability
-- The base field of a table is the default threat for the hero, which should be used to consider passive abilities or abilities with very short cooldowns
-- Most heroes have a total threat of 6, this may be lower or higher if the hero isn't a big threat. Ulties with long cooldowns may get bonus threat that is completely removed if it is on cooldown.
-- The way an ability threat is calculated is like the following:
-- Off cooldown: full. 20 sec cooldown (or shorter if max cd is less) - 0 sec = linear increase. >20 sec = 0.
-- If we don't have enough mana (+regen for 20 seconds) to cast the ability it gets 0 threat.
local tHeroThreats = {
	['Hero_Accursed'] = { -- Accursed
		Base = 2,
		0 = 2,
		1 = 2,
		2 = 0,
		3 = 0
	},
	['Hero_Aluna'] = { -- Aluna
		Base = 1,
		0 = 2,
		1 = 1,
		2 = 1,
		3 = 1
	},
	['Hero_Andromeda'] = { -- Andromeda
		Base = 1,
		0 = 2,
		1 = 1,
		2 = 0,
		3 = 2
	},
	['Hero_Arachna'] = { -- Arachna
		Base = 2,
		0 = 2,
		1 = 0,
		2 = 0,
		3 = 2
	},
	['Hero_Armadon'] = { -- Armadon (5)
		Base = 2,
		0 = 1,
		1 = 2,
		2 = 0,
		3 = 0
	},
	['Hero_Artesia'] = { -- Artesia
		Base = 0,
		0 = 3,
		1 = 0,
		2 = 0,
		3 = 3
	},
	['Hero_Artillery'] = { -- Artillery
		Base = 2,
		0 = 2,
		1 = 0,
		2 = 0,
		3 = 2,
		5 = 0 -- Ability_Artillery1a
	},
	['Hero_BabaYaga'] = { -- Wretched Hag
		Base = 1,
		0 = 1.5,
		1 = 0,
		2 = 1.5,
		3 = 2
	},
	['Hero_Behemoth'] = { -- Behemoth (7)
		Base = 1,
		0 = 2,
		1 = 1,
		2 = 0,
		3 = 3 -- long cooldown, but lot of hurt, so 1 bonus threat value
	},
	['Hero_Bephelgor'] = { -- Balphagore
		Base = 2,
		0 = 1,
		1 = 1,
		2 = 0, -- consider this passive
		3 = 2
	},
	['Hero_Berzerker'] = { -- Berzerker
		Base = 0,
		0 = 2,
		1 = 1,
		2 = 1,
		3 = 2, -- buff: State_Berzerker_Ability4
	},
	['Hero_Blitz'] = { -- Blitz (5)
		Base = 0,
		0 = 2,
		1 = 1,
		2 = 0,
		3 = 2
	},
	['Hero_Bombardier'] = { -- Bombardier
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Bubbles'] = { -- Bubbles
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Bushwack'] = { -- Bushwack
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Chipper'] = { -- The Chipper
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Chronos'] = { -- Chronos
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_CorruptedDisciple'] = { -- Corrupted Disciple
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Cthulhuphant'] = { -- Cthulhuphant
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Dampeer'] = { -- Dampeer
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Deadwood'] = { -- Deadwood
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Defiler'] = { -- Defiler
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Devourer'] = { -- Devourer
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_DiseasedRider'] = { -- Plague Rider
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_DoctorRepulsor'] = { -- Doctor Repulsor
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Dreadknight'] = { -- Lord Salforis
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_DrunkenMaster'] = { -- Drunken Master
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_DwarfMagi'] = { -- Blacksmith
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Ebulus'] = { -- Slither
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Electrician'] = { -- Electrician
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Ellonia'] = { -- Ellonia
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_EmeraldWarden'] = { -- Emerald Warden
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0, -- Ability_EmeraldWarden4_a
		6 = 0, -- Ability_EmeraldWarden4_b
		7 = 0 -- Ability_EmeraldWarden4_c
	},
	['Hero_Empath'] = { -- Empath
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0, -- Ability_Empath5
	},
	['Hero_Engineer'] = { -- Engineer
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Fade'] = { -- Fayde
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Fairy'] = { -- Nymphora
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0 -- Ability_Fairy4_TPIn
	},
	['Hero_FlameDragon'] = { -- Draconis
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_FlintBeastwood'] = { -- Flint Beastwood
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Flux'] = { -- Flux
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_ForsakenArcher'] = { -- Forsaken Archer
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Frosty'] = { -- Glacius
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Gauntlet'] = { -- Gauntlet
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0 -- Ability_Gauntlet2_Sub
	},
	['Hero_Gemini'] = { -- Gemini
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Geomancer'] = { -- Geomancer
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Gladiator'] = { -- The Gladiator
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Grinex'] = { -- Grinex
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Gunblade'] = { -- Gunblade
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Hammerstorm'] = { -- Hammerstorm
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Hantumon'] = { -- Night Hound
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Hellbringer'] = { -- Hellbringer
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_HellDemon'] = { -- Soul Reaper
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Hiro'] = { -- Swiftblade
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Hunter'] = { -- Blood Hunter
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Hydromancer'] = { -- Myrmidon
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Javaras'] = { -- Magebane
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Jereziah'] = { -- Jeraziah
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Kenisis'] = { -- Kinesis
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0, -- Ability_Kenisis2_Lift
		6 = 0 -- Ability_Kenisis2_Launch
	},
	['Hero_Kraken'] = { -- Kraken
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Krixi'] = { -- Moon Queen
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Kunas'] = { -- Thunderbringer
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Legionnaire'] = { -- Legionnaire
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Lodestone'] = { -- Lodestone
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Magmar'] = { -- Magmus
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Maliken'] = { -- Maliken
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0, -- Ability_Maliken2_Flame
		6 = 0 -- Ability_Maliken2_Healing
	},
	['Hero_Martyr'] = { -- Martyr
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_MasterOfArms'] = { -- Master Of Arms
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Midas'] = { -- Midas
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Monarch'] = { -- Monarch
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_MonkeyKing'] = { -- Monkey King
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Moraxus'] = { -- Moraxus
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Mumra'] = { -- Pharaoh
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0 -- Ability_Mumra4_Ally
	},
	['Hero_Nomad'] = { -- Nomad
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0 -- Ability_Nomad2a
		6 = 0 -- Ability_Nomad2b
	},
	['Hero_Oogie'] = { -- Oogie
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Ophelia'] = { -- Ophelia
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Panda'] = { -- Pandamonium
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Parasite'] = { -- Parasite
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Pearl'] = { -- Pearl
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Pestilence'] = { -- Pestilence
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Plant'] = { -- Bramble
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_PollywogPriest'] = { -- Pollywog Priest
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Predator'] = { -- Predator
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Prisoner'] = { -- Prisoner 945
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0 -- Ability_Prisoner2_Sub
	},
	['Hero_Prophet'] = { -- Prophet
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_PuppetMaster'] = { -- Puppet Master
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Pyromancer'] = { -- Pyromancer
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Ra'] = { -- Amun-Ra
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Rally'] = { -- Rally
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Rampage'] = { -- Rampage
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Ravenor'] = { -- Ravenor
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Revenant'] = { -- Revenant
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Rhapsody'] = { -- Rhapsody
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0, -- Ability_Rhapsody4_In
		6 = 0 -- Ability_Rhapsody4_Out
	},
	['Hero_Riftmage'] = { -- Riftwalker
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Rocky'] = { -- Pebbles
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Salomon'] = { -- Salomon
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_SandWraith'] = { -- Sand Wraith
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Scar'] = { -- The Madman
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Scout'] = { -- Scout
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0 -- Ability_Scout2_Detonate
	},
	['Hero_ShadowBlade'] = { -- Shadowblade
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Shaman'] = { -- Demented Shaman
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Silhouette'] = { -- Silhouette
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0, -- Ability_Silhouette2_Go
		6 = 0, -- Ability_Silhouette2_Pull
		7 = 0 -- Ability_Silhouette4_Swap
	},
	['Hero_SirBenzington'] = { -- Sir Benzington
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Solstice'] = { -- Solstice
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0 -- Ability_Solstice4a
	},
	['Hero_Soulstealer'] = { -- Soulstealer
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0, -- Ability_Soulstealer1a
		6 = 0, -- Ability_Soulstealer1b
		7 = 0 -- Ability_Soulstealer1c
	},
	['Hero_Succubis'] = { -- Succubus
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Taint'] = { -- Gravekeeper
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0, -- Ability_Taint2_Damage
		6 = 0 -- Ability_Taint2_Heal
	},
	['Hero_Tempest'] = { -- Tempest
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Treant'] = { -- Keeper of the Forest
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Tremble'] = { -- Tremble
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0, -- Ability_Tremble2a
		6 = 0 -- Ability_Tremble2b
	},
	['Hero_Tundra'] = { -- Tundra
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Valkyrie'] = { -- Valkyrie
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Vanya'] = { -- The Dark Lady
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Vindicator'] = { -- Vindicator
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Voodoo'] = { -- Voodoo Jester
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_WitchSlayer'] = { -- Witch Slayer
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_WolfMan'] = { -- War Beast
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Xalynx'] = { -- Torturer
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
	['Hero_Yogi'] = { -- Wildsoul
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0,
		5 = 0 -- Ability_Yogi5
	},
	['Hero_Zephyr'] = { -- Zephyr
		Base = 0,
		0 = 0,
		1 = 0,
		2 = 0,
		3 = 0
	},
};

local tBuffThreat = {
	['State_Aluna_Ability4'] = 2, -- Aluna ult
	--['State_Andromeda_Ability3'] = 2, -- Andromeda aura - this is already included in the DPS threat
	['State_Berzerker_Ability4'] = 3, -- Berzerker ult
	--['State_Arachna_Ability3'] = 2, -- Arachna aura - this is already included in the DPS threat
	--['State_Armadon_Ability4'] = 0.5, -- Armadon ult, stacks - this is already included in the DPS threat
};

local tDebuffThreat = {
	['State_Andromeda_Ability2'] = 2, -- Andromeda Aurora (minus armor)
	['State_Armadon_Ability2'] = 1, -- Armadon Spine Burst (increased damage), stacks
};