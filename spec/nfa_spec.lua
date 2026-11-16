local Nfa = require "nfa"
local h = require "helpers"

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
         assert.are.same({ "ab", "aab" },
            accepted(Nfa.concatAll { late_a():times(1, 2), char "b" }, { "b", "ab", "aab", "aaab" }))
         assert.are.same({ "a", "b" }, accepted(Nfa.unionAll { char "b", late_a() }, words))
      end)
   end)

   describe(".concatAll / .unionAll / :times match the chained .. and + P2-12", function()
      -- every word over {a, b} up to length 6
      local long_words = { "" }

      do
         local frontier = { "" }

         for _ = 1, 6 do
            local next_frontier = {}

            for _, w in ipairs(frontier) do
               for _, c in ipairs { "a", "b" } do
                  next_frontier[#next_frontier + 1] = w .. c
                  long_words[#long_words + 1] = w .. c
               end
            end

            frontier = next_frontier
         end
      end

      local function bases()
         return {
            char "a",
            char("a"):star(),
            char("a"):plus(),
            char "a" + char "b",
            Nfa.emptyWord(),
            Nfa { edges = { [3] = { a = { 2 } } }, accepting = { 2 }, start = 3 },
         }
      end

      -- the whole structure of an nfa, without metatables
      local function shape(m)
         return h.plain { edges = m.edges, accepting = m.accepting, numStates = m.numStates,
                          current = m.current }
      end

      -- Nfa:times as it was built before concatAll: one .. per copy
      local function times_chained(m, x, y)
         if x == nil and y == nil then
            return m
         end

         x = x or 0
         local r = Nfa.new()

         for _ = 1, x do
            r = r .. m
         end

         if y == nil then
            r = r .. m:star()
         else
            for _ = 1, y - x do
               r = r .. m:optional()
            end
         end

         return r
      end

      it("concatAll builds exactly the nfa of chained ..", function()
         local bs = bases()

         for _, a in ipairs(bs) do
            for _, b in ipairs(bs) do
               for _, c in ipairs(bs) do
                  assert.are.same(shape((a .. b) .. c), shape(Nfa.concatAll { a, b, c }))
               end
            end
         end
      end)

      it("unionAll accepts the language of chained + with one start state", function()
         local bs = bases()

         for _, a in ipairs(bs) do
            for _, b in ipairs(bs) do
               for _, c in ipairs(bs) do
                  local chained, all = (a + b) + c, Nfa.unionAll { a, b, c }

                  assert.are.same(accepted(chained, long_words), accepted(all, long_words))
                  -- (a + b) + c nests two new start states, unionAll adds one
                  assert.are.equal(1 + a.numStates + b.numStates + c.numStates, all.numStates)
                  assert.are.equal(chained.numStates - 1, all.numStates)
               end
            end
         end
      end)

      it("times builds exactly the nfa of the chained version", function()
         for _, m in ipairs(bases()) do
            for x = 0, 3 do
               assert.are.same(shape(times_chained(m, x)), shape(m:times(x)))

               for y = x, x + 3 do
                  assert.are.same(shape(times_chained(m, x, y)), shape(m:times(x, y)))
               end
            end
         end
      end)

      it("skip empty operands and return a lone operand itself", function()
         local a, empty = char "a", Nfa.new()

         for _, all in ipairs { Nfa.concatAll, Nfa.unionAll } do
            assert.is_true(all({}):isEmpty())
            assert.is_true(all({ empty, empty }):isEmpty())
            assert.are.equal(a, all { a })
            assert.are.equal(a, all { empty, a, empty })
         end

         assert.are.same(shape(a .. char "b"), shape(Nfa.concatAll { empty, a, empty, char "b" }))
      end)
   end)
end)
