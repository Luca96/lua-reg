local Reg = require "luareg"
local h = require "helpers"

-- Performance acceptance tests. Each check compares against a baseline measured in the
-- same run, since absolute times differ between machines and Lua versions, and accepts
-- with a wide margin around the measured ratio (in the comments). `busted --tags=perf`
-- runs only these; `busted --exclude-tags=knownbug,perf` skips them on a noisy machine.
describe("performance #perf", function()
   local a300, ab150 = ("a"):rep(300), ("ab"):rep(150)

   local function ratio(f, g)
      return h.per_op(f) / h.per_op(g)
   end

   -- n nested groups: (X|z)? and ((X|z)|) match the same strings and copy the same states,
   -- but only the first has repeats for the parser to analyse (P2-14)
   local function nest(n, open, close)
      local p = "a"

      for i = 1, n do
         p = open .. p .. "|z" .. (i % 10) .. close
      end

      return p
   end

   local deep, flat = nest(40, "(", ")?"), nest(40, "((", ")|)")

   describe("speed", function()
      it("a counted unit matches as fast as the pattern written as one count P2-14", function()
         -- measured: 0.7 to 1.1 times
         for _, case in ipairs {
            { "(a|aa){1,300}", "a{1,600}", a300 },
            { "(aa*){1,300}", "a+", a300 },
            { "(ab|abab){1,300}", "(ab){1,600}", ab150 },
            { "(a*){0,300}", "a*", a300 },
            { "(a|b*){150,300}", "(a|b+){0,300}", a300 },
         } do
            local r, base = Reg(case[1]), Reg(case[2])
            local x = ratio(function() r:matches(case[3]) end, function() base:matches(case[3]) end)

            assert.is_true(x <= 2, ("%s takes %.2f times as long as %s"):format(case[1], x, case[2]))
         end
      end)

      it("the rewritten repeats match at least 5 times faster than without them P2-14", function()
         -- the reference is the build without the rewrites: Nfa:times (unchanged) on the
         -- compiled body. Measured: 26 to 164 times faster
         for _, case in ipairs {
            { "a|aa", 1, 300, a300 },
            { "aa*", 1, 300, a300 },
            { "ab|abab", 1, 300, ab150 },
            { "a|aa|aaa", 100, 300, a300 },
            { "a|b*", 150, 300, a300 },
         } do
            local pattern = ("(%s){%d,%d}"):format(case[1], case[2], case[3])
            local old = Reg(case[1]).nfa:times(case[2], case[3])
            local new = Reg(pattern)
            local speedup = h.per_op(function() old:compute(case[4]) end, 1)
               / h.per_op(function() new:matches(case[4]) end)

            assert.is_true(speedup >= 5, ("%s is only %.1f times faster"):format(pattern, speedup))
         end
      end)

      it("a counted unit compiles as fast as the pattern written as one count P2-14", function()
         -- measured: 0.9 to 1.2 times
         for _, case in ipairs {
            { "(a|aa){1,300}", "a{1,600}" },
            { "(a|aa|aaa){100,300}", "a{100,900}" },
         } do
            local x = ratio(function() Reg(case[1]) end, function() Reg(case[2]) end)

            assert.is_true(x <= 2, ("compiling %s takes %.2f times as long as %s"):format(case[1], x, case[2]))
         end
      end)

      it("nested repeats are analysed once: time P2-14", function()
         -- measured: 1.1 times (3.1 times when the analysis isn't memoized)
         local x = ratio(function() Reg(deep) end, function() Reg(flat) end)

         assert.is_true(x <= 2, ("40 nested (X|z)? compile %.2f times as slowly as ((X|z)|)"):format(x))
      end)
   end)

   describe("memory", function()
      it("a counted unit keeps no more memory than the pattern written as one count P2-14", function()
         -- measured: 1.0 times. The memo tables of the analysis are dropped after compiling
         for _, case in ipairs {
            { "(a|aa){1,300}", "a{1,600}" },
            { "(a|aa|aaa){100,300}", "a{100,900}" },
         } do
            local kept, r = h.retained(function() return Reg(case[1]) end)
            local base = h.retained(function() return Reg(case[2]) end)

            assert.is_nil(r.parser.keys)
            assert.is_nil(r.parser.powers)
            assert.is_true(kept <= 1.2 * base, ("%s keeps %.0f KB, %s %.0f KB"):format(case[1], kept, case[2], base))
         end
      end)

      it("the rewritten nfa takes at most 80% of the memory of the build without it P2-14", function()
         -- measured: 0.56 times
         for _, case in ipairs {
            { "a|aa", 1, 300 },
            { "a|aa|aaa", 100, 300 },
         } do
            local pattern = ("(%s){%d,%d}"):format(case[1], case[2], case[3])
            local old = h.retained(function() return Reg(case[1]).nfa:times(case[2], case[3]) end)
            local new = h.retained(function() return Reg(pattern).nfa end)

            assert.is_true(new <= 0.8 * old, ("%s takes %.0f KB, the build without the rewrite %.0f KB"):format(pattern, new, old))
         end
      end)

      it("nested repeats are analysed once: allocations P2-14", function()
         -- measured: 1.02 times (3.4 times when the analysis isn't memoized)
         local x = h.allocated(function() Reg(deep) end) / h.allocated(function() Reg(flat) end)

         assert.is_true(x <= 1.5, ("40 nested (X|z)? allocate %.2f times as much as ((X|z)|)"):format(x))
      end)
   end)
end)
