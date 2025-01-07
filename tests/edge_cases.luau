local fs = require("@lune/fs")

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
		end)
end