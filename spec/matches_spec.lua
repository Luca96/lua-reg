local Reg = require "luareg"
local h = require "helpers"
local check = h.check

describe("Reg:matches", function()

   it("returns the word as second value", function()
      local ok, word = Reg("ab"):matches("ab")
      assert.is_true(ok)
      assert.are.equal("ab", word)
   end)

   it("matches the whole string only", function()
      check("abc", { "abc" }, { "", "ab", "abcd", "xabc", "abd" })
   end)

   describe("character quantifiers", function()
      it("* repeats a character zero or more times", function()
         check("a*b", { "b", "ab", "aaab" }, { "", "a", "abb" })
         check("a*b*", { "", "a", "b", "aab" }, { "ba" })
      end)

      it("+ repeats a character one or more times", function()
         check("ab+c", { "abc", "abbbc" }, { "ac", "abcc" })
         check("a+", { "a", "aaa" }, { "" })
      end)

      it("? makes a character optional", function()
         check("colou?r", { "color", "colour" }, { "colouur", "colr" })
      end)
   end)

   describe("sets", function()
      it("[abc] matches one of the characters", function()
         check("[abc]", { "a", "b", "c" }, { "", "d", "ab" })
      end)

      it("supports ranges", function()
         check("[a-c]", { "a", "b", "c" }, { "d", "A" })
         check("[a-zA-Z]+ [0-9]+", { "August 19", "June 4" }, { "June", "19 June" })
      end)

      it("supports * + ?", function()
         check("[abc]*", { "", "abcba" }, { "abd" })
         check("[abc]+", { "a", "cab" }, { "" })
         check("[abc]?", { "", "a" }, { "ab" })
      end)

      it("supports {n}, {n,m}, {,n} and {n,}", function()
         check("[0-9]{3}", { "123" }, { "12", "1234" })
         check("[0-9]{2,3}", { "12", "123" }, { "1", "1234" })
         check("[0-9]{,2}", { "1", "12" }, { "123" })
         check("[0-9]{2,}", { "12", "12345" }, { "1" })
      end)

      it("[^abc] rejects the listed characters", function()
         check("[^abc]", {}, { "a", "b", "c" })
      end)

      it("[^abc] accepts other characters P2-10", function()
         check("[^abc]", { "d", "z", " ", ":" }, { "", "dd" })
         check("[^a-c]", { "d", "A" }, { "a", "b", "c" })
      end)

      it("[^...] works inside groups, unions and repeats P2-10", function()
         check("([^ab]c)+", { "xc", "xcdc", "cc" }, { "ac", "xcbc", "" })
         check("(x|[^x])", { "x", "y" }, { "", "xy" })
         check("[^a]{2}", { "bc", "zz" }, { "ab", "b", "bbb" })
         check("a[^a]*a", { "aa", "abca" }, { "aaa", "aba a" })
      end)

      it("[^...] keeps working when the nfa is copied into a bigger one P2-10", function()
         -- the old undeft closure stored absolute state numbers, so the complement broke
         -- once concat/union renumbered its states
         check("x[^ab]|y[^ab]", { "xc", "yc" }, { "xa", "yb", "xy c" })
      end)

      it("only ], :, a leading ^ and a - between two characters are special in a set", function()
         check("[(*)]", { "(", "*", ")" }, { "a" })
         check("[a^]", { "a", "^" }, { "b" })
         check("[[]", { "[" }, { "]" })
         check("[a:-z]", { "a", "-", "z" }, { "b" })
         check("[:^a]", { "^", "a" }, { "b" })
      end)

      it("{0,m}, {0,} and {,m} allow zero repetitions P0-4", function()
         check("[a]{0,2}", { "", "a", "aa" }, { "aaa" })
         check("[a]{0,}", { "", "a", "aaa" })
         check("[a]{,2}", { "", "a", "aa" }, { "aaa" })
      end)

      it("the escape character is not part of the set P2-1", function()
         check("[:]a]", { "]", "a" }, { ":" })
      end)

      it("ranges can be followed by a literal '-'", function()
         check("[a-c-e]", { "a", "b", "c", "-", "e" }, { "d" })
      end)

      it("{n} repeats a set exactly n times", function()
         check("[ab]{2}", { "ab", "ba", "aa" }, { "a", "aba" })
      end)

      it("can contain '%' P1-1", function()
         check("[%]", { "%" }, { "", "a" })
         check("[a%]", { "a", "%" }, { "b" })
         check("[%a-c]", { "%", "a", "b", "c" }, { "d", "-" })
         check("[%d]+", { "%", "d%d" }, { "1" })
      end)
   end)

   describe("groups", function()
      it("(ab) matches the group once", function()
         check("(ab)", { "ab" }, { "a", "abab" })
      end)

      it("supports * + ?", function()
         check("(ab)*", { "", "ab", "abab" }, { "aba" })
         check("(ab)+c", { "abc", "ababc" }, { "c" })
         check("(ab)?", { "", "ab" }, { "abab" })
      end)

      it("supports {n} and {n,m}", function()
         check("(ab){2}", { "abab" }, { "ab", "ababab" })
         check("(ab){1,2}", { "ab", "abab" }, { "", "ababab" })
      end)

      it("can be nested", function()
         check("(00(abc)*00)", { "0000", "00abc00", "00abcabc00" }, { "00ab00" })
         check("a(b(cd)*)+e", { "abe", "abcdcde", "abbe" }, { "ae" })
         check("([A-Z]/[0-9]+/[A-Z])+", { "A/1234/A", "Z/00/ZA/1010/A" }, { "A/x/A" })
      end)

      it("mix with sets and quantifiers", function()
         check("[ab]{2, 4}(zz){,2}", { "abzzzz", "aazz", "abazz", "abbbzz" }, { "a" })
      end)

      it("an optional group can be followed by more pattern", function()
         check("(a)?b", { "b", "ab" }, { "", "a", "aab" })
      end)

      it("? accepts only the group or nothing P0-2", function()
         check("(a*b)?", { "", "b", "aab" }, { "a", "aaa" })
         check("((ab)+c)?", { "", "abc", "ababc" }, { "ab" })
         check("(c[ab]+)?", { "", "ca", "cab" }, { "a", "b" })
      end)

      it("{n,m} accepts only n to m whole repetitions P0-3", function()
         check("(ba*|c){1,2}", { "c", "ba", "cc", "baa", "cba", "bac" }, { "ca", "a", "ccc" })
      end)

      it("a repeat over a repeated unit or a pattern that accepts \"\" keeps its language P2-14", function()
         -- the parser rewrites these (P2-14); Nfa:times, unchanged, builds the reference.
         -- The bodies cover one unit (a|aa, aa*, ab(ab)*), counts with a gap that must not be
         -- rewritten (a|aaa; aa and aa|aaa under {0,3} and {1,3}), and different units.
         -- Every word over {a, b} up to length 6
         local words, frontier = { "" }, { "" }

         for _ = 1, 6 do
            local next_frontier = {}

            for _, w in ipairs(frontier) do
               for _, c in ipairs { "a", "b" } do
                  next_frontier[#next_frontier + 1] = w .. c
                  words[#words + 1] = w .. c
               end
            end

            frontier = next_frontier
         end

         local function accepted(m, list)
            local out = {}

            for _, w in ipairs(list) do
               if m:compute(w) then
                  out[#out + 1] = w
               end
            end

            return out
         end

         local quantifiers = {
            { "{2}", 2, 2 }, { "{3}", 3, 3 }, { "{0,3}", 0, 3 }, { "{1,3}", 1, 3 },
            { "{2,3}", 2, 3 }, { "{2,4}", 2, 4 }, { "{2,}", 2 }, { "{3,}", 3 },
            { "*", 0 }, { "+", 1 }, { "?", 0, 1 },
         }
         local bodies = {
            "a*", "a+", "a?", "a{0,2}", "a{2,}", "a{1,2}", "(a*)", "(ab)*", "a|b*", "a*b*",
            "[^a]*", "a|", "",
            "a|aa", "aa*", "a|aa|aaa", "ab|abab", "ab(ab)*", "ab|ab(ab)", "[ab]|[ba][ab]",
            "a|aaa", "aa", "aa|aaa", "a(ba)*b", "ab*a",
         }

         for _, body in ipairs(bodies) do
            for _, q in ipairs(quantifiers) do
               local pattern = "(" .. body .. ")" .. q[1]
               local expected = Reg(body).nfa:times(q[2], q[3])

               assert.are.same(accepted(expected, words), accepted(Reg(pattern).nfa, words), pattern)
            end
         end
      end)

      it("{0,m}, {,m} and {0,} allow zero repetitions", function()
         check("(ab){0,2}", { "", "ab", "abab" }, { "a", "ababab" })
         check("(ab){,2}", { "", "ab", "abab" }, { "ababab" })
         check("(ab){0,}", { "", "ab", "ababab" }, { "aba" })
         check("x(ab){0,1}y", { "xy", "xaby" }, { "xababy" })
      end)

      it("an empty group matches only the empty string P1-3", function()
         check("()", { "" }, { "a" })
         check("a()b", { "ab" }, { "", "a", "b" })
         check("()*", { "" }, { "a" })
         check("()+", { "" }, { "a" })
         check("()?", { "" }, { "a" })
         check("(){2}b", { "b" }, { "", "bb" })
         check("(a|())", { "", "a" }, { "aa" })
         check("()\1", { "" }, { "a" })
      end)

      it("a ) inside a set does not close the group P2-6", function()
         check("(a[)]b)", { "a)b" }, { "ab" })
      end)
   end)

   describe("large patterns", function()
      -- compiling used to take time quadratic in the number of copies:
      -- [a]{1000} took 6 s and [a]{1,1000} 13 s; now both take a few milliseconds
      local function compiles_fast(pattern)
         local t = os.clock()
         local r = Reg(pattern)
         local secs = os.clock() - t

         assert.is_true(secs < 1.5, ("%s compiled in %.2f s"):format(pattern:sub(1, 20), secs))
         return r
      end

      it("compile long counts in linear time P2-12", function()
         local r = compiles_fast "[a]{1000}"
         assert.is_true((r:matches(("a"):rep(1000))))
         assert.is_false((r:matches(("a"):rep(999))))

         r = compiles_fast "[a]{1,1000}"
         assert.is_true((r:matches("a")))
         assert.is_true((r:matches(("a"):rep(1000))))
         assert.is_false((r:matches(("a"):rep(1001))))
      end)

      it("compile long sequences and unions in linear time P2-12", function()
         local literal = ("ab"):rep(1000)
         assert.is_true((compiles_fast(literal):matches(literal)))

         local words = {}

         for i = 1, 500 do
            words[i] = "w" .. i
         end

         local r = compiles_fast(table.concat(words, "|"))
         assert.is_true((r:matches("w1")))
         assert.is_true((r:matches("w500")))
         assert.is_false((r:matches("w501")))
      end)

      it("match a wide {n,m} range in time linear in the subject P2-13", function()
         -- [a]{1,1000} on 1000 a's took 1.7 s: every step's closure spanned all the
         -- optional copies left. Now it takes milliseconds; the limit leaves a wide margin
         local r = Reg "[a]{1,1000}"
         local t = os.clock()

         assert.is_true((r:matches(("a"):rep(1000))))
         assert.is_true((r:matches(("a"):rep(500))))
         assert.is_false((r:matches(("a"):rep(1001))))
         assert.is_true(os.clock() - t < 0.5, ("matching took %.2f s"):format(os.clock() - t))

         check("(ab){0,3}", { "", "ab", "abab", "ababab" }, { "a", "aba", "abababab" })
         check("x(a|bc){2,4}y", { "xaay", "xbcay", "xabcabcy" }, { "xay", "xaaaaay" })
      end)

      -- the most states active before and after each character of word: matching costs
      -- that much per character
      local function most_active(r, word)
         local states = r.nfa:startStates()
         local most = #states

         for i = 1, #word do
            states = r.nfa:step(states, word:sub(i, i))
            most = math.max(most, #states)
         end

         return most
      end

      it("match a wide {n,m} range over a pattern that can match \"\" in linear time P2-14", function()
         -- a pattern that accepts "" linked every copy of {n,m} to the next through epsilons,
         -- so almost all copies stayed active (899 of 901 states for (a*){0,300}), even before
         -- the first character. The parser now collapses a quantifier over a quantifier, and
         -- repeats any other pattern that accepts "" without its "" match
         local word = ("a"):rep(300)

         for _, case in ipairs {
            { "(a*){0,300}", true }, { "(a?){0,300}", true }, { "(a|b*){1,300}", true },
            { "(a|b*){150,300}", true }, { "(a*){300}", true }, { "(a*){150,}", true },
            { "((a*)){2,300}", true }, { "(a{0,3}){0,100}", true }, { "(a+){1,300}", false },
            { "(a+){150,300}", false },
         } do
            local pattern = case[1]
            local r = Reg(pattern)

            assert.is_true((r:matches(word)), pattern)
            assert.are.equal(case[2], (r:matches("")), pattern)
            assert.is_false((r:matches(word .. "c")), pattern)
            assert.is_true(most_active(r, word) <= 10, pattern .. " keeps too many states active")
         end

         assert.is_true(most_active(Reg "(a|b*){150,}", ("b"):rep(300)) <= 10)
         assert.is_false((Reg "(a+){150,300}":matches(("a"):rep(149))))
      end)

      it("count a repeated unit in linear time P2-14", function()
         -- (a|aa){1,300} reads 300 a's as anything from 150 to 300 repetitions, and each count
         -- kept its own copy active (1,050 of 2,100 states). The parser now sees the body as
         -- one unit repeated a range of times (a 1..2) and counts the unit: a{1,600}
         local a300, ab150 = ("a"):rep(300), ("ab"):rep(150)
         local function a(n) return ("a"):rep(n) end
         local function ab(n) return ("ab"):rep(n) end

         -- pattern, a subject it matches, strings it must reject (around its bounds)
         for _, case in ipairs {
            { "(a|aa){1,300}", a300, { "", a(601) } },
            { "(a{1,2}){1,300}", a300, { "", a(601) } },
            { "([ab]|[ba][ab]){1,300}", a300, { "", a(601) } },
            { "(aa*){1,300}", a300, { "" } },
            { "(a{1,300})+", a300, { "" } },
            { "(a{1,600})*", a300, { "b" } },
            { "((a|aa){1,300})*", a300, { "b" } },
            { "a(a|aa){1,300}", a300, { "a", a(602) } },
            { "(a|aa){150,300}", a300, { a(149), a(601) } },
            { "(a|aa|aaa){100,300}", a300, { a(99), a(901) } },
            { "(ab|abab){1,300}", ab150, { "", ab(601) } },
            { "(ab|ab(ab)){1,300}", ab150, { "", ab(601) } },
            { "(ab(ab)*){1,300}", ab150, { "", "a", "aba" } },
         } do
            local pattern = case[1]
            local r = Reg(pattern)

            assert.is_true((r:matches(case[2])), pattern)

            for _, s in ipairs(case[3]) do
               assert.is_false((r:matches(s)), ("%s should reject %d chars"):format(pattern, #s))
            end

            assert.is_true(most_active(r, case[2]) <= 10, pattern .. " keeps too many states active")
         end

         -- the same automaton as the pattern written as one count
         assert.are.equal(Reg("a{1,600}").nfa.numStates, Reg("(a|aa){1,300}").nfa.numStates)
         -- a backreference is a unit too: (a)(\1|\1\1){1,3} is a followed by 1 to 6 a's
         check("(a)(\1|\1\1){1,3}", { a(2), a(7) }, { a(1), a(8) })
      end)

      it("match a wide {n,m} range over a pattern that isn't one counted unit in linear time P2-15 #knownbug", function()
         -- a pattern that isn't one unit repeated a range of times keeps a copy active per
         -- number of repetitions: different units ((a|b*) on b's, where a run of b's is one
         -- repetition or many), counts with a gap ((a|aaa): 1 or 3, never 2), and a unit
         -- written rotated (a(ba)*b is (ab)+, read as a (ba)* b)
         for _, case in ipairs {
            { "(a|aaa){1,300}", ("a"):rep(300) },
            { "(a|b*){1,300}", ("b"):rep(300) },
            { "(a(ba)*b){1,300}", ("ab"):rep(150) },
         } do
            local r = Reg(case[1])

            -- the answers are right; only the cost is wrong
            assert.is_true((r:matches(case[2])), case[1])
            assert.is_true(most_active(r, case[2]) <= 10, case[1] .. " keeps too many states active")
         end
      end)
   end)

   describe("unions", function()
      it("(A|B|C) matches any alternative", function()
         check("(a|b|c)", { "a", "b", "c" }, { "d", "ab" })
         check("x(ab|cd)y", { "xaby", "xcdy" }, { "xy", "xabcdy" })
      end)

      it("can be repeated", function()
         check("(a|b)+", { "a", "abba" }, { "" })
         check("(aa|bb)+", { "aa", "bb", "bbbb", "bbaabb" }, { "ab", "aab" })
         check("([a-z]+|[0-9]+)x", { "abcx", "12x" }, { "a1x" })
      end)

      it("can be nested and bounded", function()
         check("((a|b)c)+", { "ac", "acbc", "bcbcac" }, { "", "ab", "acb" })
         check("(a|b){2,3}", { "ab", "ba", "bab", "aaa" }, { "a", "abab" })
      end)

      it("work outside a group P0-5", function()
         check("a|b", { "a", "b" }, { "aab", "a|b" })
         check("ab|cd", { "ab", "cd" }, { "abbcd" })
      end)

      it("work outside a group next to groups and backreferences", function()
         check("x(a)|b", { "xa", "b" }, { "xab", "xb", "a" })
         check("(a)|b\1", { "a", "ba" }, { "b", "ab" })
         check("(a|b)c|d", { "ac", "bc", "d" }, { "c", "dc" })
      end)

      it("a lone | matches the empty string (two empty alternatives)", function()
         check("|", { "" }, { "|" })
      end)

      it("accept an empty alternative P2-3", function()
         check("(a|)", { "", "a" }, { "a|" })
         check("(|a)", { "", "a" }, { "|a" })
         check("(a||b)", { "", "a", "b" }, { "ab" })
         check("a|", { "", "a" }, { "aa" })
         check("x(|y)z", { "xz", "xyz" }, { "xyyz" })
      end)
   end)

   describe("group backreferences", function()
      it("\\n repeats the n-th group", function()
         check("(ab)\1", { "abab" }, { "ab" })
         check("(a)(b)\2\1", { "abba" }, { "abab" })
      end)

      it("numbers groups by their '(' from left to right", function()
         -- \1 (ab(123))  \2 (123)  \3 (000)
         check("(ab(123))+\1(000)*\3\2", { "ab123ab123000000123", "ab123ab123000123" },
               { "ab123000ab123123", "ab123ab123123" })
         check("((a)b)(c)\1\2\3", { "abcaba" .. "c" }, { "abcabac" .. "x" })
      end)

      it("refer to the group without its quantifier", function()
         -- (a)* is one group: \1 is (a), so (a)*\1 means a*a
         check("(a)*\1", { "a", "aa", "aaa" }, { "" })
         check("(ab){2}\1", { "ababab" }, { "abab" })
      end)

      it("can refer forward to a later group", function()
         check("\1(ab)", { "abab" }, { "ab" })
      end)

      it("don't count a group inside a set P1-6", function()
         -- the (a) of [(a)] is part of the set, so \1 is (b)
         check("[(a)](b)\1", { "(bb", "abb", ")bb" }, { "(ba", "(b(" })
         check("(x)[(y)]\1", { "xyx", "x(x" }, { "xyy" })
      end)

      it("can be quantified P2-4", function()
         check("(a)\1*", { "a", "aa", "aaa" }, { "a\1" })
      end)
   end)

   describe("escapes", function()
      it(": escapes reserved characters", function()
         check(":(a:)", { "(a)" }, { "a" })
         check(":[a:]", { "[a]" }, { "a" })
         check("a:+", { "a+" }, { "aa" })
         check("a:*", { "a*" }, { "aaa" })
         check("a:?", { "a?" }, { "a" })
      end)

      it(":: matches a literal ':'", function()
         check("[0-9]?[0-9]::[0-9][0-9]", { "10:20", "1:00" }, { "1:0", "100:00" })
      end)

      it("work inside unions", function()
         check("::(aa|bb|:*:+)+:[abc:]", { ":aa*+bb[abc]" }, { "aa[abc]" })
      end)

      it("work for every special character", function()
         check(":(:):[:]:{:}:*:+:?:|::", { "()[]{}*+?|:" }, { "" })
         check(":%:.:-: ", { "%.- " }, { "" })
      end)

      it("an escaped | can be quantified P0-5", function()
         check("x:|?", { "x", "x|" })
      end)

      it("pair up, so ::: is a literal ':' followed by an escape P2-5", function()
         check(":::*", { ":*" }, { "::", ":::" })
      end)
   end)

   it("{n} quantifiers apply to single characters P2-7", function()
      check("a{2,}", { "aa", "aaaa" }, { "a" })
      check("a{2}", { "aa" }, { "a{2}" })
      check("xa{1,2}y", { "xay", "xaay" }, { "xy", "xaaay" })
      check(":*{2}", { "**" }, { "*" })
   end)
end)
