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
         pcall(Reg, "(a)(b){2")  -- fails halfway through the parse, after (a) is registered
         assert.is_true((Reg("abc"):matches("abc")))
         assert.is_true((Reg("(b)\1"):matches("bb")))
      end)

      fresh(function(Reg)
         pcall(Reg, "(a)\2")
         assert.has_no.errors(function() Reg "abc" end)
      end)
   end)

   it("accepts a '%' inside a set P1-1", function()
      fresh(function(Reg)
         assert.is_true((Reg("[%]"):matches("%")))
         assert.is_true((Reg("[a%]"):matches("a")))
      end)
   end)

   it("reports an unterminated quantifier instead of overflowing the stack P1-2", function()
      fresh(function(Reg)
         for _, pattern in ipairs { "[a]{2", "(a){2", "[a]{2,", "(a){,3" } do
            local ok, err = pcall(Reg, pattern)
            assert.is_false(ok, pattern)
            assert.not_matches("stack overflow", tostring(err), 1, true)
            assert.matches("quantifier", tostring(err), 1, true)
         end
      end)
   end)

   it("accepts an empty group P1-3", function()
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

   it("accepts an empty pattern P1-5", function()
      fresh(function(Reg)
         assert.is_true((Reg(""):matches("")))
         assert.is_false((Reg(""):matches("a")))
         assert.is_true((Reg(nil):matches("")))
      end)
   end)

   it("rejects unbalanced parentheses and brackets P2-2", function()
      fresh(function(Reg)
         for _, pattern in ipairs { "(ab", "ab)", "[ab", "ab]" } do
            assert.has_error(function() Reg(pattern) end, nil, pattern)
         end
      end)
   end)

   -- each case: pattern, a phrase its error message must contain
   local function rejects_all(cases)
      fresh(function(Reg)
         for _, case in ipairs(cases) do
            local ok, err = pcall(Reg, case[1])
            assert.is_false(ok, case[1] .. " should not compile")
            assert.matches(case[2], tostring(err), 1, true)
            assert.not_matches("stack overflow", tostring(err), 1, true)
         end
      end)
   end

   it("rejects a quantifier with nothing to repeat P3-2", function()
      rejects_all {
         { "*a", "nothing to repeat" }, { "+", "nothing to repeat" }, { "?x", "nothing to repeat" },
         { "{2}", "nothing to repeat" }, { "a|*b", "nothing to repeat" }, { "(*a)", "nothing to repeat" },
      }
   end)

   it("rejects a quantifier after a quantifier P3-2", function()
      rejects_all {
         { "a**", "follows another quantifier" }, { "a+*", "follows another quantifier" },
         { "a*?", "follows another quantifier" }, { "[ab]{2}+", "follows another quantifier" },
         { "(a)?{2}", "follows another quantifier" },
      }
   end)

   it("rejects malformed {n,m} counts P3-2", function()
      rejects_all {
         { "a{1,2,3}", "bad quantifier" }, { "a{1.5}", "bad quantifier" }, { "a{x}", "bad quantifier" },
         { "a{}", "quantifier" }, { "a{,}", "quantifier" }, { "a{-1}", "bad quantifier" },
      }
   end)

   it("rejects stray closing brackets and an empty set P3-2", function()
      rejects_all {
         { "a}", "unbalanced '}'" }, { "a]", "unbalanced ']'" }, { "a)", "unbalanced ')'" },
         { "(a))", "unbalanced ')'" }, { "[]", "empty set" }, { "[^]", "empty set" },
         { "[a", "missing ']'" }, { "((a)", "missing ')'" },
      }
   end)

   it("rejects a trailing escape and escaped letters or digits P3-2", function()
      rejects_all {
         { "a:", "ends with the escape" }, { "[a:", "ends with the escape" },
         { ":a", "unknown escape ':a'" }, { ":5", "unknown escape ':5'" },
         { "[:d]", "unknown escape ':d'" }, { "x:Z", "unknown escape ':Z'" },
      }
   end)

   it("names the position of the error", function()
      fresh(function(Reg)
         local _, err = pcall(Reg, "ab**")
         assert.matches("at position 4", tostring(err), 1, true)
      end)
   end)

   it("rejects a backreference inside the group it refers to P1-7", function()
      rejects_all {
         { "(a\1)", "inside the group it refers to" },
         { "((a)\1)", "inside the group it refers to" },
         { "(a\2)(b\1)", "inside the group it refers to" },
      }
   end)

   it("treats a nil subject like an empty string P3-1", function()
      fresh(function(Reg)
         assert.is_false((Reg("a"):matches(nil)))
         assert.is_true((Reg("a*"):matches(nil)))
         assert.are.same({}, h.plain(Reg("a"):findall(nil)))
         assert.are.same({}, h.collect(Reg("a"):finder(nil), 5))
         assert.are.same({ "" }, h.plain(Reg("a"):split(nil)))
         assert.are.same({ "", 0 }, { Reg("a"):find(nil) })
      end)
   end)

   it("turns a number subject or pattern into a string P3-1", function()
      fresh(function(Reg)
         assert.is_true((Reg("1"):matches(1)))
         assert.are.same({ "2", 2 }, { Reg("2"):find(123) })
         assert.are.same({ "1", "1" }, h.plain(Reg("1"):findall(101)))
         assert.is_true((Reg(123):matches("123")))
      end)
   end)

   it("rejects other subject and pattern types P3-1", function()
      fresh(function(Reg)
         local r = Reg "a"
         local cases = {
            { function() local _ = r:matches({}) end,    "bad argument #1 to 'matches' (string expected, got table)" },
            { function() local _ = r:find(true) end,     "bad argument #1 to 'find' (string expected, got boolean)" },
            { function() local _ = r:finder({}) end,     "bad argument #1 to 'finder' (string expected, got table)" },
            { function() local _ = r:findall({}) end,    "bad argument #1 to 'findall' (string expected, got table)" },
            { function() local _ = r:split({}) end,      "bad argument #1 to 'split' (string expected, got table)" },
            { function() local _ = r:find("a", "x") end, "bad argument #2 to 'find' (number expected, got string)" },
            { function() local _ = Reg({}) end,          "bad argument #1 to 'Reg' (string expected, got table)" },
            { function() local _ = Reg.new(true) end,    "bad argument #1 to 'Reg' (string expected, got boolean)" },
         }

         for _, case in ipairs(cases) do
            local ok, err = pcall(case[1])
            assert.is_false(ok)
            assert.matches(case[2], tostring(err), 1, true)
            -- raised at the caller's line, here in this file
            assert.matches("errors_spec%.lua:%d+: ", tostring(err))
         end
      end)
   end)

   it("reports syntax errors without color codes, at the caller's line P3-8", function()
      fresh(function(Reg)
         local compilers = {
            function() local _ = Reg "*a" end,
            function() local _ = Reg.new "*a" end,
            function() local _ = Reg "(a\1)" end,   -- raised while compiling, not parsing
         }

         for _, compile in ipairs(compilers) do
            local ok, err = pcall(compile)
            assert.is_false(ok)
            err = tostring(err)
            assert.is_nil(err:find("\27", 1, true), err)
            assert.matches("^[^:]*errors_spec%.lua:%d+: ", err)
            assert.not_matches("parser.lua", err, 1, true)
         end
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
