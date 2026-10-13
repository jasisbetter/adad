--!nocheck
-- lune run tools/check.luau   (run from the crack-a-portal folder)
-- Compiles every .luau file in src/ with the real Luau compiler: catches syntax errors.
local process = require("@lune/process")
local Harness = require("./harness")

local count, errors = Harness.compileAll()
for _, e in errors do
	print("SYNTAX " .. e)
end
print(`compiled {count} files, {#errors} with errors`)
process.exit(if #errors == 0 then 0 else 1)
