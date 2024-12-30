local fs = require("@lune/fs")
local zip = require("../lib")

local file = fs.readFile("test.zip")
local reader = zip.load(buffer.fromstring(file))

print("Directory structure:")
reader:walk(function(entry, depth)
    local prefix = string.rep("  ", depth)
    local suffix = if not entry.isDirectory then string.format(" (%d bytes)", entry.size) else ""
    print(prefix .. entry.name .. suffix)
end)

print("\nContents of `/`:")
local assets = reader:listDirectory("/")
for _, entry in assets do
    print(entry.name, if entry.isDirectory then "DIR" else entry.size)
    if not entry.isDirectory then
        local extracted = reader:extract(entry, { isString = true })
        print("Content:", extracted)
    end
end

-- Get archive statistics
local stats = reader:getStats()
print(string.format([[

Archive stats:
Files: %d
Directories: %d
Total size: %d bytes]],
    stats.fileCount,
    stats.dirCount,
    stats.totalSize
))
