--- Canonicalize a path by removing redundant components
local function canonicalize(path: string): string
	-- NOTE: It is fine for us to use `/` here because ZIP file names
	-- always use `/` as the path separator
	local components = string.split(path, "/")
	local result = {}
	for _, component in components do
		if component == "." then
			-- Skip current directory
			continue
		end

		if component == ".." then
			-- Traverse one upwards
			table.remove(result, #result)
			continue
		end

		-- Otherwise, add the component to the result
		table.insert(result, component)
	end

	return table.concat(result, "/")
end

--- Check if a path is absolute
local function isAbsolute(path: string): boolean
	return (string.match(path, "^/") or string.match(path, "^[a-zA-Z]:[\\/]") or string.match(path, "^//")) ~= nil
end

--- Check if a path is relative
local function isRelative(path: string): boolean
	return not isAbsolute(path)
end

return {
	canonicalize = canonicalize,
	isAbsolute = isAbsolute,
	isRelative = isRelative,
}
