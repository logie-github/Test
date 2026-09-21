-- TCG generated-data loader. All values in these files originate from the
-- user's validated ROM and the matching pret/poketcg manifest.

local Data = {}

local function loadGenerated(name)
  local path = "data/generated/" .. name .. ".lua"
  local chunk, err = love.filesystem.load(path)
  if not chunk then error(err or ("unable to load " .. path)) end
  local value = chunk()
  assert(type(value) == "table", path .. " did not return a table")
  return value
end

function Data:load()
  self.meta = loadGenerated("tcg_meta")
  self.memory = loadGenerated("tcg_memory")
  self.constants = loadGenerated("tcg_constants")
  self.core = loadGenerated("tcg_core")
  self.effects = loadGenerated("tcg_effects")
  self.text = loadGenerated("tcg_text")
  self.cards = loadGenerated("tcg_cards")
  self.decks = loadGenerated("tcg_decks")

  assert(self.meta.schema == 5, "unsupported generated TCG data schema")
  assert(self.memory.schema == 1, "unsupported generated TCG memory schema")
  assert(self.core.schema == 3, "unsupported generated TCG core-data schema")
  assert(self.effects.schema == 1, "unsupported generated TCG effect-data schema")
  assert(self.cards.count == self.constants.NUM_CARDS, "generated card count mismatch")
  assert(self.decks.count == self.constants.NUM_VALID_DECKS, "generated deck count mismatch")
  return self
end

return Data
