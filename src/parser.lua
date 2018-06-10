-------------------------------------------------------------------------------
--[[ ~
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
local Table = require "luatable"
local Nfa   = require "nfa"
-------------------------------------------------------------------------------
local type   = type 
local abs    = math.abs 
local s_char = string.char 
local format = string.format 
local unpack = unpack 
local tostring = tostring 
local setmetatable = setmetatable 
local getmetatable = getmetatable 

local err  = "\27[1;31mError:\27[0m"
local epsilon = Nfa.epsilon
-------------------------------------------------------------------------------
-- CLASS
-------------------------------------------------------------------------------
local Parser = {}
local parser_mt = { __index = Parser }

local reserved = {
   ['['] = true,
   [']'] = true,     
   ['('] = true,
   [')'] = true,
   ['*'] = true,
   ['+'] = true,
   ['?'] = true,
   -- ['{'] = true,
   -- ['}'] = true,
}
-------------------------------------------------------------------------------
-- Token
-------------------------------------------------------------------------------
local Token = {}

local token_mt = {
   __index = Token,
   
   __call  = function(self, start, ends, type, value, op)
      local mt = getmetatable(self)

      self = {
         start = start,
         ends  = ends,
         type  = type,
         value = value,
         childs = Table(),
         forbidden = Table(),  -- not allowed childs's type
         operation = op or '',
      }
      
      return setmetatable(self, mt)
   end,

   __tostring = function(self)
      return format("Token (i: %d j: %d t: %s, v: %s, op: %s)", 
         self.start, self.ends, self.type, self.value, self.operation)
   end,
}

Token = setmetatable(Token, token_mt)
-------------------------------------------------------------------------------
-- Token type constants 
-------------------------------------------------------------------------------
local char      = "char"
local char_star = "char_star"
local char_plus = "char_plus"
local char_opt  = "char_optional"
local set       = "set"
local set_star  = "set_star"
local set_plus  = "set_plus"
local set_comp  = "set_comp"
local set_opt   = "set_optional"
local group     = "group"
local grp_star  = "group_star"
local grp_plus  = "group_plus"
local grp_opt   = "group_optional"
-------------------------------------------------------------------------------
-- token operation constants
-------------------------------------------------------------------------------
local op_concat = "op_concat"
local op_union  = "op_union"
local op_star   = "op_star"
local op_plus   = "op_plus"
local op_comp   = "op_comp"
local op_opt    = "op_optional"
-------------------------------------------------------------------------------
-- token forbidden types
-------------------------------------------------------------------------------
local forb_set = Table (
   char_star, 
   char_plus, 
   char_opt , 
   group    , 
   grp_star , 
   grp_plus , 
   grp_opt
)
 -------------------------------------------------------------------------------
function Token:isSimple()
   return self.type == char      or 
          self.type == char_star or 
          self.type == char_plus or 
          self.type == set
end
-------------------------------------------------------------------------------
-- Ranges:
-------------------------------------------------------------------------------
local range_intervals = Table(
   48,  57 ,  --0-9
   65,  90 ,  --A-Z
   97,  122   --a-z
)

local function find_ranges(input)
   -- finds all ranges inside input string
   local k = 1
   local i = 0
   local n = input:len()
   local ranges = Table()

   while k < n do
      if input:sub(k, k) == '-' then
         local c1 = input:sub(k - 1, k - 1)
         local c2 = input:sub(k + 1, k + 1)

         if c1 ~= '' and c1 ~= '-' and c2 ~= '' and c2 ~= '-' then
            ranges:append { k + i, c1, c2 }

            input = input:sub(k + 2, n)
            k = 1

            local n1 = input:len()
            i = i + abs(n - n1)
            n = n1
         end
      end

      k = k + 1
   end

   return ranges
end

local function build_range(range)
   -- transform the range into a string of characters
   local s = ""
   local k = range[1]
   local i = range[2]:byte()
   local j = range[3]:byte()

   local interval = false

   for i1, i2 in range_intervals:group(2) do
      if i >= i1 and j <= i2 then
         interval = true
         break
      end
   end

   if j < i or interval == false then
      error(format("%s Invalid range %s-%s at position %d", err, range[2], range[3], k))
   end

   for k = i, j do
      s = s .. s_char(k)
   end

   return k, s, s:len()
end

local function handle_ranges(input)
   local ranges = find_ranges(input)
   local words  = {}

   for i = 1, #ranges do
      local k, s, len = build_range(ranges[i])
      k = k - i + 1  -- fix offset when inserting %s into input

      words[i] = s
      input = input:sub(0, k - 2) .. "%s" .. input:sub(k + 2, input:len())
   end

   return format(input, unpack(words))
end
-------------------------------------------------------------------------------
-- Tokens definitions
-------------------------------------------------------------------------------
local function tk_char(input)
   if input:len() > 0 then
      return Token(1, 1, char, input:sub(1, 1))
   end

   return nil
end

local function tk_char_star(input)
   local size = input:len()
   local prev = ''
   
   for k = 1, size do
      local c = input:sub(k, k)

      if c == '*' then
         if not reserved[prev] then
            k = k - 1
            return Token(k, k + 1, char_star, input:sub(k, k))
         end
      end

      prev = c
   end   
end

local function tk_char_plus(input)
   local size = input:len()
   local prev = ''
   
   for k = 1, size do
      local c = input:sub(k, k)

      if c == '+' then
         if not reserved[prev] then
            k = k - 1
            return Token(k, k + 1, char_plus, input:sub(k, k))
         end
      end

      prev = c
   end   
end

local function tk_char_opt(input)
   local size = input:len()
   local prev = ''
   
   for k = 1, size do
      local c = input:sub(k, k)

      if c == '?' then
         if not reserved[prev] then
            k = k - 1
            return Token(k, k + 1, char_opt, input:sub(k, k), op_opt)
         end
      end

      prev = c
   end   
end

local function tk_sets(input)
   local n = input:len()
   local i, j = 0, 0

   for k = 1, n do
      local c = input:sub(k, k)

      if c == '[' and i == 0 then
         i = k
      end

      if c == ']' then
         j = k
         break
      end
   end

   if i == 0 or j == 0 or i >= j then
      return nil
   end

   --
   local k = j + 1 
   local ends  = input:sub(k, k)
   local token = nil 

   if ends == '*' then
      token = Token(i, k, set_star, input:sub(i, j), op_star)
      token.forbidden = forb_set 

   elseif ends == "+" then
      token = Token(i, k, set_plus, input:sub(i, j), op_plus)
      token.forbidden = forb_set

   elseif ends == "?" then
      token = Token(i, k, set_opt, input:sub(i, j), op_opt)
      token.forbidden = forb_set

   else
      token = Token(i, j, set, handle_ranges(input:sub(i + 1, j - 1)))
   end

   return token
end

local function tk_set_comp(input)
   local len  = input:len()
   local i, j = 0, 0

   for k = 1, len do
      local c = input:sub(k, k)

      if c == '[' and i == 0 then
         i = k
      end

      if c == ']' then
         j = k
         break
      end
   end

   if i == 0 or j == 0 or i >= j then
      return nil
   end

   if input:sub(i + 1, i + 1) == '^' then
      local value = input:sub(i, i) .. input:sub(i + 2, j)
      local token = Token(i, j + 1, set_comp, value, op_comp)
      token.forbidden = forb_set

      return token
   end
end

local function tk_groups(input)
   local len  = input:len()
   local i, j = 0, 0

   for k = 1, len do
      local c = input:sub(k, k)

      if c == '(' and i == 0 then
         i = k
      end

      if c == ')' then
         j = k
      end
   end

   if i == 0 or j == 0 or i >= j then
      return nil
   end

   --
   local k = j + 1
   local ends = input:sub(k, k)

   if ends == '*' then
      return Token(i, k, grp_star, input:sub(i, j), op_star) 

   elseif ends == '+' then
      return Token(i, k, grp_plus, input:sub(i, j), op_plus)

   elseif ends == '?' then
      return Token(i, k, grp_opt, input:sub(i, j), op_opt)

   else
      return Token(i, j, group, input:sub(i + 1, j - 1), op_concat)
   end
end

local function tk_fix_gis(input)
   -- rules for fixing groups inside a set
   local tokset = tk_sets(input)

   if tokset then
      local subinput = input:sub(tokset.start + 1, tokset.ends - 1)
      local tokgroup = tk_groups(subinput)

      if tokgroup then
         return tokset
      end
   end
end

local Tokens = {
   tk_fix_gis,
   tk_groups,
   -- tk_set_comp,
   tk_sets,
   tk_char_star,
   tk_char_plus,
   tk_char_opt,
   tk_char,
}
-------------------------------------------------------------------------------
-- tokenizer
-------------------------------------------------------------------------------
local function tokenize(input, forbidden)
   local list = Table()
   local len  = input:len() 
   local tok  = nil

   if len == 0 then
      return nil
   end

   for i = 1, #Tokens do
      tok = Tokens[i](input)
      
      if tok and forbidden:has(tok.type) == false then
         list:append(tok)
         break
      end
   end

   if tok then
      local i = tok.start - 1
      local j = tok.ends  + 1

      if i < 0 then
         i = 0
      end

      local before = tokenize(input:sub(1, i), forbidden)
      local after  = tokenize(input:sub(j, len), forbidden)

      if before then
         list:push(unpack(before:reverse()))
      end

      if after then
         list:append(unpack(after))
      end
   end

   return list
end
-------------------------------------------------------------------------------
-- Builders for basic nfa
-------------------------------------------------------------------------------
local function nfa_char(char)
   -- build an nfa that recognize a single character

   return Nfa.new {
      states = 2,
      edges  = {
         [1] = { [char] = { 2 } },
      },

      accepting = { 2 }
   }
end

local function nfa_char_star(char)
   -- build an nfa that recognize char*

   return Nfa.new {
      states = 1,
      edges  = { 
         [1] = { [char] = { 1 } }
      },
      
      accepting = { 1 } 
   }
end

local function nfa_char_plus(char)
   -- build an nfa that recognize char+

   return Nfa.new {
      states = 2,
      edges  = { 
         [1] = { [char] = { 2 } },
         [2] = { [char] = { 2 } },
      },
      accepting = { 2 } 
   }
end

local function nfa_set(chars)
   -- build an nfa that recognize c1 U c2 U ... U cn
   local len = chars:len()
   
   local nfa = Nfa.new {
      states = 1 + len + len, 
      edges  = {
         [1] = { [epsilon] = Table.new(len, Table.increase) }
      },
      accepting = Table.new(len, function(a) return a + len + 1 end)
   }

   for i = 1, len do
      local c = chars:sub(i, i)
      local state = i + 1

      nfa:addEdge(state, c, { state + len })
   end

   return nfa
end
-------------------------------------------------------------------------------
-- Parser
-------------------------------------------------------------------------------
function Parser.new(input)
-- create a parser for the given input
   local self = setmetatable({}, parser_mt)
   self.input = input or ""

   return self
end

function Parser:parse()
-- build the parse tree (needed by Parse.compile)
   local tree = Table()
   local fifo = tokenize(self.input, Table())

   tree:append(unpack(fifo))

   while fifo:notEmpty() do
      local token = fifo:head()
      local ttype = token.type

      if not token:isSimple() then
         local tokens = tokenize(token.value, token.forbidden)
         token.childs = tokens

         fifo:append(unpack(tokens))
      end
   end

   self.tree = tree
end

-- TODO: remove parameter nfa
local function compile_aux(token, nfa, operation)
   -- print(token, operation)

   local childs = token.childs
   local ttype  = token.type
   local tvalue = token.value

   if childs:notEmpty() then
      local m1 = Nfa.new()

      childs:eachi(function(tok)
         local m2 = compile_aux(tok, nil, tok.operation)

         -- build nfa from complex tokens
         if op_concat == operation then
            m1 = m1 .. m2

         elseif op_star == operation then
            m1 = m2:star()

         elseif op_plus == operation then
            m1 = m2:plus()

         elseif op_opt == operation then
            m1 = m2:optional()  

         elseif op_union == operation then
            m1 = m1 + m2

         elseif op_comp == operation then
            m1 = m2:negation()
         end
      end)

      return m1
   end
   
   -- build basic nfa from a simple token
   if ttype == char then
      nfa = nfa_char(tvalue)

   elseif ttype == char_star then
      nfa = nfa_char_star(tvalue)

   elseif ttype == char_plus then
      nfa = nfa_char_plus(tvalue)

   elseif ttype == set then
      nfa = nfa_set(tvalue)
   end

   return nfa
end

function Parser:compile()
-- build an nfa from a tree-of-tokens
   local nfa = Nfa.new()

   self.tree:eachi(function(tok)
      nfa = nfa .. compile_aux(tok, nil, tok.operation)
   end)

   return nfa
end
-------------------------------------------------------------------------------
return Parser
-------------------------------------------------------------------------------