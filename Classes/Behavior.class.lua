local _G = getfenv(0);
local setmetatable, tinsert, tcopy, type, strlen, strformat = _G.setmetatable, _G.table.insert, _G.table.copy, _G.type, _G.string.len, _G.string.format;

-- The bot classes namespace
_G.HoNBots = _G.HoNBots or {};
_G.HoNBots.Classes = _G.HoNBots.Classes or {};

local classes = _G.HoNBots.Classes;

require '/bots/Classes/Module.class.lua';
if not classes.Module then
	error('The Module class does not exist! Unable to create the Behavior class.');
	return false;
end

-- Make class table
classes.Behavior = {};

-- Easy reference
local class = classes.Behavior;
class.__index = class;

-- Inherit from the Module class
setmetatable(class, {__index = classes.Module})

-- Default properties
class.__Name = 'Unnamed';
class.__IsEnabled = true;

do -- Overrides

--[[ override function class.Create(name) (constructor)
description:		Creates a new instance of the class.
parameters:			name				(String) The name of the Behavior. Must be without Behavior at the end and must be unique.
returns:			(Behavior) A new instance of the class.
]]
function class.Create(name)
	if not name then
		error('Missing parameter 1: name.');
	elseif type(name) ~= 'string' or strlen(name) < 3 then
		error(strformat('Parameter 1 (%s) must be a string of at least 3 characters.', tostring(name)));
	elseif string.find(name:lower(), 'behavior') or string.find(name:lower(), 'behaviour') then
		error(strformat('Behavior name (%s) shouldn\'t contain the word "Behavior".', name));
	end
	local instance = {};
	setmetatable(instance, class);
	
	instance.__Name = name;
	
	return instance;
end

--[[ override function class:GetFullName()
description:		Get the full name of this Behavior.
returns:			(String) The full name of this Behavior, including the word Behavior at the end.
]]
function class:GetFullName()
	return strformat('%sBehavior', self.__Name);
end

end -- Overrides

do -- Extensions

--[[ abstract function class:Utility(botBrain)
description:		The utility function checks if the behavior should be executed. A BehaviorRunner will run the utility 
					functions for all behaviors and execute the behavior returning the highest utility value.
parameters:			botBrain			(CBotBrain) The bot brain of the bot. This is only passed by a behavior runner.
returns:			(Number) A number indicating the current utility value. If 0 the utility will be ignored.
]]
function class:Utility(botBrain)
	error(strformat('%s Utility function hasn\'t been implemented!', self:GetFullName()));
	return 0;
end

--[[ function class:AddToLegacyBehaviorRunner(behaviorRunner, bOverride)
description:		Add this behavior to a legacy behavior runner. We can't add this behavior instance to the old behaviorLib since it 
					calls .Utility rather then :Utility which doesn't pass the self var properly. So we create a wrapper table and add 
					that instead.
parameters:			behaviorRunner		(BehaviorLib) The legacy behavior runner.
					bOverride			(Boolean) True to allow overriding of the behavior.
]]
function class:AddToLegacyBehaviorRunner(behaviorRunner, bOverride)
	if not behaviorRunner or not behaviorRunner.tBehaviors then
		error(strformat('Behavior.class: Provided behavior runner "%s" is invalid.', tostring(behaviorRunner)));
	elseif not bOverride and behaviorRunner[self:GetFullName()] then
		error(strformat('Behavior.class: Behavior runner "%s" already has a "%s".', tostring(behaviorRunner), self:GetFullName()));
	end
	
	for i = 1, #behaviorRunner.tBehaviors do
		if behaviorRunner.tBehaviors[i].Name == self.__Name then
			error(strformat('Behavior.class: Not adding "%s" to behaviors: found existing behavior with matching name.', self:GetFullName()));
			return;
		end
	end
	
	if self.__bDebug then
		Echo(strformat('^wBehavior.class: Adding ^y%s^w to behavior runner ^y%s^w.', self:GetFullName(), tostring(behaviorRunner)));
	end
	
	-- Keep a reference available for others to access
	behaviorRunner[self:GetFullName()] = self;
	
	-- Reference me so we can use it inside the anonymous function
	local me = self;
	
	local tBhvr = {};
	tBhvr.Name = self.__Name;
	tBhvr.object = self; -- Allow a reference back to the original instance
	tBhvr.Utility = function (botBrain, ...)
		if me:IsEnabled() then
			return me:Utility(botBrain, ...);
		else
			return 0;
		end
	end;
	tBhvr.Execute = function (botBrain, ...)
		if me:IsEnabled() then
			return me:Execute(botBrain, ...);
		else
			return false;
		end
	end;
	
	tinsert(behaviorRunner.tBehaviors, tBhvr);
end

end -- Extensions

--[[ Example implementation:
To make a new behavior you do the following:
local classes = _G.HoNBots.Classes;

local behavior = classes.Behavior.Create('Dance');
function behavior:Utility(botBrain) -- note the ":"! It is required for class instances.
	-- Stuff you want to check
	return nUtility;
end
function behavior:Execute(botBrain) -- note the ":"! It is required for class instances.
	-- Stuff you want to do
	return bActionTaken;
end
-- To add it to your behavior runner:
behavior:AddToLegacyBehaviorRunner(behaviorLib);
]]
