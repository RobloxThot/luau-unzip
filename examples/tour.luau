local fs = require("@lune/fs")
local zip = require("../lib")
local asciitable = require("../luau_packages/asciitable")

local file = fs.readFile("tests/data/files_and_dirs.zip")
local reader = zip.load(buffer.fromstring(file))

--- Transforms a tree of recursive `{ [string]: EntryData }` to a recursive tree of
--- `{ [string]: string }`
local function formatTree(tree: Tree): Tree<string>
	local result: Tree<string> = {}
	for key, value in tree do
		if typeof(value) == "table" and not value.size then
			-- Directory, recurse
			result[key] = formatTree(value :: Tree)
			continue
		end

		-- File, format the value
		local fileEntry = value :: EntryData
		local content = reader:extract(assert(reader:findEntry(fileEntry.path)), { type = "text" }) :: string
		local truncContents = content:gsub("\n", ""):sub(1, 100)

		result[key] = string.format(
			"(%d bytes), attrs: 0x%x, content: %s",
			fileEntry.size,
			fileEntry.attributes,
			truncContents .. (if #content > 100 then "..." else "")
		)
	end

	return result
end

local tree: Tree = {}
type Tree<T = EntryData> = { [string]: T | Tree<T> }
type EntryData = {
	path: string,
	size: number,
	attributes: number,
	content: string,
}

-- Create a tree of entries by recursively walking the ZIP
reader:walk(function(entry, depth)
	local current = tree
	local parts = string.split(entry:getPath(), "/")

	if #parts == 1 and parts[1] == "" then
		-- Skip root directory
		return
	end

	-- Build the directory tree
	for i = 1, #parts - 1 do
		local part = parts[i]
		if part ~= "" then
			if not current[part] then
				current[part] = {}
			end
			current = current[part] :: { [string]: EntryData }
		end
	end

	-- Add the file or directory entry
	local name = parts[#parts]
	if name ~= "" then
		if entry.isDirectory then
			current[name] = {}
		else
			current[name] = {
				path = entry:getPath(),
				size = entry.size,
				attributes = entry.attributes,
				content = reader:extract(entry, { type = "text" }) :: string,
			}
		end
	end
end)

-- Format the tree and print it
local formattedTree = formatTree({ ["/"] = tree })
print(asciitable.tree("Directory structure:", formattedTree))

-- List the children of the root directory
local children = reader:listDirectory("/")
local formattedChildren: { [string]: string } = {}
for _, entry in children do
	formattedChildren[entry.name] = `{if entry.isDirectory then "DIR" else "FILE"} ({entry.method})`
end
print(asciitable.tree("\nChildren of `/`:", formattedChildren))

-- Get archive statistics
local stats = reader:getStats()
print("\nArchive stats:")
print("Files:", stats.fileCount)
print("Directories:", stats.dirCount)
print("Total size:", stats.totalSize, "bytes")
