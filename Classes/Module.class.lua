local _G = getfenv(0);
local setmetatable, tinsert, tcopy, type, strlen, strformat = _G.setmetatable, _G.table.insert, _G.table.copy, _G.type, _G.string.len, _G.string.format;

-- A namespace to contain Bot classes
-- This is required so our classes don't polute the global namespace and so that they are harder to accidentally override (if Module
-- was in _G then all it would require to override Module would be to type "Module" instead of "module" somewhere, the latter
-- which could be common when making a new Module instance and which wouldn't throw an exception).
_G.HoNBots = _G.HoNBots or {};
_G.HoNBots.Classes = _G.HoNBots.Classes or {};

local classes = _G.HoNBots.Classes;

-- Make class table
classes.Module = {};

-- Easy reference
local class = classes.Module;
class.__index = class;

-- Default properties
class.__Name = 'Unnamed';
class.__IsEnabled = true;
class.__bDebug = false;

--[[ function class.Create(name) (constructor)
description:		Creates a new instance of the Module class. Should always be overridden by sub classes.
parameters:			name				(String) The name of the Module. Must be without Module at the end and must be unique.
returns:			(Module) A new instance of the class.
]]
function class.Create(name)
	if not name then
		error('Missing parameter 1: name.');
	elseif type(name) ~= 'string' or strlen(name) < 3 then
		error(strformat('Parameter 1 (%s) must be a string of at least 3 characters.', tostring(name)));
	elseif string.find(name:lower(), 'module') then
		error(strformat('Module name (%s) shouldn\'t contain the word "Module".', name));
	end
	local instance = {};
	setmetatable(instance, class);
	
	instance.__Name = name;
	
	return instance;
end

--[[ abstract function class:Execute(botBrain)
description:		The execute function is the code that is executed when appropriate.
parameters:			botBrain			(CBotBrain) The bot brain of the (team)bot.
					...					(*) Any other relevant parameters.
]]
function class:Execute(botBrain, ...)
	error(strformat('%s Execute function hasn\'t been implemented!', self:GetFullName()));
end

--[[ function class:GetName()
description:		Get the name of this Module.
returns:			(String) The name of this Module as provided in the Create function.
]]
function class:GetName()
	return self.__Name;
end
--[[ function class:GetFullName()
description:		Get the full name of this Module.
returns:			(String) The full name of this Module, including the word Module at the end.
]]
function class:GetFullName()
	return strformat('%sModule', self.__Name);
end
--[[ function class:__tostring()
description:		Make a string representation of this Module.
returns:			(String) An identifier of this Module.
]]
function class:__tostring()
	return strformat('<%s>', self:GetFullName());
end

--[[ function class:Enable()
description:		Enable this Module.
]]
function class:Enable()
	if self.__bDebug then
		Echo(strformat('^wModule.class: Enabling ^y%s^w.', self:GetFullName()));
	end
	
	self.__IsEnabled = true;
end
--[[ function class:Disable()
description:		Disable this Module.
]]
function class:Disable()
	if self.__bDebug then
		Echo(strformat('^wModule.class: Disabling ^y%s^w.', self:GetFullName()));
	end
	
	self.__IsEnabled = false;
end
--[[ function class:IsEnabled()
description:		Check if this Module is enabled.
returns:			(Boolean) Returns if the Module is enabled.
]]
function class:IsEnabled()
	return self.__IsEnabled;
end

--[[ Example implementation:
To make a new Module you do the following:
local classes = _G.HoNBots.Classes;

local module = classes.Module.Create('Dance');
function module:Execute(botBrain) -- note the ":"! It is required for class instances.
	-- Stuff you want to do
end

-- At this point you need to add the module to whatever object you want yourself. If you want to add a module 
-- to the TeamBotBrain, BotBrain or a BehaviorRunner you should probably use the TeamBotBrainModule, BotBrainModule 
-- or Behavior class instead of this class. Generally this is the case.
]]
