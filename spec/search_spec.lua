local Reg = require "luareg"
local h = require "helpers"
local plain = h.plain

describe("searching", function()
   local digits = Reg "[0-9]+"

   describe(":find", function()
      it("returns the first match and its start index", function()
         assert.are.same({ "12", 2 }, { digits:find("x12y") })
         assert.are.same({ "12", 1 }, { digits:find("12") })
         assert.are.same({ "a", 2 }, { Reg("a"):find("ba") })
      end)

      it("returns '', 0 without a match", function()
         assert.are.same({ "", 0 }, { digits:find("abc") })
         assert.are.same({ "", 0 }, { digits:find("") })
      end)

      it("returns the leftmost match when another one ends the string #knownbug", function()
         assert.are.same({ "1", 2 }, { digits:find("a1b2") })
      end)

      it("finds a match in a one-character string #knownbug", function()
         assert.are.same({ "7", 1 }, { digits:find("7") })
      end)
   end)

   describe(":findall", function()
      it("returns an enhanced table", function()
         assert.is_function(digits:findall("1").append)
      end)

      it("returns every match", function()
         assert.are.same({ "12" }, plain(digits:findall("12")))
         assert.are.same({}, plain(digits:findall("abc")))
      end)

      it("returns the matches in order #knownbug", function()
         assert.are.same({ "1", "22", "333" }, plain(digits:findall("a1b22c333")))
      end)
   end)

   describe(":split", function()
      it("splits the string around the matches", function()
         assert.are.same({ "a", "b", "c" }, plain(digits:split("a1b22c")))
         assert.are.same({ "abc" }, plain(digits:split("abc")))
      end)

      it("keeps empty pieces", function()
         assert.are.same({ "", "a" }, plain(digits:split("12a")))
      end)

      it("drops empty pieces with remove_empty", function()
         assert.are.same({ "a", "b" }, plain(digits:split("1a22b", true)))
      end)

      it("splits at every match when one ends the string #knownbug", function()
         assert.are.same({ ", ", ", " }, plain(digits:split("1, 2, 3", true)))
      end)
   end)

   describe(":finder", function()
      it("first returns the first match", function()
         local iter = Reg("a"):finder("bab")
         assert.are.same({ "a", 2 }, { iter() })
      end)

      it("iterates over every match #knownbug", function()
         assert.are.same({ { "12", 3 }, { "345", 7 } }, h.collect(digits:finder("ab12cd345ef"), 10))
      end)
   end)
end)
