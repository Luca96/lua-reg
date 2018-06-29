# Lua-Reg 0.03
A Regular Expression Engine for Lua. 

## Warning!
Currently the module is `under development`, so it is:
- __unfinished__
- __unoptimized__
- __unstable__
- __untested__

## Changes
View the `changelog` for more info about changes.

## Installation
To install the library just `clone` the repo and install [LuaTable](https://github.com/Luca96/lua-table#installation).

## Working features:
- quantifiers: `*, +, ?, {n}, {n, m}, {,n}, {n,}` 
- sets: `[abc]`
- ranges: `[0-9], [a-zA-Z]`
- groups: `(abc[0-9]abc)`
- groups inside groups: `(00(abc)*00)` 
- group backreference: `(abc)\2(123)\1`
- unions of expressions: `(A|B|C)`

## Examples
```lua
local Reg = require "luareg"

-- sets
local r = Reg "[a-zA-Z]+ [0-9]+"
print(r:matches "August 19")
print(r:matches "June 4")

local r = Reg "[0-9]?[0-9]:[0-9][0-9]"
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
print(r:matches "ab123000ab123123")

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
