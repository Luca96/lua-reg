local Nfa = require "nfa"

-- nfa that accepts exactly the one-character string c
local function char(c)
   return Nfa { states = 2, edges = { [1] = { [c] = { 2 } } }, accepting = { 2 } }
end

-- the words of `words` accepted by m, in order
local function accepted(m, words)
   local out = {}

   for _, w in ipairs(words) do
      if m:compute(w) then
         out[#out + 1] = w
      end
   end

   return out
end

local words = { "", "a", "b", "ab", "ba", "aa", "aaa", "aaaa" }

describe("Nfa", function()

   describe(".new / :isEmpty", function()
      it("creates an empty nfa without arguments", function()
         local m = Nfa.new()
         assert.is_true(m:isEmpty())
         assert.are.equal(0, m.numStates)
      end)

      it("counts the states of the given edges", function()
         local m = char "a"
         assert.is_false(m:isEmpty())
         assert.are.equal(2, m.numStates)
      end)

      it("can be called like a constructor", function()
         assert.are.equal(getmetatable(Nfa.new()), getmetatable(Nfa {}))
      end)
   end)

   describe(":compute", function()
      it("accepts exactly the words of its language", function()
         assert.are.same({ "a" }, accepted(char "a", words))
      end)

      it("returns the word as second value", function()
         local ok, word = char("a"):compute("b")
         assert.is_false(ok)
         assert.are.equal("b", word)
      end)
   end)

   describe(":copy", function()
      it("returns an independent nfa with the same language", function()
         local m = char "a"
         local c = m:copy()
         c:addEdge(2, "b", { 2 })

         assert.are.same({ "a" }, accepted(m, words))
         assert.are.same({ "a", "ab" }, accepted(c, words))
      end)
   end)

   describe("operations", function()
      it("union (+) accepts either language", function()
         assert.are.same({ "a", "b" }, accepted(char "a" + char "b", words))
      end)

      it("union with an empty nfa returns the other one", function()
         local m = char "a"
         assert.are.equal(m, m + Nfa.new())
         assert.are.equal(m, Nfa.new() + m)
      end)

      it("concat (..) accepts the concatenation", function()
         assert.are.same({ "ab" }, accepted(char "a" .. char "b", words))
      end)

      it("star accepts zero or more repetitions", function()
         assert.are.same({ "", "a", "aa", "aaa", "aaaa" }, accepted(char("a"):star(), words))
      end)

      it("plus accepts one or more repetitions", function()
         assert.are.same({ "a", "aa", "aaa", "aaaa" }, accepted(char("a"):plus(), words))
      end)

      it("optional accepts zero or one occurrence", function()
         assert.are.same({ "", "a" }, accepted(char("a"):optional(), words))
      end)

      it("optional does not loop through the start state", function()
         -- a*b: the start state of m has an a-loop, so "a" must not be accepted
         local astar = Nfa { states = 1, edges = { [1] = { a = { 1 } } }, accepting = { 1 } }
         local m = (astar .. char "b"):optional()
         assert.are.same({ "", "b", "ab" }, accepted(m, words))
      end)
   end)

   describe(":times", function()
      it("{n} accepts exactly n repetitions", function()
         assert.are.same({ "aa" }, accepted(char("a"):times(2, 2), words))
      end)

      it("{n, m} accepts n to m repetitions", function()
         assert.are.same({ "aa", "aaa" }, accepted(char("a"):times(2, 3), words))
      end)

      it("{n,} accepts n or more repetitions", function()
         assert.are.same({ "aa", "aaa", "aaaa" }, accepted(char("a"):times(2), words))
      end)

      it("{0, m} accepts zero to m repetitions", function()
         assert.are.same({ "", "a", "aa" }, accepted(char("a"):times(0, 2), words))
      end)

      it("{0,} accepts any number of repetitions", function()
         assert.are.same({ "", "a", "aa", "aaa", "aaaa" }, accepted(char("a"):times(0), words))
      end)

      it("{1, 3} accepts one to three repetitions", function()
         assert.are.same({ "a", "aa", "aaa" }, accepted(char("a"):times(1, 3), words))
      end)

      it("returns the nfa unchanged without bounds", function()
         local m = char "a"
         assert.are.equal(m, m:times())
      end)
   end)

   describe(":addEdge", function()
      it("changes only the given state P3-6 #knownbug", function()
         -- (a|b)c: the accepting states of a (3) and b (5) both get an epsilon edge
         -- to c's start state, and concat stores the same list object for both
         local m = (char "a" + char "b") .. char "c"
         assert.are.same({ "ac", "bc" }, accepted(m, { "a", "b", "ac", "bc" }))

         m:addEdge(3, Nfa.epsilon, { 7 })  -- let "a" skip the c
         assert.are.same({ "a", "ac", "bc" }, accepted(m, { "a", "b", "ac", "bc" }))
      end)
   end)
end)
