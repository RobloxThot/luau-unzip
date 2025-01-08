local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local frktest = require("../lune_packages/frktest")
local check = frktest.assert.check

local ZipReader = require("../lib")

return function(test: typeof(frktest.test))
	test.suite("Edge case tests", function()
		test.case("Handles misaligned comment properly", function()
			local data = fs.readFile("tests/data/misaligned_comment.zip")
			local zip = ZipReader.load(buffer.fromstring(data))

			check.equal(zip.comment, "short.")
		end)

		test.case("Follows symlinks correctly", function()
			-- TODO: More test files with symlinks

			local data = fs.readFile("tests/data/pandoc_soft_links.zip")
			local zip = ZipReader.load(buffer.fromstring(data))

			local entry = assert(zip:findEntry("/pandoc-3.2-arm64/bin/pandoc-lua"))
			assert(entry:isSymlink(), "Entry type must be a symlink")

			local targetPath = zip:extract(entry, { isString = true }) :: string
			check.equal(targetPath, "pandoc")

			local bin = zip:extract(entry, { isString = false, followSymlinks = true }) :: buffer
			local expectedBin =
				process.spawn("unzip", { "-p", "tests/data/pandoc_soft_links.zip", "pandoc-3.2-arm64/bin/pandoc" })
			check.is_true(expectedBin.ok)

			-- Compare hashes instead of the entire binary to improve speed and not print out
			-- the entire binary data in case there's a mismatch
			check.equal(serde.hash("blake3", bin), serde.hash("blake3", expectedBin.stdout))
		end)
	end)
end
