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
      it("changes only the given state P3-6", function()
         -- (a|b)c: the accepting states of a (3) and b (5) both get an epsilon edge
         -- to c's start state; concat used to store the same list object for both
         local m = (char "a" + char "b") .. char "c"
         assert.are.same({ "ac", "bc" }, accepted(m, { "a", "b", "ac", "bc" }))

         m:addEdge(3, Nfa.epsilon, { 7 })  -- let "a" skip the c
         assert.are.same({ "a", "ac", "bc" }, accepted(m, { "a", "b", "ac", "bc" }))
      end)

      it("doesn't change a list another state shares P3-6", function()
         -- star links its new start state (1) and the accepting state (3) to state 2
         local s = char("a"):star()
         s:addEdge(1, Nfa.epsilon, { 3 })

         assert.are.same({ 2, 3 }, s.edges[1][Nfa.epsilon])
         assert.are.same({ 2 }, s.edges[3][Nfa.epsilon])
      end)

      it("doesn't change the list it is given P3-6", function()
         local m, targets = char "a", { 2 }
         m:addEdge(1, "b", targets)
         m:addEdge(1, "b", { 1 })

         assert.are.same({ 2 }, targets)
         assert.are.same({ "a", "b", "ba" }, accepted(m, { "a", "b", "ba", "ab" }))
      end)
   end)

   describe(".new with tables of the caller P3-7", function()
      it("copies the given tables", function()
         local edges, accepting = { [1] = { a = { 2 } } }, { 2 }
         local m = Nfa { edges = edges, accepting = accepting }

         m:addEdge(1, "a", { 1 })
         m:addEdge(2, "b", { 2 })
         m:acceptingStates { 1 }

         assert.is_nil(getmetatable(edges))
         assert.are.same({ [1] = { a = { 2 } } }, edges)
         assert.are.same({ 2 }, accepting)
      end)

      it("is not empty when edges[1] is missing", function()
         -- state 1 is accepting and has no edges: the language is { "" }
         local m = Nfa { edges = { [2] = { a = { 3 } } }, accepting = { 1 } }

         assert.is_false(m:isEmpty())
         assert.are.equal(3, m.numStates)
         assert.are.same({ "", "a" }, accepted(char "a" + m, words))
      end)

      it("counts a state that only has outgoing edges", function()
         local m = Nfa { edges = { [5] = { a = { 1 } } }, accepting = { 1 }, start = 5 }

         assert.are.equal(5, m.numStates)
         assert.are.same({ "a" }, accepted(m, words))
      end)
   end)

   describe("a start state other than 1 P3-10", function()
      -- reads "a" from state 3 to 2; state 1 is unused
      local function late_a()
         return Nfa { edges = { [3] = { a = { 2 } } }, accepting = { 2 }, start = 3 }
      end

      it("is kept by every operation", function()
         assert.are.same({ "a" }, accepted(late_a():copy(), words))
         assert.are.same({ "a", "b" }, accepted(late_a() + char "b", words))
         assert.are.same({ "a", "b" }, accepted(char "b" + late_a(), words))
         assert.are.same({ "ab" }, accepted(late_a() .. char "b", words))
         assert.are.same({ "ba" }, accepted(char "b" .. late_a(), words))
         assert.are.same({ "", "a", "aa", "aaa", "aaaa" }, accepted(late_a():star(), words))
         assert.are.same({ "a", "aa", "aaa", "aaaa" }, accepted(late_a():plus(), words))
         assert.are.same({ "", "a" }, accepted(late_a():optional(), words))
         assert.are.same({ "aa", "aaa" }, accepted(late_a():times(2, 3), words))
      end)
   end)
end)
