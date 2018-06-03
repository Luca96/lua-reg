# Lua-Reg 0.0
A Regular Expression Engine for Lua. 

## Warning!
Currently the module is ```under development```, so it is:
- __unfinished__
- __unoptimized__
- __unstable__

## Changes
View the ```changelog``` for more info about changes.

## Installation
To install the library just ```clone``` the repo and install [LuaTable](https://github.com/Luca96/lua-table#installation).

## Working features:
- sets: ```[abc], [abc]*, [abc]+```
- ranges: ```[0-9], [a-zA-Z]```

## Planned features:
- set complement
- groups
- optionals
- unions
- ecc...

## Examples
```lua
local Reg = require "luareg"

local r1 = Reg "[a-zA-Z]+ [0-9]+"
print(r1:matches "August 19")
print(r1:matches "June 4")

local r2 = Reg "[0-9][0-9]:[0-9][0-9]"
print(r2:matches "10:20")
print(r2:matches "00:00")

```
