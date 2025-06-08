# luau-unzip

<a href="https://lune-org.github.io/docs"><img alt="Lune" src="https://raw.githubusercontent.com/0x5eal/semver-luau/refs/heads/main/.lune/assets/powered-by-lune.svg" /></a>

A Luau library to unzip and extract files from ZIP archives. The implementation is based on the [PKZip APPNOTE v6.3.9](https://www.pkware.com/documents/APPNOTE/APPNOTE-6.3.9.TXT).

## Features
- Extract files from ZIP archives.
- Supports `INFLATE` and `STORE` decompression methods.
- Traverse and list archive contents.
- Retrieve archive statistics (file count, directory count, total size) and metadata.

## Usage

```luau
local zip = loadstring(game:HttpGet("https://raw.githubusercontent.com/RobloxThot/luau-unzip/main/lib/init.luau", true))()

-- Read the ZIP file
local file = readFile("test.zip")

-- Load the ZIP archive
local reader = zip.load(buffer.fromstring(file))

-- Print directory structure
print("Directory structure:")
reader:walk(function(entry, depth)
    local prefix = string.rep("  ", depth)
    local suffix = if not entry.isDirectory
        then string.format(" (%d bytes), content: %s", entry.size, reader:extract(entry, { type = "text" }) :: string)
        else ""
    print(prefix .. entry.name .. suffix)
end)

-- List children of root directory
print("\nChildren of `/`:")
local assets = reader:listDirectory("/")
for _, entry in assets do
    print(string.format("    %s - %s (%s)", entry.name, if entry.isDirectory then "DIR" else "FILE", entry.method))
end

-- Get archive statistics
local stats = reader:getStats()
print("\nArchive stats:")
print("Files:", stats.fileCount)
print("Directories:", stats.dirCount)
print("Total size:", stats.totalSize, "bytes")
```

## License
This project is licensed under the [MIT] license.

[MIT]: https://compeydev.mit-license.org
