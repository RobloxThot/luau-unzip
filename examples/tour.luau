local fs = require("@lune/fs")
local stdio = require("@lune/stdio")
local zip = require("../lib")

local file = fs.readFile("test.zip")
local reader = zip.load(buffer.fromstring(file))

print("Directory structure:")
reader:walk(function(entry, depth)
	local prefix = string.rep("  ", depth)
	local suffix = if not entry.isDirectory
		then string.format(" (%d bytes), content: %s", entry.size, stdio.format(reader:extract(entry) :: string))
		else ""
	print(prefix .. entry.name .. suffix)
end)

print("\Children of `/`:")
local assets = reader:listDirectory("/")
for _, entry in assets do
	print(`    {entry.name} - {if entry.isDirectory then "DIR" else "FILE"}`)
end

-- Get archive statistics
local stats = reader:getStats()
print("\nArchive stats:")
print("Files:", stats.fileCount)
print("Directories:", stats.dirCount)
print("Total size:", stats.totalSize, "bytes")