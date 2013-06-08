do -- Dump(oObject, skipEcho)

local function getIndentation(nDepth)
	local s = '';
	for i = 0, nDepth do
		s = s .. '    '; -- console doesn't appreciate tabs so use 4 spaces instead
	end
	
	return s;
end

local function dumpToString(object)
	local objectType = type(object);
	
	if objectType == 'string' then
		return '"' .. tostring(object) .. '"';
	elseif objectType == 'number' then
		return tostring(object);
	else
		return '<' .. tostring(object) .. '>';
	end
end

local function dump(oObject, seen, nDepth)
	-- Initial dump should have these values empty
	seen = seen or {};
	nDepth = nDepth or -1;
	
	if type(oObject) == 'table' and not seen[oObject] then
		seen[oObject] = true;
		nDepth = nDepth + 1;
		
		local s = ' {\n'; -- tostring(oObject) - we can't do tostring here since Vector3 is bugged
		for k, v in pairs(oObject) do
			s = s .. getIndentation(nDepth) .. '[' .. dumpToString(k) .. '] = ' .. dump(v, seen, nDepth) .. ',\n';
		end
		
		return s .. getIndentation(nDepth - 1) .. '}';
	else
		return dumpToString(oObject);
	end
end

-- Dump the contents of the provided object into the console
function Dump(oObject, skipEcho)
	local dumped = dump(oObject);
	if skipEcho ~= true then
		Echo(dumped);
	end
	return dumped;
end

end -- Dump

do -- DrawNumber(vecPos, number, height, color)

function DrawNumber(vecPos, number, height, color)
	height = height or 100;
	local width = height / 2;
	color = color or "yellow";
	
	number = tostring(number);
	
	if number:len() > 1 then
		for i = 1, number:len() do
			local newNumber = number:sub(i, i);
			
			DrawNumber(vecPos + Vector3.Create((i - 1) * (width + 20), 0), newNumber, height, color);
		end
		return;
	end
	
	if number == "1" then
		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height), false, color)
	elseif number == "2" then
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(width, 0), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(0, height / 2), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(width, height / 2), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(width, height/2), vecPos + Vector3.Create(width, height), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
	elseif number == "3" then
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(width, 0), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(width, height / 2), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height), false, color)
	elseif number == "4" then
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(0, height / 2), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(width, height / 2), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height), false, color)
	elseif number == "5" then
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(width, 0), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height / 2), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(width, height / 2), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(0, height), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
	elseif number == "6" then
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(width, 0), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(0, height), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(width, height / 2), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(width, height / 2), vecPos + Vector3.Create(width, 0), false, color)
	elseif number == "7" then
		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
	elseif number == "8" then
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(0, height), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(width, 0), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(width, height / 2), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
	elseif number == "9" then
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(width, 0), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(width, height / 2), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height / 2), vecPos + Vector3.Create(0, height), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
	elseif number == "0" then
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(0, height), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(width, 0), vecPos + Vector3.Create(width, height), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, 0), vecPos + Vector3.Create(width, 0), false, color)
		HoN.DrawDebugLine(vecPos + Vector3.Create(0, height), vecPos + Vector3.Create(width, height), false, color)
	end
end

end -- DrawNumber

do -- DrawCircle(vecCenter, nRadius, color)

function DrawCircle(vecCenter, nRadius, color)
	-- How many lines should be used? The bigger the radius the more lines are needed
	local nSteps = nRadius / 100;
	if nSteps < 8 then nSteps = 8; end
	if nSteps > 30 then nSteps = 30; end
	
	if not color then color = 'red'; end
	
	local vecRotator, vecLocation, vecPrevious;
	-- Prepare the vector that moves around the center
	vecRotator = Vector3.Create(nRadius, 0, 0);
	
	for i = 0, nSteps do
		vecRotator = core.RotateVec2D(vecRotator, 360 / nSteps);
		vecLocation = vecCenter + vecRotator;
		
		if vecPrevious then
			HoN.DrawDebugLine(vecPrevious, vecLocation, false, color);
		end
		vecPrevious = vecLocation;
	end
end

end -- DrawCircle