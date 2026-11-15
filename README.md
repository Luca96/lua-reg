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
None open (P1-1 to P1-7 were fixed; see the changelog).

### P2: misparses, search, performance
None open (P2-1 to P2-11 were fixed; see the changelog).

### P3: robustness and code quality
None open (P3-1 to P3-10 were fixed; see the changelog).

### Roadmap
- Put the modules in a namespace (`luareg.parser`, `luareg.nfa`): `parser` and `nfa` are generic
  module names that would clash once the library is installed through a rockspec.
- A rockspec, with a `test` section so `luarocks test` runs the suite.
- Missing regex features: the `.` wildcard (an nfa `default` edge, as `[^...]` uses), anchors
  (`^`, `$`), `:d`-style classes (escaped letters are already reserved for them).
- CI running busted on Lua 5.1, 5.4 and LuaJIT.
