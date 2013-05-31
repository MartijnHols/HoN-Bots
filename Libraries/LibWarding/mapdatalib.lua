-- mapdatalib v1.01 by Fanha
local _G = getfenv(0)
local object = _G.object

object.mapdatalib = object.mapdatalib or {}
local mapdatalib = object.mapdatalib

local print, ipairs, pairs, string, table, next, type, tinsert, tremove, tsort, format, tostring, tonumber, strfind, strsub
	= _G.print, _G.ipairs, _G.pairs, _G.string, _G.table, _G.next, _G.type, _G.table.insert, _G.table.remove, _G.table.sort, _G.string.format, _G.tostring, _G.tonumber, _G.string.find, _G.string.sub
local ceil, floor, pi, tan, atan, atan2, abs, cos, sin, acos, max, random
	= _G.math.ceil, _G.math.floor, _G.math.pi, _G.math.tan, _G.math.atan, _G.math.atan2, _G.math.abs, _G.math.cos, _G.math.sin, _G.math.acos, _G.math.max, _G.math.random
	
local core = object.core
local BotEcho, VerboseLog, BotLog = core.BotEcho, core.VerboseLog, core.BotLog

local bDebug = false;

if bDebug then BotEcho('loading mapdatalib...') end

local tCachedMapDataLayers = {}
local sDefaultDataFile = '/bots/test.botmetadata'

local function GetNodesFromBotMetaDataActiveLayer()
	-- HACK: Currently the only option to query the nodes
	-- Iterate through the grid finding the closest point and removing dupes
	local tNodes = {}
	for x=700,15300,100 do
		for y=400,15600,100 do
			local foundNode = BotMetaData.GetClosestNode(Vector3.Create(x,y))
			tNodes[foundNode] = foundNode
		end
	end
	if bDebug then BotEcho('Nodes cached: '..core.NumberElements(tNodes)) end
	return tNodes
end

-------------------------
-- MapDataLayer functions
-------------------------

-- Gets all of the nodes in the layer
local function MapDataLayerGetNodes(mapDataLayer)
	return mapDataLayer.tNodes
end

-- Gets all of the nodes in the layer matching a particular predicate
local function MapDataLayerQueryNodes(mapDataLayer,funcPredicateQuery)
	local tNodes = {}
	for _,node in pairs(mapDataLayer.tNodes) do
		if funcPredicateQuery(node) then
			tNodes[node] = node
		end
	end
	return tNodes
end

-- Gets a single node in the layer matching a particular predicate
local function MapDataLayerQueryNode(mapDataLayer,funcPredicateQuery)
	local nodeFound = nil
	for _,node in pairs(mapDataLayer.tNodes) do
		if funcPredicateQuery(node) then
			nodeFound = node
			break
		end
	end
	return nodeFound
end

-- Gets a single node with the specified name
local function MapDataLayerGetNodeByName(mapDataLayer, sName)
	local function funcNameQuery(node)
		return node:GetName() == sName
	end
	return mapDataLayer:QueryNode(funcNameQuery)
end

-- Returns all of the nodes with a particular property value
local function MapDataLayerGetNodesWithPropertyValue(mapDataLayer, sProperty, value)
	local function funcPropertyValue(node)
		return node:GetProperty(sProperty) == value
	end
	return mapDataLayer:QueryNodes(funcPropertyValue)
end

-- Returns all of the nodes in the particular bounding area
local function MapDataLayerGetNodesInArea(mapDataLayer,vMin,vMax)
	local function funcArea(node)
		local vecPosition = node:GetPosition()
		return vecPosition.x >= vMin.x and vecPosition.y >= vMin.y and vecPosition.x <= vMax.x and vecPosition.y <= vMin.y
	end
	return mapDataLayer:QueryNodes(funcArea)
end

-- Returns all of the nodes in the particular radius of a point
local function MapDataLayerGetNodesInRadius(mapDataLayer,vecCenter,nRadius)
	local nRadSq = nRadius*nRadius
	local function funcRadius(node)
		return Vector3.Distance2DSq(vecCenter,node:GetPosition()) <= nRadSq
	end
	return mapDataLayer:QueryNodes(funcRadius) 
end

-- Finds a path using a custom costing function
local function MapDataLayerFindPathCustom(mapDataLayer,vecStart,vecEnd,funcCost)
	BotMetaData.SetActiveLayer(mapDataLayer.sSource)
	local ret = BotMetaData.FindPath(vecStart,vecEnd,funcCost)
	if object.metadata ~= nil then
		BotMetaData.SetActiveLayer(sDefaultDataFile)
	end
	return ret
end

-- Finds a path using the default costs
local function MapDataLayerFindPathDefault(mapDataLayer,vecStart,vecEnd)
	local function funcDefaultCost(nodeParent,nodeCurrent,link,nOriginalCost)
		return nOriginalCost
	end
	return mapDataLayer:FindPathCustom(vecStart,vecEnd,funcDefaultCost)
end

-- Finds a path using the given nodes
-- NOTE: tNodes must be a list of nodes keyed by themselves
local function MapDataLayerFindPathUsingNodes(mapDataLayer,vecStart,vecEnd,tNodes)
	local function funcNodeCost(nodeParent,nodeCurrent,link,nOriginalCost)
		if tNodes[nodeCurrent] ~= nil then
			return nOriginalCost
		else
			return nOriginalCost + 9999
		end
	end
	return mapDataLayer:FindPathCustom(vecStart,vecEnd,funcNodeCost)
end

-- Gets the closest node to a position
local function MapDataLayerGetClosestNode(mapDataLayer,vecPosition)
	BotMetaData.SetActiveLayer(mapDataLayer.sSource)
	local ret = BotMetaData.GetClosestNode(vecPosition)
	if object.metadata ~= nil then
		BotMetaData.SetActiveLayer(sDefaultDataFile)
	end
	return ret
end

-------------------------

local function CreateMapDataLayer(sFile)
	-- Hardcoded exception for the default metadata
	local newMapDataLayer = {}
	if not ( object.metadata ~= nil and sFile == sDefaultDataFile ) then
		BotMetaData.RegisterLayer(sFile)
	end
	
	newMapDataLayer.sSource = sFile
	
	if bDebug then BotEcho('Caching map data nodes from file: '..sFile) end
	BotMetaData.SetActiveLayer(sFile)
	newMapDataLayer.tNodes = GetNodesFromBotMetaDataActiveLayer()
	
	newMapDataLayer.GetNodes = MapDataLayerGetNodes
	newMapDataLayer.QueryNodes = MapDataLayerQueryNodes
	newMapDataLayer.QueryNode = MapDataLayerQueryNode
	newMapDataLayer.GetNodeByName = MapDataLayerGetNodeByName
	newMapDataLayer.GetNodesWithPropertyValue = MapDataLayerGetNodesWithPropertyValue
	newMapDataLayer.GetNodesInArea = MapDataLayerGetNodesInArea
	newMapDataLayer.GetNodesInRadius = MapDataLayerGetNodesInRadius
	newMapDataLayer.FindPathCustom = MapDataLayerFindPathCustom
	newMapDataLayer.FindPathDefault = MapDataLayerFindPathDefault
	newMapDataLayer.FindPathUsingNodes = MapDataLayerFindPathUsingNodes
	newMapDataLayer.GetClosestNode = MapDataLayerGetClosestNode
	
	tCachedMapDataLayers[sFile] = newMapDataLayer
	if object.metadata ~= nil then
		BotMetaData.SetActiveLayer(sDefaultDataFile)
	end
	if bDebug then BotEcho('Finished') end
	
	return newMapDataLayer
end

--------------------
-- Library functions
--------------------

-- Gets a map data layer from a file
function mapdatalib.GetMapDataLayerFromFile(sFile)
	local cachedValue = tCachedMapDataLayers[sFile]
	if cachedValue == nil then
		cachedValue = CreateMapDataLayer(sFile)
	end
	return cachedValue
end

-- Gets the default core map layer
function mapdatalib.GetDefaultMapDataLayer()
	return mapdatalib.GetMapDataLayerFromFile(sDefaultDataFile)
end

-- Gets the closest node of a set
function mapdatalib.GetClosestNodeOf(vecPosition,tNodes)
	local nClosestDistSq = nil
	local nodeClosest = nil
	for _,node in pairs(tNodes) do
		local nDistSq = Vector3.Distance2DSq(vecPosition,node:GetPosition())
		if nClosestDistSq == nil or nDistSq < nClosestDistSq then
			nClosestDistSq = nDistSq
			nodeClosest = node
		end
	end
	return nodeClosest
end

--------------------

if bDebug then BotEcho('finished loading mapdatalib') end