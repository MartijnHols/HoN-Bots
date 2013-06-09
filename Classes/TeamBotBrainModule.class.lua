local _G = getfenv(0);
local setmetatable, tinsert, tcopy, type, strlen, strformat = _G.setmetatable, _G.table.insert, _G.table.copy, _G.type, _G.string.len, _G.string.format;

-- The bot classes namespace
_G.HoNBots = _G.HoNBots or {};
_G.HoNBots.Classes = _G.HoNBots.Classes or {};

local classes = _G.HoNBots.Classes;

require '/bots/Classes/Module.class.lua';
if not classes.Module then
	error('The Module class does not exist! Unable to create the TeamBotBrainModule class.');
	return false;
end

-- Make class table
classes.TeamBotBrainModule = {};

-- Easy reference
local class = classes.TeamBotBrainModule;
class.__index = class;

-- Inherit from the Module class
setmetatable(class, {__index = classes.Module})

-- Default properties
class.__Name = 'Unnamed';
class.__IsEnabled = true;

do -- Overrides

--[[ override function class.Create(name) (constructor)
description:		Creates a new instance of the class.
parameters:			name				(String) The name of the module. Must be without Module or TeamBotBrainModule at the end and must be unique.
returns:			(TeamBotBrainModule) A new instance of the class.
]]
function class.Create(name)
	if not name then
		error('Missing parameter 1: name.');
	elseif type(name) ~= 'string' or strlen(name) < 3 then
		error(strformat('Parameter 1 (%s) must be a string of at least 3 characters.', tostring(name)));
	elseif string.find(name:lower(), 'module') or string.find(name:lower(), 'teambotbrainmodule') or string.find(name:lower(), 'tbbmodule') then
		error(strformat('TeamBotBrainModule name (%s) shouldn\'t contain the word "Module".', name));
	end
	local instance = {};
	setmetatable(instance, class);
	
	instance.__Name = name;
	
	return instance;
end

--[[ override function class:GetFullName()
description:		Get the full name of this module.
returns:			(String) The full name of this module, including the module type at the end.
]]
function class:GetFullName()
	return strformat('%sTeamBotBrainModule', self.__Name);
end

end -- Overrides

do -- Extensions

--[[ function class:AddToLegacyTeamBotBrain(teamBot, bOverride)
description:		Add this module to the legacy TeamBotBrain.
parameters:			teamBot				(TeamBotBrain) The TeamBotBrain to add to.
					bOverride			(Boolean) True to allow overriding of an existing module with the same name.
]]
function class:AddToLegacyTeamBotBrain(teamBotBrain, bOverride)
	if not teamBotBrain or not teamBotBrain.onthink then
		error(strformat('TeamBotBrainModule.class: Provided TeamBotBrain "%s" is invalid.', tostring(teamBotBrain)));
	elseif not bOverride and teamBotBrain[self:GetFullName()] then
		error(strformat('TeamBotBrainModule.class: TeamBotBrain "%s" already has a "%s".', (teamBotBrain.myName or tostring(teamBotBrain)), self:GetFullName()));
	end

	if self.__bDebug then
		Echo(strformat('^wTeamBotBrainModule.class: Adding ^y%s^w to TeamBotBrain ^y%s^w.', self:GetFullName(), (teamBotBrain.myName or tostring(teamBotBrain))));
	end

	-- Keep a reference available for others to access
	teamBotBrain[self:GetFullName()] = self;

	-- Reference me so we can use it inside the anonymous function
	local me = self;

	-- Extend onthink
	local oldTeamBotOnThink = teamBotBrain.onthink;
	teamBotBrain.onthink = function (...)
		local returnValue = oldTeamBotOnThink(...);

		if me:IsEnabled() then
			me:Execute(teamBotBrain, ...);
		end

		return returnValue;
	end;
end

end -- Extensions

--[[ Example implementation:
To make a new TeamBotBrainModule you do the following:
local classes = _G.HoNBots.Classes;

local module = classes.TeamBotBrainModule.Create('Dance');
function module:Execute(teamBotBrain, tGameVariables) -- note the ":"! It is required for class instances.
	-- Stuff you want to do
end
-- If you want to add the module to your team bot brain you need to execute the following function
-- in the CoreInitialize of your bot. This is required because the first bot per team gets loaded before the 
-- TeamBotBrain.
module:AddToLegacyTeamBotBrain(HoN.GetTeamBotBrain());
]]
