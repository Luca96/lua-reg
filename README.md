# Lua-Reg 0.5.0
[![test](https://github.com/Luca96/lua-reg/actions/workflows/test.yml/badge.svg)](https://github.com/Luca96/lua-reg/actions/workflows/test.yml)

A Regular Expression Engine for Lua: patterns are compiled to an NFA and matched in time linear
in the length of the string.

Lua-Reg is still before 1.0, so its API may change between minor versions (each change is listed
in the changelog). It runs on Lua 5.1, 5.2, 5.3, 5.4 and LuaJIT 2.1: CI runs the test suite on
each of them.

## Changes
View the `changelog` for more info about changes. Coming from 0.04? See
[Upgrading from 0.04](#upgrading-from-004).

## Installation
With [LuaRocks](https://luarocks.org):

```
luarocks install lua-reg
```

This also installs its dependency, the `luatable` rock from
[lua-table](https://github.com/Luca96/lua-table). Then `require "luareg"` (the modules are
`luareg`, `luareg.parser` and `luareg.nfa`).

From a clone of the repository, `luarocks make rockspecs/lua-reg-scm-1.rockspec` installs the
checked-out code the same way. Without LuaRocks, install lua-table
([instructions](https://github.com/Luca96/lua-table#installation)) and add the repo's `src`
folder to `package.path` (`src/?.lua`): `require "luareg"` loads `src/luareg.lua`, which loads
its parts `luareg.parser` and `luareg.nfa` from `src/luareg/`.

## Running the tests
The test suite uses [busted](https://lunarmodules.github.io/busted/) (`luarocks install busted`).
It expects [lua-table](https://github.com/Luca96/lua-table) to be checked out next to lua-reg
(`../lua-table`). From the repository root:

```
busted                           # whole suite
busted --exclude-tags=knownbug   # skip tests tagged #knownbug (tests of open known issues)
```

Or let LuaRocks fetch what the suite needs (busted and the `luatable` rock) and run it:
`luarocks test rockspecs/lua-reg-scm-1.rockspec` (it skips `#knownbug` tests). busted must find
`luatable` on its own `package.path`, so install both rocks in the same tree.

CI runs busted on every push and pull request, on Lua 5.1, 5.2, 5.3, 5.4 and LuaJIT 2.1,
against lua-table's `master`.

## Working features:
- quantifiers on characters, sets, groups and backreferences: `*, +, ?, {n}, {n, m}, {,n}, {n,}`
  (`{,n}` and `{0,n}` allow zero to n repetitions, `{0,}` is the same as `*`)
- sets: `[abc], [abc]+, [abc]*, [abc]?`; inside a set only `]`, `:`, a leading `^` and a `-`
  between two characters are special, so `[(*)]` is the set of `(`, `*` and `)`
- set complement: `[^abc]` (any character except a, b and c)
- ranges: `[0-9], [a-zA-Z]`
- groups: `(abc[0-9]abc)`, groups inside groups: `(00(abc)*00)`, the empty group `()`
- group backreferences `\1` to `\5`: groups are numbered by their `(` from left to right
  (see *Limitations* for what a backreference matches)
- unions of expressions: `A|B`, `(A|B|C)`; an alternative may be empty: `(a|)` is "a or nothing"
- escape a special character with `:`. The special characters are `( ) [ ] { } * + ? | :`; only
  punctuation can be escaped (`:a` and `:5` are errors, reserved for future classes like `:d`)
- strict syntax: a malformed pattern raises an error that names the position, e.g. unbalanced
  brackets, a quantifier with nothing to repeat (`*a`) or after another one (`a**`), a bad count
  (`a{1,2,3}`), an empty set `[]` or a trailing `:`
- searching with `find`, `finder`, `findall` and `split`: leftmost-longest matches, found in one
  pass over the string (time linear in its length)
- arguments work like Lua's string functions: a `nil` subject is `""`, a number is turned into a
  string, and any other type raises a *bad argument* error. Errors, syntax errors included, are
  plain messages that point at the line that called lua-reg

## Examples
```lua
local Reg = require "luareg"

-- sets
local r = Reg "[a-zA-Z]+ [0-9]+"
print(r:matches "August 19")
print(r:matches "June 4")

local r = Reg "[0-9]?[0-9]::[0-9][0-9]"  -- ':' is the escape character, so '::' is a literal ':'
print(r:matches "10:20")
print(r:matches "1:00")

-- groups
local r = Reg "([A-Z]/[0-9]+/[A-Z])+"
print(r:matches "A/1234/A")
print(r:matches "Z/00/ZA/1010/A")

local r = Reg "(00(abc)*00)"
print(r:matches "0000")
print(r:matches "00abc00")
print(r:matches "00abcabc00")

-- quantifiers
local r = Reg "[ab]{2, 4}(zz){,2}"
print(r:matches "abzzzz")
print(r:matches "aazz")
print(r:matches "abazz")
print(r:matches "abbbzz")

-- group backreference
local r = Reg "(ab(123))+\1(000)*\3\2"
print(r:matches "ab123ab123000000123")

-- how to backreference groups: one number per '(', from left to right
-- \1: refer to (ab(123))
-- \2: refer to (123)
-- \3: refer to (000)

-- unions
local r = Reg "(aa|bb)+"
print(r:matches "aa")
print(r:matches "bb")
print(r:matches "bbbb")
print(r:matches "bbaabb")

-- escape special characters with ':'
-- the special characters are: {, }, [, ], (, ), +, *, ?, |, :
local r = Reg "::(aa|bb|:*:+)+:[abc:]"
print(r:matches ":aa*+bb[abc]")
-----------------------------------------------------------
-- REG MODULE
-----------------------------------------------------------
local reg = Reg "[0-9]+"
local input = "123, 456, 1000, 1900"

-- find: the leftmost-longest match and its start index ("", 0 without a match);
-- an optional second argument is the index to start from (negative: from the end)
print(reg:find(input))
print(reg:find(input, 4))

-- finder
for s, i in reg:finder(input) do
   print(s, i)
end

-- findall
local finds = reg:findall(input) 
finds:eachi(print)

-- split
local splits = reg:split(input, true)
splits:eachi(print)

```

## Limitations
- **Backreferences are subroutine-style: they repeat the group's pattern, not the text it
  matched.** `([ab])\1` matches `ab` as well as `aa` (like PCRE's `(?1)`; text backreferences
  need a backtracking engine). A backreference refers to the group without its quantifier
  (`(a)*\1` means `a*a`), can point forward (`\1(ab)`), and can't be inside the group it refers
  to (`(a\1)` is an error: that would be recursion). Only `\1` to `\5` exist.
- **Ranges must stay inside one class:** `0-9`, `A-Z` or `a-z`. `[!-/]` is an error, so list such
  characters one by one.
- **Empty matches in searches** follow Lua 5.4's `string.gmatch`: `find` reports them
  (`Reg"a*":find"bbb"` returns `"", 1`), and `findall`/`finder`/`split` skip an empty match right
  where the previous match ended (`Reg"a*":findall"baaac"` gives `"", "aaa", ""`).
- Matching is byte-based: a multi-byte UTF-8 character counts as several characters.

## Upgrading from 0.04
0.5.0 changes how some patterns and searches behave (details in the changelog):
- **Group numbers** follow the `(` from left to right, and a quantified group counts once:
  renumber `\1` .. `\5` in patterns written for 0.04.
- **Malformed patterns raise errors** instead of being matched literally: escape literal
  brackets, quantifiers and `|` with `:`, and write a literal `]` as `:]`.
- **Escaped letters and digits** (`:a`, `:5`) are errors; only punctuation can be escaped.
- **`{,n}`** allows 0 to n repetitions (it was 1 to n): write `{1,n}` for the old meaning.
- **Empty matches are reported**: `find` returns `"", 1` for `Reg"a*":find"bbb"` (it was `"", 0`),
  and `findall`, `finder` and `split` include empty matches. Test for a match with
  `i > 0`, as before.
- **A negative `init`** in `find(str, init)` counts from the end of the string.
- **Modules:** `require "luareg"` is unchanged, but `require "nfa"` is now
  `require "luareg.nfa"`.

## Known issues
Each issue has an ID (P0 urgent … P3 low; IDs are never reused) and a `#knownbug` test in
`spec/` whose name contains the ID: `busted --filter="P2%-14"` runs it (the filter is a Lua
pattern, so escape the `-`).

### P2: performance
- **P2-14: A wide `{n,m}` range over a pattern that can match the empty string matches slowly.**
  `(a*){0,300}` on 300 a's takes about 180 ms, against 2 ms for `(a){0,300}`, and the time grows
  with the size of the range (n × m for a subject of n characters). `{n,m}` is built from m copies
  of the repeated pattern, each linked to the next one by an epsilon. When the pattern accepts
  `""`, those epsilons chain through every copy, so after each character almost all of them are
  active: 899 of 901 states for `(a*){0,300}`. Patterns that can't match empty (`(a*b){0,300}`)
  and unbounded repeats (`(a*)*`, `(a*){0,}`) aren't affected. Workaround: repeat something that
  can't match empty, e.g. `[a]{0,300}` instead of `(a?){0,300}`, or `a*` instead of `(a*){0,300}`.

## Roadmap
- fix the open known issue **P2-14**: a wide `{n,m}` range over a pattern that can match `""`
  is slow (see [Known issues](#known-issues));
- regex features: the `.` wildcard (an nfa `default` edge, as `[^...]` uses), anchors (`^`, `$`),
  and `:d`-style classes (escaped letters are already reserved for them).
