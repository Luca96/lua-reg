local Reg = require "luareg"
local h = require "helpers"
local fresh = h.fresh

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
      fresh(function(Reg)
         assert.has_error(function() Reg "(a)\2" end)
      end)
   end)

   it("compiles correct regexes after a failed one", function()
      fresh(function(Reg)
         pcall(Reg, "(a)\2")
         assert.is_true((Reg("(b)"):matches("b")))
         assert.is_true((Reg("(b)\1"):matches("bb")))
      end)
   end)

   it("compiles the very next regex correctly after a failed one P0-1", function()
      fresh(function(Reg)
         pcall(Reg, "(a)\2")
         assert.is_true((Reg("(b)\1"):matches("bb")))
      end)

      fresh(function(Reg)
         pcall(Reg, "a()b")  -- crashes halfway through the parse (P1-3)
         assert.is_true((Reg("abc"):matches("abc")))
         assert.is_true((Reg("(b)\1"):matches("bb")))
      end)

      fresh(function(Reg)
         pcall(Reg, "(a)\2")
         assert.has_no.errors(function() Reg "abc" end)
      end)
   end)

   it("accepts a '%' inside a set P1-1 #knownbug", function()
      fresh(function(Reg)
         assert.is_true((Reg("[%]"):matches("%")))
         assert.is_true((Reg("[a%]"):matches("a")))
      end)
   end)

   it("reports an unterminated quantifier instead of overflowing the stack P1-2 #knownbug", function()
      fresh(function(Reg)
         for _, pattern in ipairs { "[a]{2", "(a){2" } do
            local ok, err = pcall(Reg, pattern)
            assert.is_false(ok)
            assert.not_matches("stack overflow", tostring(err), 1, true)
         end
      end)
   end)

   it("accepts an empty group P1-3 #knownbug", function()
      fresh(function(Reg)
         assert.is_true((Reg("a()b"):matches("ab")))
      end)
   end)

   it("reports {,0} as a bad quantifier P1-4", function()
      fresh(function(Reg)
         local ok, err = pcall(Reg, "[a]{,0}")
         assert.is_false(ok)
         assert.matches("quantifier", tostring(err), 1, true)
      end)
   end)

   it("rejects a negative lower bound", function()
      fresh(function(Reg)
         assert.has_error(function() Reg "[a]{-1,2}" end)
         assert.has_error(function() Reg "(a){-1,}" end)
      end)
   end)

   it("accepts an empty pattern P1-5 #knownbug", function()
      fresh(function(Reg)
         assert.is_true((Reg(""):matches("")))
      end)
   end)

   it("rejects unbalanced parentheses and brackets P2-2 #knownbug", function()
      fresh(function(Reg)
         for _, pattern in ipairs { "(ab", "ab)", "[ab", "ab]" } do
            assert.has_error(function() Reg(pattern) end, nil, pattern)
         end
      end)
   end)

   it("treats a nil subject like an empty string P3-1 #knownbug", function()
      fresh(function(Reg)
         assert.is_false((Reg("a"):matches(nil)))
         assert.are.same({}, h.plain(Reg("a"):findall(nil)))
      end)
   end)

   it("does not leak globals P3-9", function()
      local saved = rawget(_G, "nfa")
      _G.nfa = nil

      Reg "ab"
      local leaked = rawget(_G, "nfa")

      _G.nfa = saved
      assert.is_nil(leaked)
   end)
end)
