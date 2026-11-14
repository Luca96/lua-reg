local Reg = require "luareg"
local h = require "helpers"

describe("errors", function()

   it("rejects a reversed range", function()
      assert.has_error(function() Reg "[z-a]" end)
   end)

   it("rejects a range across character classes", function()
      assert.has_error(function() Reg "[a-9]" end)
   end)

   it("rejects {n, m} with m < n", function()
      assert.has_error(function() Reg "[a-z]{3,1}" end)
   end)

   it("rejects {0}", function()
      assert.has_error(function() Reg "[a-z]{0}" end)
   end)

   it("rejects a backreference to a missing group", function()
      assert.has_error(function() Reg "(a)\2" end)
   end)

   it("compiles correct regexes after a failed one", function()
      pcall(Reg, "(a)\2")
      assert.is_true(h.accepts("(b)", "b"))
      assert.is_true(h.accepts("(b)\1", "bb"))
   end)

   it("accepts an empty pattern #knownbug", function()
      assert.is_true(h.accepts("", ""))
   end)

   it("does not leak globals #knownbug", function()
      local saved = rawget(_G, "nfa")
      _G.nfa = nil

      Reg "ab"
      local leaked = rawget(_G, "nfa")

      _G.nfa = saved
      assert.is_nil(leaked)
   end)
end)
