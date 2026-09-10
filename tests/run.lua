--------------------------------------------------------------------------
-- Run every standalone Pokopia suite.
--
--   lua5.1 tests/run.lua          (from the mod root)
--
-- These need no engine. `tests/core.lua` is separate: it boots Gen1Recomp
-- through the modkit harness and is run by the packaging tooling instead.
--
-- Each suite exits non-zero on its first failing run, so a clean pass here
-- means every suite passed.
--------------------------------------------------------------------------

local SUITES={
  "tests/cinema.lua",   -- shared presentation: frame, cards, page runner
  "tests/chapters.lua", -- Mansion cold open, Celadon chapter opening
  "tests/finale.lua",   -- LOG 568 bookend
}

for _,path in ipairs(SUITES) do
  io.write("== ",path," ==\n")
  local chunk,err=loadfile(path)
  if not chunk then
    io.write("cannot load ",path,": ",tostring(err),"\n")
    os.exit(1)
  end
  chunk()
  io.write("\n")
end

io.write("all suites passed\n")
