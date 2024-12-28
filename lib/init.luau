local SIGNATURES = table.freeze({
	LOCAL_FILE = 0x04034b50,
	CENTRAL_DIR = 0x02014b50,
	END_OF_CENTRAL_DIR = 0x06054b50,
})

-- TODO: ERROR HANDLING !!

local ZipEntry = {}
export type ZipEntry = typeof(setmetatable({} :: ZipEntryInner, { __index = ZipEntry }))
type ZipEntryInner = {
	name: string,
	size: number,
	offset: number,
	timestamp: number,
	crc: number,
	isDirectory: boolean,
	parent: ZipEntry?,
	children: { ZipEntry },
	getPath: (ZipEntry) -> string,
}

function ZipEntry.new(name, size, offset, timestamp, crc): ZipEntry
	return setmetatable(
		{
			name = name,
			size = size,
			offset = offset,
			timestamp = timestamp,
			crc = crc,
			isDirectory = string.sub(name, -1) == "/",
			parent = nil,
			children = {},
		} :: ZipEntryInner,
		{ __index = ZipEntry }
	)
end

function ZipEntry.getPath(self: ZipEntry): string
	local path = self.name
	local current = self.parent

	while current and current.name ~= "/" do
		path = current.name .. path
		current = current.parent
	end

	return path
end

local ZipReader = {}
export type ZipReader = typeof(setmetatable({} :: ZipReaderInner, { __index = ZipReader }))
type ZipReaderInner = {
	data: buffer,
	entries: { ZipEntry },
	directories: { [string]: ZipEntry },
	root: ZipEntry,
}

function ZipReader.new(data): ZipReader
	local root = ZipEntry.new("/", 0, 0, 0, 0)
	root.isDirectory = true

	local this = setmetatable(
		{
			data = data,
			entries = {},
			directories = {},
			root = root,
		} :: ZipReaderInner,
		{ __index = ZipReader }
	)

	this:parseCentralDirectory()
	this:buildDirectoryTree()
	return this
end

function ZipReader.parseCentralDirectory(self: ZipReader): ()
	local bufSize = buffer.len(self.data)
	local pos = bufSize - 22

	while pos > 0 do
		if buffer.readu32(self.data, pos) == SIGNATURES.END_OF_CENTRAL_DIR then
			break
		end
		pos = pos - 1
	end

	if pos < 0 then
		error("Invalid ZIP file: End of Central Directory not found")
	end

	local cdOffset = buffer.readu32(self.data, pos + 16)
	local cdEntries = buffer.readu16(self.data, pos + 10)

	pos = cdOffset
	for i = 1, cdEntries do
		if buffer.readu32(self.data, pos) ~= SIGNATURES.CENTRAL_DIR then
			error("Invalid central directory header")
		end

		local nameLength = buffer.readu16(self.data, pos + 28)
		local extraLength = buffer.readu16(self.data, pos + 30)
		local commentLength = buffer.readu16(self.data, pos + 32)
		local timestamp = buffer.readu32(self.data, pos + 12)
		local crc = buffer.readu32(self.data, pos + 16)
		local size = buffer.readu32(self.data, pos + 24)
		local offset = buffer.readu32(self.data, pos + 42)

		local nameBuffer = buffer.create(nameLength)
		buffer.copy(nameBuffer, 0, self.data, pos + 46, nameLength)
		local name = buffer.tostring(nameBuffer)

		local entry = ZipEntry.new(name, size, offset, timestamp, crc)
		table.insert(self.entries, entry)

		pos = pos + 46 + nameLength + extraLength + commentLength
	end
end

function ZipReader.buildDirectoryTree(self: ZipReader): ()
	for _, entry in self.entries do
		local parts = {}
		for part in string.gmatch(entry.name, "([^/]+)/?") do
			table.insert(parts, part)
		end

		local current = self.root
		local path = ""

		for i, part in parts do
			path ..= part
			if i < #parts then
				if not self.directories[path] then
					local dir = ZipEntry.new(path, 0, 0, entry.timestamp, 0)
					dir.isDirectory = true
					dir.parent = current

					self.directories[path] = dir
					table.insert(current.children, dir)
				end

				current = self.directories[path]
				continue
			end

			entry.parent = current
			table.insert(current.children, entry)
		end
	end
end

function ZipReader.findEntry(self: ZipReader, path: string): ZipEntry
	if path == "/" then
		return self.root
	end

	path = string.gsub(path, "^/", ""):gsub("/$", "")
	for _, entry in self.entries do
		if string.gsub(entry.name, "/$", "") == path then
			return entry
		end
	end

	return self.directories[path]
end

function ZipReader.extract(self: ZipReader, entry: ZipEntry): buffer
	if entry.isDirectory then
		error("Cannot extract directory")
	end

	local pos = entry.offset
	if buffer.readu32(self.data, pos) ~= SIGNATURES.LOCAL_FILE then
		error("Invalid local file header")
	end

	local nameLength = buffer.readu16(self.data, pos + 26)
	local extraLength = buffer.readu16(self.data, pos + 28)

	pos = pos + 30 + nameLength + extraLength

	local content = buffer.create(entry.size)
	buffer.copy(content, 0, self.data, pos, entry.size)

	-- TODO: decompress data! `buffer.readu16(self.data, entry.offset + 8)`
	-- will give the compression method, where method id 8 corresponds to
	-- deflate

	return content
end

function ZipReader.extractDirectory(self: ZipReader, path: string): { [string]: buffer }
	local files = {}
	path = string.gsub(path, "^/", "")

	for _, entry in self.entries do
		if not entry.isDirectory and string.sub(entry.name, 1, #path) == path then
			files[entry.name] = self:extract(entry)
		end
	end

	return files
end

function ZipReader.listDirectory(self: ZipReader, path: string): { ZipEntry }
	local entry = self:findEntry(path)
	if not entry or not entry.isDirectory then
		error("Not a directory")
	end

	return entry.children
end

function ZipReader.walk(self: ZipReader, callback: (entry: ZipEntry, depth: number) -> ()): ()
	local function walkEntry(entry: ZipEntry, depth: number)
		callback(entry, depth)

		for _, child in entry.children do
			-- ooo spooky recursion... blame this if shit go wrong
			walkEntry(child, depth + 1)
		end
	end

	walkEntry(self.root, 0)
end

export type ZipStatistics = { fileCount: number, dirCount: number, totalSize: number }
function ZipReader.getStats(self: ZipReader): ZipStatistics
	local stats: ZipStatistics = {
		fileCount = 0,
		dirCount = 0,
		totalSize = 0,
	}

	for _, entry in self.entries do
		if entry.isDirectory then
			stats.dirCount = stats.dirCount + 1
			continue
		end

		stats.fileCount = stats.fileCount + 1
		stats.totalSize = stats.totalSize + entry.size
	end

	return stats
end

return {
	load = function(data)
		return ZipReader.new(data)
	end,
}
