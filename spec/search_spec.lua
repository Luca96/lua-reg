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
         assert.are.same({ "", 0 }, { digits:find(nil) })
      end)

      it("returns the leftmost match when another one ends the string P2-9", function()
         assert.are.same({ "1", 2 }, { digits:find("a1b2") })
      end)

      it("finds a match in a one-character string P2-9", function()
         assert.are.same({ "7", 1 }, { digits:find("7") })
      end)

      it("returns the longest match at the leftmost start", function()
         assert.are.same({ "ab", 1 }, { Reg("a|ab"):find("abc") })
         assert.are.same({ "aaa", 2 }, { Reg("a+"):find("baaab") })
         assert.are.same({ "abab", 3 }, { Reg("(ab)+"):find("xxababa") })
      end)

      it("reports empty matches", function()
         assert.are.same({ "", 1 }, { Reg("a*"):find("bbb") })
         assert.are.same({ "aa", 2 }, { Reg("a*"):find("baa", 2) })
         assert.are.same({ "", 1 }, { Reg(""):find("abc") })
         assert.are.same({ "", 1 }, { Reg("a*"):find("") })
      end)

      it("starts at init", function()
         assert.are.same({ "2", 4 }, { digits:find("a1b2", 3) })
         assert.are.same({ "34", 3 }, { digits:find("1234", 3) })
         assert.are.same({ "", 0 }, { digits:find("a1b", 3) })
         assert.are.same({ "", 4 }, { Reg("x*"):find("abc", 4) })
         assert.are.same({ "", 0 }, { Reg("x*"):find("abc", 5) })
         assert.are.same({ "1", 1 }, { digits:find("1", -3) })
      end)

      it("counts a negative init from the end, like string.find P3-1", function()
         assert.are.same({ "b", 4 }, { Reg("b"):find("abab", -2) })
         assert.are.same({ "2", 4 }, { digits:find("a1b2", -1) })
         assert.are.same({ "1", 2 }, { digits:find("a1b2", -3) })
         assert.are.same({ "", 3 }, { Reg("x*"):find("abc", -1) })
         assert.are.same({ "b", 4 }, { Reg("b"):find("abab", "3") })  -- a numeric string
      end)

      it("is linear in the length of the subject", function()
         -- a per-start scan would rerun a* from every one of the 20000 positions
         local s = ("a"):rep(20000)
         local t = os.clock()
         assert.are.same({ "", 0 }, { Reg("a*b"):find(s) })
         assert.is_true(os.clock() - t < 5, "find took too long")
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

      it("returns the matches in order P2-9", function()
         assert.are.same({ "1", "22", "333" }, plain(digits:findall("a1b22c333")))
         assert.are.same({ "7" }, plain(digits:findall("7")))
      end)

      it("includes empty matches, but not right after a match (as string.gmatch)", function()
         assert.are.same({ "", "aaa", "" }, plain(Reg("a*"):findall("baaac")))
         assert.are.same({ "", "", "" }, plain(Reg(""):findall("ab")))
         assert.are.same({ "aa" }, plain(Reg("a*"):findall("aa")))
      end)
   end)

   describe(":split", function()
      it("splits the string around the matches", function()
         assert.are.same({ "a", "b", "c" }, plain(digits:split("a1b22c")))
         assert.are.same({ "abc" }, plain(digits:split("abc")))
         assert.are.same({ "a", "b", "c" }, plain(Reg(", "):split("a, b, c")))
      end)

      it("keeps empty pieces", function()
         assert.are.same({ "", "a" }, plain(digits:split("12a")))
         assert.are.same({ "a", "" }, plain(digits:split("a12")))
      end)

      it("drops empty pieces with remove_empty", function()
         assert.are.same({ "a", "b" }, plain(digits:split("1a22b", true)))
      end)

      it("splits at every match when one ends the string P2-9", function()
         assert.are.same({ ", ", ", " }, plain(digits:split("1, 2, 3", true)))
         assert.are.same({ "", ", ", ", ", "" }, plain(digits:split("1, 2, 3")))
      end)

      it("splits around empty matches too", function()
         assert.are.same({ "", "b", "c", "" }, plain(Reg("a*"):split("baaac")))
         assert.are.same({ "", "a", "b", "" }, plain(Reg(""):split("ab")))
      end)
   end)

   describe(":finder", function()
      it("first returns the first match", function()
         local iter = Reg("a"):finder("bab")
         assert.are.same({ "a", 2 }, { iter() })
      end)

      it("iterates over every match with indices into the original string P2-8", function()
         assert.are.same({ { "12", 3 }, { "345", 7 } }, h.collect(digits:finder("ab12cd345ef"), 10))
         assert.are.same({ { "a", 2 } }, h.collect(Reg("a"):finder("bab"), 10))
      end)

      it("returns the same matches as findall, empty ones included", function()
         assert.are.same({ { "", 1 }, { "aaa", 2 }, { "", 6 } }, h.collect(Reg("a*"):finder("baaac"), 10))
      end)

      it("ends: a for-in loop terminates", function()
         local n = 0
         for _ in digits:finder("1 22 333") do n = n + 1 end
         assert.are.equal(3, n)
      end)
   end)

   describe("on random patterns", function()
      -- deterministic LCG, independent of math.random
      local seed = 2026
      local function rnd(k)
         seed = (seed * 1103515245 + 12345) % 2147483648
         return seed % k + 1
      end
      local function pick(t) return t[rnd(#t)] end

      local quants = { "", "", "*", "+", "?", "{2}", "{1,2}", "{0,2}", "{2,}" }
      local expr
      local function atom(d)
         local k = rnd(d > 2 and 3 or 5)
         if k == 1 then return pick { "a", "b", "c" } .. pick(quants) end
         if k == 2 then return pick { "[ab]", "[^a]", "[bc]" } .. pick(quants) end
         if k == 3 then return pick { "a", "b" } end
         if k == 4 then return "(" .. expr(d + 1) .. ")" .. pick(quants) end
         return "(" .. expr(d + 1) .. "|" .. expr(d + 1) .. ")" .. pick(quants)
      end
      function expr(d) local s = "" for _ = 1, rnd(3) do s = s .. atom(d) end return s end

      local function subject()
         local s = ""
         for _ = 1, rnd(8) - 1 do s = s .. pick { "a", "b", "c", "d" } end
         return s
      end

      -- the leftmost-longest match, by trying every substring
      local function brute_find(r, s, init)
         for i = init, #s + 1 do
            for j = #s, i - 1, -1 do
               if r:matches(s:sub(i, j)) then return s:sub(i, j), i end
            end
         end
         return "", 0
      end

      it("find agrees with a brute-force leftmost-longest search", function()
         for _ = 1, 150 do
            local p = expr(1)
            local r = Reg(p)
            for _ = 1, 8 do
               local s = subject()
               local init = rnd(#s + 1)
               assert.are.same({ brute_find(r, s, init) }, { r:find(s, init) },
                  ("%q on %q from %d"):format(p, s, init))
            end
         end
      end)

      it("matches(s) is true exactly when find(s) returns all of s at 1", function()
         for _ = 1, 150 do
            local p = expr(1)
            local r = Reg(p)
            for _ = 1, 8 do
               local s = subject()
               local m, i = r:find(s)
               assert.are.equal((r:matches(s)), m == s and i == 1, ("%q on %q"):format(p, s))
            end
         end
      end)
   end)
end)
