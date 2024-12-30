local Tree = {}

export type Tree = typeof(setmetatable({} :: TreeInner, { __index = Tree }))
type TreeInner = {
	table: { number }, -- len: 16 (🏳️‍⚧️❓)
	trans: { number }, -- len: 288
}

function Tree.new(): Tree
	return setmetatable(
		{
			table = table.create(16, 0),
			trans = table.create(288, 0),
		} :: TreeInner,
		{ __index = Tree }
	)
end

local Data = {}
export type Data = typeof(setmetatable({} :: DataInner, { __index = Data }))
export type DataInner = {
	source: buffer,
	sourceIndex: number,
	tag: number,
	bitcount: number,

	dest: buffer,
	destLen: number,
	
    ltree: Tree,
	dtree: Tree,
}

function Data.new(source: buffer, dest: buffer): Data
	return setmetatable(
		{
			source = source,
			sourceIndex = 0,
			tag = 0,
			bitcount = 0,
			dest = dest,
			destLen = 0,
			ltree = Tree.new(),
			dtree = Tree.new(),
		} :: DataInner,
		{ __index = Data }
	)
end

-- Static structures
local staticLengthTree = Tree.new()
local staticDistTree = Tree.new()

-- Extra bits and base tables
local lengthBits = table.create(30, 0)
local lengthBase = table.create(30, 0)
local distBits = table.create(30, 0)
local distBase = table.create(30, 0)

-- Special ordering of code length codes
-- stylua: ignore
local clcIndex = {
    16, 17, 18, 0, 8, 7, 9, 6,
    10, 5, 11, 4, 12, 3, 13, 2,
    14, 1, 15
}

local codeTree = Tree.new()
local lengths = table.create(288 + 32, 0)

local function buildBitsBase(bits: { number }, base: { number }, delta: number, first: number)
	local sum = first

	-- build bits table
	for i = 0, delta - 1 do
		bits[i] = 0
	end
	for i = 0, 29 - delta do
		bits[i + delta] = math.floor(i / delta)
	end

	-- build base table
	for i = 0, 29 do
		base[i] = sum
		sum = sum + bit32.lshift(1, bits[i])
	end
end

local function buildFixedTrees(lengthTree: Tree, distTree: Tree)
	-- build fixed length tree
	for i = 0, 6 do
		lengthTree.table[i] = 0
	end
	lengthTree.table[7] = 24
	lengthTree.table[8] = 152
	lengthTree.table[9] = 112

	for i = 0, 23 do
		lengthTree.trans[i] = 256 + i
	end
	for i = 0, 143 do
		lengthTree.trans[24 + i] = i
	end
	for i = 0, 7 do
		lengthTree.trans[24 + 144 + i] = 280 + i
	end
	for i = 0, 111 do
		lengthTree.trans[24 + 144 + 8 + i] = 144 + i
	end

	-- build fixed distance tree
	for i = 0, 4 do
		distTree.table[i] = 0
	end
	distTree.table[5] = 32

	for i = 0, 31 do
		distTree.trans[i] = i
	end
end

local offs = table.create(16, 0)

local function buildTree(t: Tree, lengths: { number }, off: number, num: number)
	-- clear code length count table
	for i = 0, 15 do
		t.table[i] = 0
	end

	-- scan symbol lengths, and sum code length counts
	for i = 0, num - 1 do
		t.table[lengths[off + i]] += 1
	end

	t.table[0] = 0

	-- compute offset table for distribution sort
	local sum = 0
	for i = 0, 15 do
		offs[i] = sum
		sum = sum + t.table[i]
	end

	-- create code->symbol translation table
	for i = 0, num - 1 do
		local len = lengths[off + i]
		if len > 0 then
			t.trans[offs[len]] = i
			offs[len] += 1
		end
	end
end

local function getBit(d: Data): number
	if d.bitcount <= 0 then
		d.tag = buffer.readu8(d.source, d.sourceIndex)
		d.sourceIndex += 1
		d.bitcount = 8
	end

	local bit = bit32.band(d.tag, 1)
	d.tag = bit32.rshift(d.tag, 1)
	d.bitcount -= 1

	return bit
end

local function readBits(d: Data, num: number?, base: number): number
	if not num then
		return base
	end

	while d.bitcount < 24 and d.sourceIndex < buffer.len(d.source) do
		d.tag = bit32.bor(d.tag, bit32.lshift(buffer.readu8(d.source, d.sourceIndex), d.bitcount))
		d.sourceIndex += 1
		d.bitcount += 8
	end

	local val = bit32.band(d.tag, bit32.rshift(0xffff, 16 - num))
	d.tag = bit32.rshift(d.tag, num)
	d.bitcount -= num

	return val + base
end

local function decodeSymbol(d: Data, t: Tree): number
	while d.bitcount < 24 and d.sourceIndex < buffer.len(d.source) do
		d.tag = bit32.bor(d.tag, bit32.lshift(buffer.readu8(d.source, d.sourceIndex), d.bitcount))
		d.sourceIndex += 1
		d.bitcount += 8
	end

	local sum, cur, len = 0, 0, 0
	local tag = d.tag

	repeat
		cur = 2 * cur + bit32.band(tag, 1)
		tag = bit32.rshift(tag, 1)
		len += 1
		sum += t.table[len]
		cur -= t.table[len]
	until cur < 0

	d.tag = tag
	d.bitcount -= len

	return t.trans[sum + cur]
end

local function decodeTrees(d: Data, lengthTree: Tree, distTree: Tree)
	local hlit = readBits(d, 5, 257)
	local hdist = readBits(d, 5, 1)
	local hclen = readBits(d, 4, 4)

	for i = 0, 18 do
		lengths[i] = 0
	end

	for i = 0, hclen - 1 do
		lengths[clcIndex[i + 1]] = readBits(d, 3, 0)
	end

	buildTree(codeTree, lengths, 0, 19)

	local num = 0
	while num < hlit + hdist do
		local sym = decodeSymbol(d, codeTree)

		if sym == 16 then
			local prev = lengths[num - 1]
			for _ = 1, readBits(d, 2, 3) do
				lengths[num] = prev
				num += 1
			end
		elseif sym == 17 then
			for _ = 1, readBits(d, 3, 3) do
				lengths[num] = 0
				num += 1
			end
		elseif sym == 18 then
			for _ = 1, readBits(d, 7, 11) do
				lengths[num] = 0
				num += 1
			end
		else
			lengths[num] = sym
			num += 1
		end
	end

	buildTree(lengthTree, lengths, 0, hlit)
	buildTree(distTree, lengths, hlit, hdist)
end

local function inflateBlockData(d: Data, lengthTree: Tree, distTree: Tree)
	while true do
		local sym = decodeSymbol(d, lengthTree)

		if sym == 256 then
			return
		end

		if sym < 256 then
			buffer.writeu8(d.dest, d.destLen, sym)
			d.destLen += 1
		else
			sym -= 257

			local length = readBits(d, lengthBits[sym], lengthBase[sym])
			local dist = decodeSymbol(d, distTree)

			local offs = d.destLen - readBits(d, distBits[dist], distBase[dist])

			for i = offs, offs + length - 1 do
				buffer.writeu8(d.dest, d.destLen, buffer.readu8(d.dest, i))
				d.destLen += 1
			end
		end
	end
end

local function inflateUncompressedBlock(d: Data)
	while d.bitcount > 8 do
		d.sourceIndex -= 1
		d.bitcount -= 8
	end

	local length = buffer.readu8(d.source, d.sourceIndex + 1)
	length = 256 * length + buffer.readu8(d.source, d.sourceIndex)

	local invlength = buffer.readu8(d.source, d.sourceIndex + 3)
	invlength = 256 * invlength + buffer.readu8(d.source, d.sourceIndex + 2)

	if length ~= bit32.bxor(invlength, 0xffff) then
		error("Invalid block length")
	end

	d.sourceIndex += 4

	for _ = 1, length do
		buffer.writeu8(d.dest, d.destLen, buffer.readu8(d.source, d.sourceIndex))
		d.destLen += 1
		d.sourceIndex += 1
	end

	d.bitcount = 0
end

local function uncompress(source: buffer): buffer
	local dest = buffer.create(buffer.len(source) * 4)
	local d = Data.new(source, dest)

	repeat
		local bfinal = getBit(d)
		local btype = readBits(d, 2, 0)

		if btype == 0 then
			inflateUncompressedBlock(d)
		elseif btype == 1 then
			inflateBlockData(d, staticLengthTree, staticDistTree)
		elseif btype == 2 then
			decodeTrees(d, d.ltree, d.dtree)
			inflateBlockData(d, d.ltree, d.dtree)
		else
			error("Invalid block type")
		end
	until bfinal == 1

	if d.destLen < buffer.len(dest) then
		local result = buffer.create(d.destLen)
		buffer.copy(result, 0, dest, 0, d.destLen)
		return result
	end

	return dest
end

-- Initialize static trees and tables
buildFixedTrees(staticLengthTree, staticDistTree)
buildBitsBase(lengthBits, lengthBase, 4, 3)
buildBitsBase(distBits, distBase, 2, 1)
lengthBits[28] = 0
lengthBase[28] = 258

return uncompress
