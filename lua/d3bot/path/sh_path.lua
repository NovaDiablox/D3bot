-- Copyright (C) 2020 David Vogel
--
-- This file is part of D3bot.
--
-- D3bot is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- D3bot is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with D3bot.  If not, see <http://www.gnu.org/licenses/>.

local D3bot = D3bot
local PATH = D3bot.PATH
local PRIORITY_QUEUE = D3bot.PRIORITY_QUEUE

------------------------------------------------------
--		Static
------------------------------------------------------

-- Make all methods and properties of the class available to its objects.
PATH.__index = PATH

-- Get new instance of a path object.
-- abilities is a table that maps navmesh locomotion types (keys) to locomotion handlers (values)
-- This contains a path as a series of points with some metadata (E.g. what navmesh triangle this points to, the navmesh connection entity it uses (NAV_EDGE, ...)).
function PATH:New(navmesh, abilities)
	local obj = {
		Navmesh = navmesh,
		Abilities = abilities, -- Maps navmesh locomotion types (keys) to locomotion handlers (values)
		Path = {} -- Queue of path elements in reverse order (current element is last in the list)
	}

	-- Instantiate
	setmetatable(obj, self)

	return obj, nil
end

------------------------------------------------------
--		Methods
------------------------------------------------------

-- Generates a path from the start to dest position.
-- A position is defined by both a vector and a navmesh triangle that vector is on/in.
-- It must be made sure that pos triangle pairs match, otherwise the returned path will not be optimal or even malformed.
-- The actual pathfinding is based on edges, not triangles.
function PATH:GeneratePathToPos(startPos, startTriangle, destPos, destTriangle)
	-- See: https://en.wikipedia.org/wiki/A*_search_algorithm

	-- Reset current path
	self.Path = {}

	-- Load some variables from self (for optimization)
	local navmesh = self.Navmesh
	local abilities = self.Abilities

	-- Data structures for pathfinding
	local edgeData = {} -- Contains scores and other information about edges
	local openList = PRIORITY_QUEUE:New(function(edge) return edgeData[edge].FScore end) -- List of edges that have to be expanded

	-- Function to build a path from the generated data
	local function reconstructPath(edge)
		-- Add destPos
		local pathElement = {
			Pos = destPos,
			Via = destTriangle,
			LocomotionHandler = abilities[destTriangle:GetCache().LocomotionType]
		}
		table.insert(self.Path, pathElement)

		-- Add everything in between: Recursively go through edges and their previous elements to find the path in reverse order
		local edge = edge
		while edge do
			local edgeCache = edge:GetCache()
			local edgeInfo = edgeData[edge]

			local pathElement = {
				Pos = edgeCache.Center,
				Via = edgeInfo.Via,
				LocomotionHandler = abilities[edgeInfo.Via:GetCache().LocomotionType]
			}
			table.insert(self.Path, pathElement)

			edge = edgeInfo.FromEdge
		end

		-- Add startPos
		local pathElement = {
			Pos = startPos,
			Via = startTriangle,
			LocomotionHandler = abilities[startTriangle:GetCache().LocomotionType]
		}
		table.insert(self.Path, pathElement)

		return true
	end

	-- Returns the heuristic for a given vector pos.
	-- Should be consistent (monotone), otherwise some code has to be changed.
	local function heuristic(pos)
		return (destPos-pos):Length()
	end

	-- Helper function for adding edges to the open list
	local function enqueueEdge(edge, tentative_gScore, fromEdge, via, toPos)
		edgeData[edge] = {
			GScore = tentative_gScore, -- The cheapest path from start to this edge
			FScore = tentative_gScore + heuristic(toPos), -- Best guess as to how cheap a path can be that goes through this edge
			FromEdge = fromEdge, -- The previous edge
			Via = via -- The navmesh entity that connects the previous and current edge
		}
		openList:Enqueue(edge)
	end

	-- If the bot doesn't know how to navigate on the triangle that he starts on, abort
	local startLocomotionHandler = abilities[startTriangle:GetCache().LocomotionType]
	if not startLocomotionHandler then return false end

	-- If the bot doesn't know how to navigate on the destination triangle, abort
	if not abilities[destTriangle:GetCache().LocomotionType] then return false end

	-- Add the edges of the startTriangle to the open list.
	-- Their initial gScore is the cost of moving from startPos to the edge center.
	local e1, e2, e3 = startTriangle.Edges[1], startTriangle.Edges[2], startTriangle.Edges[3]
	local e1Center, e2Center, e3Center = e1:GetCache().Center, e2:GetCache().Center, e3:GetCache().Center
	enqueueEdge(e1, startLocomotionHandler:GetApproximateCost(e1Center - startPos), nil, startTriangle, e1Center)
	enqueueEdge(e2, startLocomotionHandler:GetApproximateCost(e2Center - startPos), nil, startTriangle, e2Center)
	enqueueEdge(e3, startLocomotionHandler:GetApproximateCost(e3Center - startPos), nil, startTriangle, e3Center)

	-- As search is edge based, get edges that represent the end condition
	local endE1, endE2, endE3 = destTriangle.Edges[1], destTriangle.Edges[2], destTriangle.Edges[3]

	-- Get next edge from queue and expand it
	for edge in openList.Dequeue, openList do
		local edgeCache = edge:GetCache()

		-- Get gScore of current edge
		local gScore = edgeData[edge].GScore

		-- Found destination triangle by one of its edges, now generate path.
		-- This does not include the cost from this edge to the destPos, but should work good enough.
		if edge == endE1 or edge == endE2 or edge == endE3 then
			return reconstructPath(edge)
		end

		-- Iterate over neighbor edges
		for _, v in ipairs(edgeCache.PathfindingEdges) do
			local neighborEdge, via, distance = v.Edge, v.Via, v.Distance

			-- Check if neighbor is in the closed list, if so it's already optimal.
			-- This check must be removed if the heuristic is changed to an "admissible heuristic".
			if true or not edgeData[neighborEdge] then

				-- Get locomotion type and handler.
				-- Via may be a triangle or some other similar navmesh entity.
				local locomotionHandler = abilities[via:GetCache().LocomotionType]

				-- Check locomotion handler ("Is the bot able to navigate to this edge?")
				if locomotionHandler then
					local neighborEdgeCache = neighborEdge:GetCache()
					local tentative_gScore = gScore + locomotionHandler:GetApproximateCost(neighborEdgeCache.Center - edgeCache.Center)

					-- As we will use a consistent (monotone) heuristic and no negative costs, the first encounter of the edge here represents already the optimal path.
					-- There is no need to check this, except if the heuristic gets changed.
					-- TODO: Figure out why pathfinding behaves like it uses an admissible heuristic
					local edgeInfo = edgeData[neighborEdge]
					if tentative_gScore < (edgeInfo and edgeInfo.GScore or math.huge) then

						-- Enqueue neighbor edge
						enqueueEdge(neighborEdge, tentative_gScore, edge, via, neighborEdgeCache.Center)

					end
				end
			end
		end
	end

	-- No path found
	return false
end

-- Draw the path into a 3D rendering context.
function PATH:Render3D()
	render.SetColorMaterialIgnoreZ()
	cam.IgnoreZ(true)

	local oldPos
	for _, pathElement in pairs(self.Path) do
		local pos = pathElement.Pos

		if pos and oldPos then
			render.DrawBeam(pos, oldPos, 5, 0, 1, Color(0, 0, 255, 255))
		end

		oldPos = pos
	end

	cam.IgnoreZ(false)
end