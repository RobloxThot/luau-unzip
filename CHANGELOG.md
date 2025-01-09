# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added
- `ZipEntry` now has a `versionMadeBy` field which includes information about the host system and version of the ZIP file
- `ZipEntry` now has a `compressedSize` field which indicates the size of the compressed data
- Added method `ZipEntry:compressionEfficiency` to return compression efficiency in the form of a percentage
- Added method `ZipEntry:unixMode` to parse and extract unix mode information from external file attributes
- Added methods to handle path safety and sanitization were added to `ZipEntry`: 
```luau
-- NOTE: All paths returned by methods use `/` as the path separator

-- Returns the path if it is safe, otherwise returns nil
entry:getSafePath()

-- Converts a potentially unsafe path to a safe one, possibly losing some information
entry:sanitizePath()
```
### Changed
- Renamed `isAscii` field for `ZipEntry` to `isText`
- Renamed `isString` option for `ZipReader:extract` to `isText`
### Fixed
- Removed any typecast for internal decompression utilities due to `table.freeze` interfering with types

## [0.0.1] - 2025-01-07
### Changed
- Improved output format for `tour` example
- Relaxed MSLV requirement to 0.593
- Refactored utilities as separate modules
- Improved test coverage with more edge case tests

## [0.0.1-rc.2] - 2025-01-06
### Added
- Support for symlinks - checking whether an entry is a symlink and following symlinks
```luau
local unzip = require("unzip")

local zip = unzip.load(...)

-- Given a ZIP of the structure: path/to/symlink -> path/to/target
local entry = zip:findEntry("path/to/symlink")

-- The following will return "path/to/target"
local targetPath = zip:extract(entry, { isString = true, followSymlinks = false })
print("Symlink target:", targetPath)

-- The following will return the contents of "path/to/target"
local followedTargetContents = zip:extract(entry, { isString = true, followSymlinks = true })
local targetContents = zip:extract(zip:findEntry("path/to/target"), { isString = true })

-- Following the symlink should give us the contents of the target file
assert(targetContents == followedTargetContents, "Symlink must lead to the target file!")
```
- Added the `isAscii` field and automatic compressed data type detection when the `isString` option is not provided using internal file attributes
### Fixed
- Fixed a bug where ZIPs that contained an end of central directory record with a misaligned comment window would not be correctly read
- Fixed an underflow while trying to align the byte boundary while decompressing uncompressed inflate blocks

## [0.0.1-rc.1] - 2025-01-06
### Added
- Initial library release :tada:

[unreleased]: https://github.com/0x5eal/luau-unzip/commits/HEAD
[0.0.1]: https://pesde.dev/packages/0x5eal/unzip/0.0.1/any
[0.0.1-rc.2]: https://pesde.dev/packages/0x5eal/unzip/0.0.1-rc.2/any
[0.0.1-rc.1]: https://pesde.dev/packages/0x5eal/unzip/0.0.1-rc.1/any

