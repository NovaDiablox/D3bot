local D3bot = D3bot
local NAV_TRIANGLE = D3bot.NAV_TRIANGLE

------------------------------------------------------
--						Static						--
------------------------------------------------------

-- Get new instance of a triangle object.
-- This represents a triangle that is defined by 3 edges that are connected in a loop.
-- If a triangle with the same id already exists, it will be overwritten.
-- It's possible to get invalid triangles, therefore this needs to be checked.
function NAV_TRIANGLE:New(navmesh, id, e1, e2, e3)
	local obj = {
		Navmesh = navmesh,
		ID = id or navmesh:GetUniqueID(), -- TODO: Convert id to integer if possible
		Edges = {e1, e2, e3}
	}

	setmetatable(obj, self)
	self.__index = self

	-- TODO: Selfcheck

	-- Check if there was a previous element. If so, delete it first
	local old = navmesh.Triangles[obj.ID]
	if old then old:_Delete() end

	-- Add object to the navmesh
	navmesh.Triangles[obj.ID] = obj

	-- Add reference to this triangle to all edges
	table.insert(e1.Triangles, obj)
	table.insert(e2.Triangles, obj)
	table.insert(e3.Triangles, obj)

	-- Publish change event
	if navmesh.PubSub then
		navmesh.PubSub:SendTriangleToSubs(obj)
	end

	return obj
end

-- Same as NAV_TRIANGLE:New(), but uses table t to restore a previous state that came from MarshalToTable().
-- As it needs a navmesh to find the edges by their reference ID, this should only be called after all the edges have been fully loaded into the navmesh.
function NAV_TRIANGLE:NewFromTable(navmesh, t)
	local e1 = navmesh:FindEdgeByID(t.Edges[1])
	local e2 = navmesh:FindEdgeByID(t.Edges[2])
	local e3 = navmesh:FindEdgeByID(t.Edges[3])
	
	if not e1 or not e2 or not e3 then error("Couldn't find all edges by their reference") end

	local obj = self:New(navmesh, t.ID, e1, e2, e3)

	return obj
end

------------------------------------------------------
--						Methods						--
------------------------------------------------------

-- Returns the object's ID, which is most likely a number object.
-- It can be anything else, though.
function NAV_TRIANGLE:GetID()
	return self.ID
end

-- Returns a table that contains all important data of this object.
function NAV_TRIANGLE:MarshalToTable()
	local t = {
		ID = self:GetID(),
		Edges = {
			self.Edges[1]:GetID(),
			self.Edges[2]:GetID(),
			self.Edges[3]:GetID()
		}
	}

	return t -- Make sure that any object returned here is a deep copy of its original
end

-- Deletes the triangle from the navmesh and makes sure that there is nothing left that references it.
function NAV_TRIANGLE:Delete()
	-- Publish change event
	if self.Navmesh.PubSub then
		self.Navmesh.PubSub:DeleteTriangleFromSubs(self:GetID())
	end

	return self:_Delete()
end

-- Internal method.
function NAV_TRIANGLE:_Delete()
	-- Delete any reference to this triangle from edges
	for _, edge in ipairs(self.Edges) do
		table.RemoveByValue(edge.Triangles, self)
		-- Delete any "floating" edge
		edge:_GC()
	end

	self.Navmesh.Triangles[self.ID] = nil
	self.Navmesh = nil
end

-- Returns wether the triangle consists out of the three given edges or not.
function NAV_TRIANGLE:ConsistsOfEdges(e1, e2, e3)
	local se1, se2, se3 = self.Edges[1], self.Edges[2], self.Edges[3]
	-- There is probably a nicer way to do this, but it doesn't need to be that fast.
	-- This will cause between 6 to 9 comparison operations, but most of time time just 6.
	-- If the optimizer is doing its job well, it may just be 3 comparisons at best.
	if se1 == e1 and se2 == e2 and se3 == e3 then return true end
	if se1 == e1 and se2 == e3 and se3 == e2 then return true end
	if se1 == e2 and se2 == e1 and se3 == e3 then return true end
	if se1 == e2 and se2 == e3 and se3 == e1 then return true end
	if se1 == e3 and se2 == e1 and se3 == e2 then return true end
	if se1 == e3 and se2 == e2 and se3 == e1 then return true end
	return false
end

-- Draw the edge into a 3D rendering context.
function NAV_TRIANGLE:Render3D()
	local e1, e2, e3 = self.Edges[1], self.Edges[2], self.Edges[3]
	--local p1, p2, p3 = e1.Points[1], e2.Points[1], e3.Points[1]

	-- TODO: Cache triangle points

	--render.DrawQuad(e1, p2)
end