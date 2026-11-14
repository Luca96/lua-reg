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
- quantifiers: `*, +, ?, {n}, {n, m}, {,n}, {n,}` 
- sets: `[abc], [abc]+, [abc]*, [abc]?`
- set complement: `[^abc]`
- ranges: `[0-9], [a-zA-Z]`
- groups: `(abc[0-9]abc)`
- groups inside groups: `(00(abc)*00)` 
- group backreference: `(abc)\2(123)\1`
- unions of expressions: `(A|B|C)`
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

## Known issues & roadmap
This section tracks what is still open. Update it when an item is fixed or a new one is found.
Each known issue has a `#knownbug` test in `spec/`.

### Known issues
- **`find` can skip earlier matches.** When a match ends the string, `find` returns it instead of
  an earlier one (`Reg"[0-9]+":find"a1b2"` gives `"2", 4`). Because of this, `findall` returns
  matches out of order (`"a1b22c333"` → `333, 1, 22`) and `split` misses split points
  (`"123, 456, 1000, 1900"` → `", 456, 1000,"`).
- **`find`/`findall` miss one-character inputs.** `Reg"[0-9]+":find"7"` returns `"", 0`.
- **`finder` never advances.** After the first match it keeps returning the same one, so a
  `for ... in reg:finder(s)` loop does not end.
- **Set complement accepts nothing.** `[^abc]` correctly rejects `a`, `b`, `c`, but also rejects
  every other character.
- **`|` only works inside a group.** `a|b` matches neither `a` nor `b`; use `(a|b)`.
- **`{n}` quantifiers on single characters are ignored.** `a{2,}` does not match `aa`; they only
  work on sets and groups (`[a]{2,}`, `(a){2,}`).
- **An empty pattern crashes.** `Reg ""` raises *attempt to get length of a nil value*.
- **Global leak.** Compiling a regex sets a global `nfa` (missing `local` in `parser.lua`).

### Roadmap
- Fix the known issues above.
- Put the modules in a namespace (`luareg.parser`, `luareg.nfa`): `parser` and `nfa` are generic
  module names that would clash once the library is installed through a rockspec.
- A rockspec, with a `test` section so `luarocks test` runs the suite.
- Missing regex features: the `.` wildcard, anchors (`^`, `$`), `\d`-style classes.
- CI running busted on Lua 5.1, 5.4 and LuaJIT.
