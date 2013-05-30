local _G = getfenv(0);
local setmetatable, tinsert, tcopy, type, strlen, strformat = _G.setmetatable, _G.table.insert, _G.table.copy, _G.type, _G.string.len, _G.string.format;

local bDebug = true;

-- A namespace to contain Bot classes
-- This is required so our classes don't polute the global namespace and so that they are harder to accidentally override (if Behavior
-- was in _G then all it would require to override Behavior would be to type "Behavior" instead of "behavior" somewhere, the latter
-- which could be common when making a new behavior instance).
_G.BotsNS = _G.BotsNS or {};

_G.BotsNS.Behavior = {};
local class = _G.BotsNS.Behavior;
class.__index = class;
class.__Name = 'Unnamed';
class.__IsEnabled = true;

--[[ function class.Create(name) (constructor)
description:		Creates a new instance of the class.
parameters:			name				(string) The name of the behavior. Must be without Behavior at the end and must be unique.
returns:			(Behavior) A new instance of the class.
]]
function class.Create(name)
	if not name then
		error('Missing parameter 1: name.');
	elseif type(name) ~= 'string' or strlen(name) < 3 then
		error('Parameter 1 (' .. tostring(name) .. ') must be a string of at least 3 characters.');
	elseif string.find(name:lower(), 'behavior') or string.find(name:lower(), 'behaviour') then
		error('Behavior name (' .. name .. ') shouldn\'t contain the word "Behavior".');
	end
	local bhvr = {};
	setmetatable(bhvr, class);
	
	bhvr.__Name = name;
	
	return bhvr;
end

--[[ abstract function class:Utility(botBrain)
description:		The utility function checks if the behavior should be executed. This is different for either a BehaviorRunner or 
					a TeamBotBrain;
					 - A BehaviorRunner will run the utility functions for all behaviors and execute the behavior returning the 
					   highest utility value.
					 - A TeamBotBrain will run the utility function for all behaviors and execute all behaviors that return a 
					   utility value above 0.
parameters:			botBrain			(CBotBrain) The bot brain of the bot. This is only passed by a behavior runner.
returns:			(number) A number indicating the current utility value. If 0 the utility will be ignored.
]]
function class:Utility(botBrain)
	error(self.Name .. 'Behavior Utility function hasn\'t been implemented!');
	return 0;
end

--[[ abstract function class:Execute(botBrain)
description:		The execute function is executed if the utility function returned the highest utility value. In case the behavior 
					is running in a TeamBotBrain it will be executed whenever the utility value is above 0.
parameters:			botBrain			(CBotBrain) The bot brain of the bot. This is only passed by a behavior runner.
]]
function class:Execute(botBrain)
	error(self.Name .. 'Behavior Execute function hasn\'t been implemented!');
end

function class:GetName()
	return self.__Name;
end
function class:GetFullName()
	return strformat('%sBehavior', self.__Name);
end

function class:Enable()
	if bDebug then
		Echo('^wBehavior.class: Enabling ^y' .. self:GetFullName() .. '^w.');
	end
	
	self.__IsEnabled = true;
end
function class:Disable()
	if bDebug then
		Echo('^wBehavior.class: Disabling ^y' .. self:GetFullName() .. '^w.');
	end
	
	self.__IsEnabled = false;
end
function class:IsEnabled()
	return self.__IsEnabled;
end

function class:__tostring()
	return strformat('<%s>', self:GetFullName());
end

--[[ function class:AddToLegacyBehaviorRunner(behaviorRunner)
description:		Add this behavior to a legacy behavior runner. We can't add this behavior instance to the old behaviorLib since it 
					calls .Utility rather then :Utility which doesn't pass the self var properly. So we create a wrapper table and add 
					that instead.
parameters:			behaviorRunner		(BehaviorLib) The behavior runner.
					bOverride			(Boolean) True to allow overriding of the behavior.
]]
function class:AddToLegacyBehaviorRunner(behaviorRunner, bOverride)
	if not behaviorRunner or not behaviorRunner.tBehaviors then
		error('Behavior.class: Provided behavior runner "' .. tostring(behaviorRunner) .. '" is invalid.');
	elseif not bOverride and behaviorRunner[self.__Name .. 'Behavior'] then
		error('Behavior.class: Behavior runner "' .. tostring(behaviorRunner) .. '" already has a "' .. self:GetFullName() .. '".');
	end
	
	for i = 1, #behaviorRunner.tBehaviors do
		if behaviorRunner.tBehaviors[i].Name == self.__Name then
			error('Behavior.class: Not adding "' .. self:GetFullName() .. '" to behaviors: found existing behavior with matching name.');
			return;
		end
	end
	
	if bDebug then
		Echo('^wBehavior.class: Adding ^y' .. self:GetFullName() .. '^w to behavior runner ^y' .. tostring(behaviorRunner) .. '^w.');
	end
	
	-- Keep a reference available for others to access
	behaviorRunner[self.__Name .. 'Behavior'] = self;
	
	-- Reference me so we can use it inside the anonymous function
	local me = self;
	
	local tBhvr = {};
	tBhvr.Name = self.__Name;
	tBhvr.Utility = function (...)
		if me:IsEnabled() then
			return me:Utility(...);
		else
			return 0;
		end
	end;
	tBhvr.Execute = function (...)
		if me:IsEnabled() then
			return me:Execute(...);
		else
			return false;
		end
	end;
	
	tinsert(behaviorRunner.tBehaviors, tBhvr);
end

--[[ function class:AddToLegacyTeamBotBrain(teamBot)
description:		Add this behavior to the legacy TeamBotBrain.
parameters:			teamBot				(TeamBotBrain) The TeamBotBrain to add to.
					bOverride			(Boolean) True to allow overriding of the behavior.
]]
function class:AddToLegacyTeamBotBrain(teamBot, bOverride)
	if not teamBot or not teamBot.onthink then
		error('Behavior.class: Provided teambot "' .. tostring(teamBot) .. '" is invalid.');
	elseif not bOverride and teamBot[self.__Name .. 'Behavior'] then
		local sTeamBotName = teamBot.myName or tostring(teamBot);
		error('Behavior.class: Teambot "' .. sTeamBotName .. '" already has a "' .. self:GetFullName() .. '".');
	end
	
	if bDebug then
		Echo('^wBehavior.class: Adding ^y' .. self:GetFullName() .. '^w to TeamBotBrain ^y' .. teamBot.myName .. '^w.');
	end
	
	-- Keep a reference available for others to access
	teamBot[self.__Name .. 'Behavior'] = self;
	
	-- Reference me so we can use it inside the anonymous function
	local me = self;
	
	-- Extend onthink
	local oldTeamBotOnThink = teamBot.onthink;
	teamBot.onthink = function (...)
		local returnValue = oldTeamBotOnThink(...);
		
		-- The team bot brain doesn't have any orders so several behaviors should be able to run within the same frame
		if me:IsEnabled() and me:Utility(...) > 0 then
			me:Execute(...);
		end
		
		return returnValue;
	end;
end

--[[
To make a new behavior you do the following:
local behavior = BotsNS.Behavior.Create('Dance');
function behavior:Utility(botBrain) -- note the ":"! It is required for classes.
	-- Stuff you want to check
end
function behavior:Execute(botBrain) -- note the ":"! It is required for classes.
	-- Stuff you want to do
end
-- To add it to your behavior runner:
behavior:AddToLegacyBehaviorRunner(behaviorLib);
-- If you want to add the behaviro to your team bot brain you need to execute the following function
-- in the CoreInitialize of your bot. This is required because the first bot gets loaded before the 
-- TeamBotBrain.
behavior:AddToLegacyTeamBotBrain(HoN.GetTeamBotBrain());
]]
