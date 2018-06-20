# Lua-Reg 0.01
A Regular Expression Engine for Lua. 

## Warning!
Currently the module is `under development`, so it is:
- __unfinished__
- __unoptimized__
- __unstable__

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
local reg = Regex "(ab(123))+\3(000)*\4\5"
print(reg:matches "ab123000ab123123")

-- how to backreference groups:
-- \1: refer to (ab(123))+
-- \2: refer to (000)*
-- \3: refer to (ab(123))
-- \4: refer to (000)
-- \5: refer to (123)

-- findall

```
