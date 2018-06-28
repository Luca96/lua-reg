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
    __VERSION = "0.03",
    __INFO    = "Regular Expression Engine for Lua",
    __AUTHOR  = "Luca Anzalone",
}

local mt  = { __index = Reg }
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
-------------------------------------------------------------------------------
-- Methods
-------------------------------------------------------------------------------
function Reg:matches(str)
-- returns true if the given string matches the regex
   return self.nfa:compute(str)
end

function Reg:find(str)
-- matches the first substring that satisfy the regex
-- returns the maching substring with start index
   str = str or ""
   
   local len, j = str:len(), 1

   while len > 0 and j < len do
      --
      for i = len, j, -1 do
         local sub = str:sub(j, i)

         if self:matches(sub) then
            return sub, j
         end
      end

      for i = j, len do
         local sub = str:sub(i, len)

         if self:matches(sub) then
            return sub, i
         end
      end

      j = j + 1
   end

   return "", 0
end

function Reg:finder(str)
-- return an iterator that finds every substring that matches
   local s, i = nil, nil

   return function()
      s, i = self:find(str)
      str  = str:sub(i + s:len() - 1)

      if i <= 0 then
         return
      end

      return s, i
   end 
end

function Reg:findall(str)
-- returns a list of substring that matches the regex
   local list  = Table()
   local len   = str:len()
   local j     = 1
   local match = false

   while len > 0 and j < len do
      match = false
      --
      for i = len, j, -1 do
         local sub = str:sub(j, i)

         if self:matches(sub) then
            list:append(sub)

            str = str:sub(i + 1, len)
            len = str:len()

            match = true
            j = 1

            break
         end
      end

      if not match then
         for i = j, len do
            local sub = str:sub(i, len)

            if self:matches(sub) then
               list:append(sub)

               str = str:sub(j, i - 1)
               len = str:len()

               match = true
               j = 1

               break
            end
         end
      end

      if not match then
         j = j + 1
      end
   end

   return list 
end

function Reg:split(str)
-- returns a list of string obtained by splitting the input string
   local list = Table()
   local size = 0
   local s, i = self:find(str) 

   while i > 0 do
      list:append(str:sub(0, i - 1))
      
      size = i + s:len()
      str  = str:sub(size)
      
      s, i = self:find(str)
   end

   -- add the last sub of str after the last match
   list:append(str:sub(size, str:len()))

   return list
end
-------------------------------------------------------------------------------
return setmetatable(Reg, { __call = function(t, ...) return Reg.new(...) end })
-------------------------------------------------------------------------------