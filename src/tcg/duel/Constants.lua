-- Compatibility wrapper for TCG systems. Constants are generated from the
-- exact pret/poketcg source used to build the ROM manifest; none are authored
-- in this module.

local chunk, err = love.filesystem.load("data/generated/tcg_constants.lua")
if not chunk then error(err or "unable to load generated TCG constants") end
local constants = chunk()
assert(type(constants) == "table", "generated TCG constants must be a table")
return constants
