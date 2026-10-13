--!nocheck
-- lune run tools/test.luau [filter]   (run from the crack-a-portal folder)
-- Runs every ServerStorage/Tests/*.spec.luau through the same Run module Studio uses.
local process = require("@lune/process")
local Harness = require("./harness")

local run = Harness.require(Harness.game:GetService("ServerStorage").Tests.Run)
local passed, failed = run(process.args[1])
process.exit(if failed == 0 and passed > 0 then 0 else 1)
