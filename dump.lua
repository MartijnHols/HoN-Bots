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
