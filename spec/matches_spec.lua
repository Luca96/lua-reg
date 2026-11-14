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

      it("[^abc] accepts other characters #knownbug", function()
         check("[^abc]", { "d", "z" })
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

      it("work outside a group #knownbug", function()
         check("a|b", { "a", "b" })
      end)
   end)

   describe("group backreferences", function()
      it("\\n repeats the n-th group", function()
         check("(ab)\1", { "abab" }, { "ab" })
         check("(a)(b)\2\1", { "abba" }, { "abab" })
      end)

      it("numbers groups outermost first, then left to right", function()
         -- \1 (ab(123))+  \2 (000)*  \3 (ab(123))  \4 (000)  \5 (123)
         check("(ab(123))+\3(000)*\4\5", { "ab123ab123000000123", "ab123ab123000123" },
               { "ab123000ab123123", "ab123ab123123" })
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
         check("::(aa|bb|:*:+)+:[abc]", { ":aa*+bb[abc]" }, { "aa[abc]" })
      end)
   end)

   it("{n} quantifiers apply to single characters #knownbug", function()
      check("a{2,}", { "aa", "aaaa" }, { "a" })
   end)
end)
