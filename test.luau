local fs = require("@lune/fs")
local zip = require("./lib")

local file = fs.readFile("test.zip")
local reader = zip.load(buffer.fromstring(file))

print("Directory structure:")
reader:walk(function(entry, depth)
    local prefix = string.rep("  ", depth)
    local suffix = if not entry.isDirectory then string.format(" (%d bytes)", entry.size) else ""
    print(prefix .. entry.name .. suffix)
end)

print("\nContents of /lib/:")
local assets = reader:listDirectory("/lib/")
for _, entry in ipairs(assets) do
    print(entry.name, entry.isDirectory and "DIR" or entry.size)
end

local configEntry = reader:findEntry("config.json")
if configEntry then
    local content = reader:extract(configEntry)
    print("\nConfig file size:", buffer.len(content))
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
