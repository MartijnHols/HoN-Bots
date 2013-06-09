local _G = getfenv(0);
local setmetatable, tinsert, tcopy, type, strlen, strformat = _G.setmetatable, _G.table.insert, _G.table.copy, _G.type, _G.string.len, _G.string.format;

-- The bot classes namespace
_G.HoNBots = _G.HoNBots or {};
_G.HoNBots.Classes = _G.HoNBots.Classes or {};

local classes = _G.HoNBots.Classes;

require '/bots/Classes/Module.class.lua';
if not classes.Module then
	error('The Module class does not exist! Unable to create the BotBrainModule class.');
	return false;
end

-- Make class table
classes.BotBrainModule = {};

-- Easy reference
local class = classes.BotBrainModule;
class.__index = class;

-- Inherit from the Module class
setmetatable(class, {__index = classes.Module})

-- Default properties
class.__Name = 'Unnamed';
class.__IsEnabled = true;

do -- Overrides

--[[ override function class.Create(name) (constructor)
description:		Creates a new instance of the class.
parameters:			name				(String) The name of the module. Must be without Module or BotBrainModule at the end and must be unique.
returns:			(BotBrainModule) A new instance of the class.
]]
function class.Create(name)
	if not name then
		error('Missing parameter 1: name.');
	elseif type(name) ~= 'string' or strlen(name) < 3 then
		error(strformat('Parameter 1 (%s) must be a string of at least 3 characters.', tostring(name)));
	elseif string.find(name:lower(), 'module') or string.find(name:lower(), 'botbrainmodule') or string.find(name:lower(), 'bbmodule') then
		error(strformat('BotBrainModule name (%s) shouldn\'t contain the word "Module".', name));
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
	return strformat('%sModule', self.__Name);
end

end -- Overrides

do -- Extensions

--[[ function class:AddToLegacyBotBrain(botBrain, bOverride)
description:		Add this module to a legacy BotBrain.
					If the BotBrain is a TeamBotBrain then this function may only be called from the CoreInitialize of a bot.
parameters:			botBrain			(BotBrain) The BotBrain to add to.
					bOverride			(Boolean) True to allow overriding of an existing module with the same name.
]]
function class:AddToLegacyBotBrain(botBrain, bOverride)
	local sBrainType = (botBrain.teamID and 'TeamBotBrain') or 'BotBrain';
	
	if not botBrain or not botBrain.onthink then
		error(strformat('BotBrainModule.class: Provided %s "%s" is invalid.', sBrainType, tostring(botBrain)));
	elseif not bOverride and botBrain[self:GetFullName()] then
		error(strformat('BotBrainModule.class: %s "%s" already has a "%s".', sBrainType, (botBrain.myName or tostring(botBrain)), self:GetFullName()));
	end
	
	if self.__bDebug then
		Echo(strformat('^wBotBrainModule.class: Adding ^y%s^w to %s ^y%s^w.', self:GetFullName(), sBrainType, (botBrain.myName or tostring(botBrain))));
	end
	
	-- Keep a reference available for others to access
	botBrain[self:GetFullName()] = self;
	
	-- Reference me so we can use it inside the anonymous function
	local me = self;
	
	-- Extend onthink
	local oldBotBrainOnThink = botBrain.onthink;
	botBrain.onthink = function (...)
		local returnValue = oldBotBrainOnThink(...);
		
		if me:IsEnabled() then
			me:Execute(botBrain, ...);
		end
		
		return returnValue;
	end;
end

end -- Extensions

--[[ Example implementation:
To make a new BotBrainModule you do the following:
local classes = _G.HoNBots.Classes;

local module = classes.BotBrainModule.Create('Dance');
function module:Execute(botBrain, tGameVariables) -- note the ":"! It is required for class instances.
	-- Stuff you want to do
end
module:AddToLegacyBotBrain(object);
]]
