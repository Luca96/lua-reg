# Lua-Reg 0.04
A Regular Expression Engine for Lua. 

## Warning!
Currently the module is `under development`, so it is:
- __unfinished__
- __unoptimized__
- __unstable__

It runs on Lua 5.1 – 5.4.

## Changes
View the `changelog` for more info about changes.

## Installation
To install the library just `clone` the repo and install [LuaTable](https://github.com/Luca96/lua-table#installation).

## Running the tests
The test suite uses [busted](https://lunarmodules.github.io/busted/) (`luarocks install busted`).
It expects [lua-table](https://github.com/Luca96/lua-table) to be checked out next to lua-reg
(`../lua-table`). From the repository root:

```
busted                           # whole suite
busted --exclude-tags=knownbug   # skip the tests for the known issues below
```

## Working features:
- quantifiers: `*, +, ?, {n}, {n, m}, {,n}, {n,}` (`{,n}` and `{0,n}` allow zero to n
  repetitions, `{0,}` is the same as `*`)
- sets: `[abc], [abc]+, [abc]*, [abc]?`
- set complement: `[^abc]`
- ranges: `[0-9], [a-zA-Z]`
- groups: `(abc[0-9]abc)`
- groups inside groups: `(00(abc)*00)` 
- group backreference: `(abc)\2(123)\1`
- unions of expressions: `A|B`, `(A|B|C)`
- escape reserved characters with `:` 

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
local r = Reg "(ab(123))+\3(000)*\4\5"
print(r:matches "ab123ab123000000123")

-- how to backreference groups:
-- \1: refer to (ab(123))+
-- \2: refer to (000)*
-- \3: refer to (ab(123))
-- \4: refer to (000)
-- \5: refer to (123)

-- unions
local r = Reg "(aa|bb)+"
print(r:matches "aa")
print(r:matches "bb")
print(r:matches "bbbb")
print(r:matches "bbaabb")

-- escape reserved characters with ':'
-- reserved characters are: {, }, [, ], (, ), +, *, ?, |, :
local r = Reg "::(aa|bb|:*:+)+:[abc]"
print(r:matches ":aa*+bb[abc]")
-----------------------------------------------------------
-- REG MODULE
-----------------------------------------------------------
local reg = Reg "[0-9]+"
local input = "123, 456, 1000, 1900"

-- find
print(reg:find(input))

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
- **Backreferences repeat the group's pattern, not the text it matched.** `([ab])\1` matches `ab`
  as well as `aa`. Only `\1` to `\5` exist. Groups are numbered outermost first, then left to right.
- **Ranges must stay inside one class:** `0-9`, `A-Z` or `a-z`. `[!-/]` is an error, so list such
  characters one by one.
- **`find` never reports an empty match.** `Reg"a*":find"bbb"` returns `"", 0`.
- Matching is byte-based: a multi-byte UTF-8 character counts as several characters.

## Known issues & roadmap
This section tracks what is still open. Update it when an item is fixed or a new one is found.
Each known issue has an ID, and a `#knownbug` test in `spec/` whose name contains that ID
(`busted --filter="P1%-2"` runs one; the filter is a Lua pattern, so escape the `-`). When you
fix one, remove its entry here and the tag from its test, and keep the ID in the test name. IDs
are never reused.

Priorities:
- **P0, urgent:** silently wrong results, or one bad call breaks every later one.
- **P1, high:** crashes or hangs on input that looks reasonable.
- **P2, medium:** misparses you can work around, the search API, performance.
- **P3, low:** robustness and code quality.

### P0: wrong results
None open (P0-1 to P0-5 were fixed; see the changelog).

### P1: crashes and hangs
- **P1-1: `%` inside a set crashes.** The set's text goes through `string.format`: `[%]`, `[a%]`.
- **P1-2: An unterminated quantifier overflows the stack.** `[a]{2`, `(a){2`.
- **P1-3: An empty group crashes.** `()`, `a()b`.
- **P1-5: An empty pattern crashes.** `Reg ""` and `Reg(nil)` raise *attempt to get length of a
  nil value*.

### P2: misparses, search, performance
- **P2-1: The escape character stays in a set.** `[:]a]` also matches `:`.
- **P2-2: Unbalanced `(`, `)`, `[`, `]` are matched literally** instead of raising an error.
- **P2-3: An empty alternative turns `|` into a literal.** `(a|)` matches `a|` but not `a`. The
  same holds for `(|a)` and `(a||b)`.
- **P2-4: A quantifier after a backreference applies to the byte `\1`.** `(a)\1*` rejects `aa`.
- **P2-5: Escapes don't pair up.** `:::*` should mean a literal `:` and then a literal `*`, but it
  parses as `:` followed by `:*`.
- **P2-6: A `)` inside a set ends the enclosing group.** `(a[)]b)` rejects `a)b`.
- **P2-7: `{n}` quantifiers on single characters are matched literally.** `a{2}` matches the text
  `a{2}`. Use `[a]{2}` or `(a){2}`.
- **P2-8: `finder` never advances.** It cuts the string one character too early, so it keeps
  returning the same match, and its indices count from the cut instead of the original string.
- **P2-9: `find` can skip earlier matches.** When a match ends the string, `find` returns it
  instead of an earlier one (`Reg"[0-9]+":find"a1b2"` gives `"2", 4`), and it misses one-character
  inputs (`find"7"` gives `"", 0`). So `findall` returns matches out of order
  (`"a1b22c333"` → `333, 1, 22`) and `split` misses split points.
- **P2-10: Set complement accepts nothing.** `[^abc]` rejects `a`, `b` and `c`, but also every
  other character.
- **P2-11: Slow on long input** (no test). `find`/`findall` are O(n³): 0.6 s for 80 characters
  without a match. `matches` recurses once per character and copies a substring each step, so
  100,000 characters take 5 s and 300,000 run out of memory.

### P3: robustness and code quality
- **P3-1: A `nil` subject crashes.** `:matches(nil)` and `:findall(nil)` raise index errors, while
  `:find(nil)` treats `nil` as `""`.
- **P3-2: Lenient parsing.** `*a`, `a**` and `+` are taken as literals, and `{1.5}` as `{1}`.
  `{1,2,3}` prints a warning to stdout and is then matched literally (no test).
- **P3-6: `add_edge` changes shared lists in place.** `concat` gives several states the same edge
  list, so `Nfa:addEdge` on one of them changes the others too.
- **P3-7: `Nfa.new` keeps the caller's `edges`/`accepting` tables** instead of copying them, and
  `count_states` still uses `#`, which holes in the edges table can fool (no test).
- **P3-8: Error messages contain ANSI color codes** and point into `parser.lua` instead of the
  caller's line (no test).

### Roadmap
- Fix the known issues, P1 first.
- Put the modules in a namespace (`luareg.parser`, `luareg.nfa`): `parser` and `nfa` are generic
  module names that would clash once the library is installed through a rockspec.
- A rockspec, with a `test` section so `luarocks test` runs the suite.
- Missing regex features: the `.` wildcard, anchors (`^`, `$`), `\d`-style classes.
- CI running busted on Lua 5.1, 5.4 and LuaJIT.
