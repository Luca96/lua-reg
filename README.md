# Lua-Reg 0.0
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
- sets: `[abc], [abc]*, [abc]+`
- ranges: `[0-9], [a-zA-Z]`
- groups: `(abc[0-9]abc), (a[0-9]a)*, (a[0-9]a)+`
- groups inside groups: `(00(abc)*00)` 

## Planned features:
- set complement
- optionals
- unions
- ecc...

## Examples
```lua
local Reg = require "luareg"

-- sets
local r1 = Reg "[a-zA-Z]+ [0-9]+"
print(r1:matches "August 19")
print(r1:matches "June 4")

local r2 = Reg "[0-9][0-9]:[0-9][0-9]"
print(r2:matches "10:20")
print(r2:matches "00:00")

-- groups
local reg = Regex "([A-Z]/[0-9]+/[A-Z])+"
print(reg:matches "A/1234/A")
print(reg:matches "Z/00/ZA/1010/A")

local reg = Regex "(00(abc)*00)"
print(reg:matches "0000")
print(reg:matches "00abc00")
print(reg:matches "00abcabc00")

```
