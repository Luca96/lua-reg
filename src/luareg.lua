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
local table  = require "luatable"
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
    __VERSION = "0.04",
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
-- parse and compile the given regex
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

function Reg:find(str, init)
-- the leftmost-longest match at index init (default 1) or later: returns the
-- matched substring and its start index, or "", 0 without a match.
-- An empty match is a match too: Reg"a*":find"bbb" returns "", 1.
   str  = str or ""
   init = init or 1

   if init < 1 then
      init = 1
   elseif init > #str + 1 then
      return "", 0
   end

   local i, j = self.nfa:search(str, init)

   if i == nil then
      return "", 0
   end

   return str:sub(i, j), i
end

local function each_match(self, str)
-- iterator over the successive matches in str: (substring, start, end).
-- Same rule as Lua 5.4's string.gmatch: after a match the search goes on where it
-- ended, and an empty match is not allowed right where the previous match ended
-- (so "a*" on "baaac" gives "", "aaa", "" at 1, 2 and 6).
   local nfa  = self.nfa
   local n    = #str
   local init = 1
   local last = nil  -- the index right after the previous match

   return function()
      while init <= n + 1 do
         local i, j = nfa:search(str, init)

         if i == nil then
            init = n + 2
            return nil
         end

         if j < i and i == last then
            -- empty match where the previous match ended: skip it
            init = i + 1
         else
            init = j >= i and j + 1 or i + 1
            last = j + 1
            return str:sub(i, j), i, j
         end
      end
   end
end

function Reg:finder(str)
-- return an iterator over every match: each step returns the matched substring
-- and its start index in str
   local next_match = each_match(self, str)

   return function()
      local s, i = next_match()
      return s, i
   end
end

function Reg:findall(str)
-- returns a list of the substrings that match the regex, in order
   local list = table()

   for s in each_match(self, str) do
      list:append(s)
   end

   return list
end

function Reg:split(str, remove_empty)
-- returns the list of pieces of str between the matches of the regex
   local list = table()
   local from = 1

   for _, i, j in each_match(self, str) do
      list:append(str:sub(from, i - 1))
      from = j + 1
   end

   -- add the last substring after the last match
   list:append(str:sub(from))

   if remove_empty then
      -- remove all the empty string
      return list:reject(function(s) return s:len() <= 0 end)
   end

   return list
end
-------------------------------------------------------------------------------
return setmetatable(Reg, { __call = function(t, ...) return Reg.new(...) end })
-------------------------------------------------------------------------------