-------------------------------------------------------------------------------
-- lua-reg: Regular Expression Engine for Lua
-------------------------------------------------------------------------------
--[[
MIT License

Copyright (c) 2018 Luca Anzalone

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]
-------------------------------------------------------------------------------
local Parser = require "parser"
local Table  = require "luatable"
local Nfa    = require "nfa"
-------------------------------------------------------------------------------
local setmetatable = setmetatable 
local assert = assert 
local select = select 
local insert = table.insert 
local remove = table.remove 
local concat = table.concat 
local format = string.format 
local print  = print 
local pairs  = pairs 
local ipairs = ipairs 
local type   = type 
-------------------------------------------------------------------------------
-- CLASS
-------------------------------------------------------------------------------
local Reg = {
    __VERSION = "0.0",
    __INFO    = "Regular Expression Engine for Lua",
    __AUTHOR  = "Luca Anzalone",
}

local mt = { __index = Reg }
-------------------------------------------------------------------------------
-- private functions
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Constructors
-------------------------------------------------------------------------------
function Reg.new(input)
-- 
   local self = setmetatable({}, mt)
   self.input = input or ""

   self.parser = Parser.new(input)
   self.parser:parse()

   self.nfa = self.parser:compile()

   return self
end

local function init(self, input)
--
   return Reg.new(input)
end
-------------------------------------------------------------------------------
-- Operations
-------------------------------------------------------------------------------
function Reg:matches(word)
--  
   return self.nfa:compute(word)
end
-------------------------------------------------------------------------------
return setmetatable(Reg, { __call = init })
-------------------------------------------------------------------------------