local inflate = require("./inflate")
local crc32 = require("./crc")

-- Little endian constant signatures used in the ZIP file format
local SIGNATURES = table.freeze({
	-- Marks the beginning of each file in the ZIP
	LOCAL_FILE = 0x04034b50,
	-- Marks the start of an data descriptor
	DATA_DESCRIPTOR = 0x08074b50,
	-- Marks entries in the central directory
	CENTRAL_DIR = 0x02014b50,
	-- Marks the end of the central directory
	END_OF_CENTRAL_DIR = 0x06054b50,
})

type CrcValidationOptions = {
	skip: boolean,
	expected: number,
}

local function validateCrc(decompressed: buffer, validation: CrcValidationOptions)
	-- Unless skipping validation is requested, we verify the checksum
	if not validation.skip then
		local computed = crc32(decompressed)
		assert(
			validation.expected == computed,
			`Validation failed; CRC checksum does not match: {string.format("%x", computed)} ~= {string.format(
				"%x",
				computed
			)} (expected ~= got)`
		)
	end
end

local DECOMPRESSION_ROUTINES: { [number]: (buffer, number, CrcValidationOptions) -> buffer } = table.freeze({
	-- `STORE` decompression method - No compression
	[0x00] = function(buf, _, validation)
		validateCrc(buf, validation)
		return buf
	end,

	-- `DEFLATE` decompression method - Compressed raw deflate chunks
	[0x08] = function(buf, uncompressedSize, validation)
		-- FIXME: Why is uncompressedSize not getting inferred correctly although it
		-- is typed?
		local decompressed = inflate(buf, uncompressedSize :: any)
		validateCrc(decompressed, validation)
		return decompressed
	end,
})

-- TODO: ERROR HANDLING!

local ZipEntry = {}
export type ZipEntry = typeof(setmetatable({} :: ZipEntryInner, { __index = ZipEntry }))
-- stylua: ignore
type ZipEntryInner = {
    name: string,           -- File path within ZIP, '/' suffix indicates directory
    size: number,           -- Uncompressed size in bytes
    offset: number,         -- Absolute position of local header in ZIP
    timestamp: number,      -- MS-DOS format timestamp
    crc: number,            -- CRC32 checksum of uncompressed data
    isDirectory: boolean,   -- Whether the entry is a directory or not
    parent: ZipEntry?,      -- The parent of the current entry, nil for root
    children: { ZipEntry }, -- The children of the entry
}

function ZipEntry.new(name: string, size: number, offset: number, timestamp: number, crc: number): ZipEntry
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
-- stylua: ignore
type ZipReaderInner = {
	data: buffer,                         -- The buffer containing the raw bytes of the ZIP
	entries: { ZipEntry },                -- The decoded entries present
	directories: { [string]: ZipEntry },  -- The directories and their respective entries 
	root: ZipEntry,                       -- The entry of the root directory
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
	-- ZIP files are read from the end, starting with the End of Central Directory record
	-- The EoCD is at least 22 bytes and contains pointers to the rest of the ZIP structure
	local bufSize = buffer.len(self.data)
	local pos = bufSize - 22

	-- Search backwards for the EoCD signature
	while pos > 0 do
		-- Read 4 bytes as uint32 in little-endian format
		if buffer.readu32(self.data, pos) == SIGNATURES.END_OF_CENTRAL_DIR then
			break
		end
		pos -= 1
	end

	-- Central Directory offset is stored 16 bytes into the EoCD record
	local cdOffset = buffer.readu32(self.data, pos + 16)
	-- Number of entries is stored 10 bytes into the EoCD record
	local cdEntries = buffer.readu16(self.data, pos + 10)

	-- Process each entry in the Central Directory
	pos = cdOffset
	for i = 1, cdEntries do
		-- Central Directory Entry format:
		-- Offset  Bytes  Description
		-- ------------------------------------------------
		-- 0       4      Central directory entry signature
		-- 8       2      General purpose bitflags
		-- 12      4      Last mod time/date
		-- 28      2      File name length (n)
		-- 30      2      Extra field length (m)
		-- 32      2      Comment length (k)
		-- 16      4      CRC-32
		-- 24      4      Uncompressed size
		-- 42      4      Local header offset
		-- 46      n      File name
		-- 46+n    m      Extra field
		-- 46+n+m  k      Comment

		local _bitflags = buffer.readu16(self.data, pos + 8)
		local nameLength = buffer.readu16(self.data, pos + 28)
		local extraLength = buffer.readu16(self.data, pos + 30)
		local commentLength = buffer.readu16(self.data, pos + 32)
		local timestamp = buffer.readu32(self.data, pos + 12)
		local crc = buffer.readu32(self.data, pos + 16)
		local size = buffer.readu32(self.data, pos + 24)
		local offset = buffer.readu32(self.data, pos + 42)
		local name = buffer.readstring(self.data, pos + 46, nameLength)

		local entry = ZipEntry.new(name, size, offset, timestamp, crc)
		table.insert(self.entries, entry)

		pos = pos + 46 + nameLength + extraLength + commentLength
	end
end

function ZipReader.buildDirectoryTree(self: ZipReader): ()
	-- Sort entries to process directories first; I could either handle
	-- directories and files in separate passes over the entries, or sort
	-- the entries so I handled the directories first -- I decided to do
	-- the latter
	table.sort(self.entries, function(a, b)
		if a.isDirectory ~= b.isDirectory then
			return a.isDirectory
		end
		return a.name < b.name
	end)

	for _, entry in self.entries do
		local parts = {}
		-- Split entry path into individual components
		-- e.g. "folder/subfolder/file.txt" -> {"folder", "subfolder", "file.txt"}
		for part in string.gmatch(entry.name, "([^/]+)/?") do
			table.insert(parts, part)
		end

		-- Start from root directory
		local current = self.root
		local path = ""

		-- Process each path component
		for i, part in parts do
			path ..= part

			if i < #parts or entry.isDirectory then
				-- Create missing directory entries for intermediate paths
				if not self.directories[path] then
					if entry.isDirectory and i == #parts then
						-- Existing directory entry, reuse it
						self.directories[path] = entry
					else
						-- Create new directory entry for intermediate paths or undefined
						-- parent directories in the ZIP
						local dir = ZipEntry.new(path .. "/", 0, 0, entry.timestamp, 0)
						dir.isDirectory = true
						dir.parent = current
						self.directories[path] = dir
					end

					-- Track directory in both lookup table and parent's children
					table.insert(current.children, self.directories[path])
				end

				-- Move deeper into the tree
				current = self.directories[path]
				continue
			end

			-- Link file entry to its parent directory
			entry.parent = current
			table.insert(current.children, entry)
		end
	end
end

function ZipReader.findEntry(self: ZipReader, path: string): ZipEntry?
	if path == "/" then
		-- If the root directory's entry was requested we do not
		-- need to do any additional work
		return self.root
	end

	-- Normalize path by removing leading and trailing slashes
	-- This ensures consistent lookup regardless of input format
	-- e.g., "/folder/file.txt/" -> "folder/file.txt"
	path = string.gsub(path, "^/", ""):gsub("/$", "")

	-- First check regular files and explicit directories
	for _, entry in self.entries do
		-- Compare normalized paths
		if string.gsub(entry.name, "/$", "") == path then
			return entry
		end
	end

	-- If not found, check virtual directory entries
	-- These are directories that were created implicitly
	return self.directories[path]
end

type ExtractionOptions = {
	decompress: boolean?,
	isString: boolean?,
	skipCrcValidation: boolean?,
	skipSizeValidation: boolean?,
}
function ZipReader.extract(self: ZipReader, entry: ZipEntry, options: ExtractionOptions?): buffer | string
	-- Local File Header format:
	-- Offset  Bytes  Description
	-- 0       4      Local file header signature
	-- 6       2      General purpose bitflags
	-- 8       2      Compression method (8 = DEFLATE)
	-- 14      4      CRC32 checksum
	-- 18      4      Compressed size
	-- 22      4      Uncompressed size
	-- 26      2      File name length (n)
	-- 28      2      Extra field length (m)
	-- 30      n      File name
	-- 30+n    m      Extra field
	-- 30+n+m  -      File data

	if entry.isDirectory then
		error("Cannot extract directory")
	end

	local defaultOptions: ExtractionOptions = {
		decompress = true,
		isString = false,
		skipValidation = false,
	}

	-- TODO: Use a `Partial` type function for this in the future!
	local optionsOrDefault: {
		decompress: boolean,
		isString: boolean,
		skipCrcValidation: boolean,
		skipSizeValidation: boolean,
	} = if options
		then setmetatable(options, { __index = defaultOptions }) :: any
		else defaultOptions

	local pos = entry.offset
	if buffer.readu32(self.data, pos) ~= SIGNATURES.LOCAL_FILE then
		error("Invalid local file header")
	end

	local bitflags = buffer.readu16(self.data, pos + 6)
	local crcChecksum = buffer.readu32(self.data, pos + 14)
	local compressedSize = buffer.readu32(self.data, pos + 18)
	local uncompressedSize = buffer.readu32(self.data, pos + 22)
	local nameLength = buffer.readu16(self.data, pos + 26)
	local extraLength = buffer.readu16(self.data, pos + 28)

	pos = pos + 30 + nameLength + extraLength

	if bit32.band(bitflags, 0x08) ~= 0 then
		-- The bit at offset 3 was set, meaning we did not have the file sizes
		-- and CRC checksum at the time of the creation of the ZIP. Instead, they
		-- were appended after the compressed data chunks in a data descriptor

		-- Data Descriptor format:
		-- Offset   Bytes   Description
		-- 0        0 or 4  0x08074b50 (optional signature)
		-- 0 or 4   4       CRC32 checksum
		-- 4 or 8   4       Compressed size
		-- 8 or 12  4       Uncompressed size

		-- Start at the compressed data
		local descriptorPos = pos
		while true do
			-- Try reading a u32 starting from current offset
			local leading = buffer.readu32(self.data, descriptorPos)

			if leading == SIGNATURES.DATA_DESCRIPTOR then
				-- If we find a data descriptor signature, that must mean
				-- the current offset points is the start of the descriptor
				break
			end

			if leading == entry.crc then
				-- If we find our file's CRC checksum, that means the data
				-- descriptor signature was omitted, so our chunk starts 4
				-- bytes before
				descriptorPos -= 4
				break
			end

			-- Skip to the next byte
			descriptorPos += 1
		end

		crcChecksum = buffer.readu32(self.data, descriptorPos + 4)
		compressedSize = buffer.readu32(self.data, descriptorPos + 8)
		uncompressedSize = buffer.readu32(self.data, descriptorPos + 12)
	end

	local content = buffer.create(compressedSize)
	buffer.copy(content, 0, self.data, pos, compressedSize)

	if optionsOrDefault.decompress then
		local compressionMethod = buffer.readu16(self.data, entry.offset + 8)
		local decompress = DECOMPRESSION_ROUTINES[compressionMethod]
		if decompress == nil then
			error(`Unsupported compression, ID: {compressionMethod}`)
		end

		content = decompress(content, uncompressedSize, {
			expected = crcChecksum,
			skip = optionsOrDefault.skipCrcValidation,
		})

		-- Unless skipping validation is requested, we make sure the uncompressed size matches
		assert(
			optionsOrDefault.skipSizeValidation or uncompressedSize == buffer.len(content),
			"Validation failed; uncompressed size does not match"
		)
	end

	return if optionsOrDefault.isString then buffer.tostring(content) else content
end

function ZipReader.extractDirectory(
	self: ZipReader,
	path: string,
	options: ExtractionOptions
): { [string]: buffer } | { [string]: string }
	local files: { [string]: buffer } | { [string]: string } = {}
	-- Normalize path by removing leading slash for consistent prefix matching
	path = string.gsub(path, "^/", "")

	-- Iterate through all entries to find files within target directory
	for _, entry in self.entries do
		-- Check if entry is a file (not directory) and its path starts with target directory
		if not entry.isDirectory and string.sub(entry.name, 1, #path) == path then
			-- Store extracted content mapped to full path
			files[entry.name] = self:extract(entry, options)
		end
	end

	-- Return a map of file to contents
	return files
end

function ZipReader.listDirectory(self: ZipReader, path: string): { ZipEntry }
	-- Locate the entry with the path
	local entry = self:findEntry(path)
	if not entry or not entry.isDirectory then
		-- If an entry was not found, we error
		error("Not a directory")
	end

	-- Return the children of our discovered entry
	return entry.children
end

function ZipReader.walk(self: ZipReader, callback: (entry: ZipEntry, depth: number) -> ()): ()
	-- Wrapper function which recursively calls callback for every child
	-- in an entry
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

	-- Iterate through the entries, updating stats
	for _, entry in self.entries do
		if entry.isDirectory then
			stats.dirCount += 1
			continue
		end

		stats.fileCount += 1
		stats.totalSize += entry.size
	end

	return stats
end

return {
	-- Creates a `ZipReader` from a `buffer` of ZIP data.
	load = function(data: buffer)
		return ZipReader.new(data)
	end,
}
