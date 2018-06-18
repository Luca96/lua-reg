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
local pairs  = pairs 
local abs    = math.abs 
local s_char = string.char 
local format = string.format 
local unpack = unpack 
local error_ = error 
local assert = assert 
local tostring = tostring 
local tonumber = tonumber 
local setmetatable = setmetatable 
local getmetatable = getmetatable 

local err  = "\27[1;31mError: \27[0m"
local warn = "\27[1;33mWarning: \27[0m"
local epsilon = Nfa.epsilon

-------------------------------------------------------------------------------
-- errors, warnings, assertions
-------------------------------------------------------------------------------
local function warning(message)
   print(warn .. message)
end

local function error(message)
   error_(err .. message)
end
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
   ['{'] = true,
   ['}'] = true,
}
-------------------------------------------------------------------------------
-- Token
-------------------------------------------------------------------------------
local Token = {}

local token_mt = {
   __index = Token,
   
   __tostring = function(t)
      return format(
         "Token (i: %d j: %d t: %s, v: %s, op: %s)", 
         t.start, 
         t.ends, 
         t.type, 
         t.value, 
         t.operation)
   end,
}

function Token.new(i, j, t, v, o)
-- creates a new token object
   local self = {
      start     = i,
      ends      = j,
      type      = t,
      value     = v,
      childs    = Table(),
      forbidden = Table(),  -- not allowed childs's type
      operation = o or '',
   }

   return setmetatable(self, token_mt)
end

function Token:copy(other)
-- copy the content of self into other
   for k, v in pairs(self) do
      other[k] = v
   end
end

Token = setmetatable(Token, 
   { __call = function(self, ...) return Token.new(...) end })

-- group backreferences:
local group_list = Table()
local back_list  = Table()
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
local set_times = "set_times"
local group     = "group"
local grp_star  = "group_star"
local grp_plus  = "group_plus"
local grp_opt   = "group_optional"
local grp_times = "group_times"
local g_backref = "group_backreference"
-------------------------------------------------------------------------------
-- token operation constants
-------------------------------------------------------------------------------
local op_concat = "op_concat"
local op_union  = "op_union"
local op_star   = "op_star"
local op_plus   = "op_plus"
local op_comp   = "op_comp"
local op_opt    = "op_optional"
local op_times  = "op_times" 
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
   grp_opt  ,
   g_backref
)
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
      error(format("Invalid range %s-%s at position %d", range[2], range[3], k))
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

local function handle_times(input, i)
   -- handle quantifiers like: {n}, {n,} and {n, m}
   local j = 0
   local h = 0
   local n = input:len()

   for k = i, n do
      local c = input:sub(k, k)

      if c == ',' then
         if h == 0 then
            h = k
         else
            warning("possible bad quantifier in " .. input)
            return
         end
      end

      if c == '}' and j == 0 then
         j = k
         break
      end
   end

   local d = j - i + 1

   if h == 0 then
      -- no comma (1 number)
      local n = tonumber(input:sub(i, j - 1))

      if n == nil then
         error("for quantifier {n} in " .. input .. ", n must be specified!")

      elseif n <= 0 then
         error("bad number for quantifier {n} in " .. input .. ", n must be > 0!")
      end

      return n, n, d

   else
      -- comma and 2 numbers
      local n = tonumber(input:sub(i, h - 1))
      local m = tonumber(input:sub(h + 1, j - 1))

      if n == nil and m == nil then
         error("for quantifier {n, m} in " .. input .. ", specify at least n or m")

      elseif m and n then 
         
         if n <= 0 and m <= 0 then
            error("bad numbers for quantifier {n, m} in " .. input .. ", n and m must be > 0!")
         
         elseif m < n then
            error("bad numbers for quantifier {n, m} in " .. input .. ", n must be <= m!")
         end   
      end 

      if m and (m > 0 and n == nil) then
         return 1, m, d 
      end

      return n, m, d
   end
end
-------------------------------------------------------------------------------
-- Tokens definitions
-------------------------------------------------------------------------------
local function tk_char(input)
   if input:len() > 0 then
      local token = Token(1, 1, char, input:sub(1, 1))
      token.isSimple = true

      return token
   end
end

local function tk_char_star(input)
   local size = input:len()
   local prev = ''
   
   for k = 1, size do
      local c = input:sub(k, k)

      if c == '*' then
         if not reserved[prev] then
            k = k - 1
            
            local token = Token(k, k + 1, char_star, input:sub(k, k))
            token.isSimple = true

            return token
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
            
            local token = Token(k, k + 1, char_plus, input:sub(k, k))
            token.isSimple = true

            return token
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

local function tk_backref(input)
   local n = input:len()

   for i = 1, n do
      local c = input:sub(i, i)
      local k = nil

      if c == '\1' then
         k = 1
      elseif c == '\2' then
         k = 2
      elseif c == '\3' then
         k = 3
      elseif c == '\4' then
         k = 4
      elseif c == '\5' then
         k = 5
      end

      if k then
         local token = Token(i, i, g_backref, '\\' .. k)
         token.index = k

         back_list:append(token)

         return token
      end
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

   elseif ends == "{" then 
      token = Token(i, j, set, nil)
      local n, m, d = handle_times(input, k + 1)

      if n or m then
         token.min = n
         token.max = m
         token.ends = k + d
         token.value = input:sub(i, j) 
         token.type  = set_times
         token.operation = op_times
      else
         token.value = handle_ranges(input:sub(i + 1, j - 1))
         token.isSimple = true
      end

   else
      token = Token(i, j, set, handle_ranges(input:sub(i + 1, j - 1)))
      token.isSimple = true
   end

   return token
end

local function tk_groups(input)
   local len  = input:len()
   local i, j = 0, 0
   local h = 0

   for k = 1, len do
      local c = input:sub(k, k)

      if c == '(' then
         h = h + 1

         if i == 0 then
            i = k
         end

      elseif c == ')' then
         h = h - 1

         if h == 0 then
            -- parenthesis are balanced (we have a valid group)
            j = k
            break
         end
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
      token = Token(i, k, grp_star, input:sub(i, j), op_star) 

   elseif ends == '+' then
      token = Token(i, k, grp_plus, input:sub(i, j), op_plus)

   elseif ends == '?' then
      token = Token(i, k, grp_opt, input:sub(i, j), op_opt)

   elseif ends == "{" then
      token = Token(i, j, group, nil, op_concat)
      local n, m, d = handle_times(input, k + 1)

      if n or m then
         token.min = n
         token.max = m
         token.ends = k + d
         token.value = input:sub(i, j) 
         token.type  = grp_times
         token.operation = op_times
      else
         token.value = input:sub(i + 1, j - 1)
      end

   else
      token = Token(i, j, group, input:sub(i + 1, j - 1), op_concat)
   end

   token.isGroup = true

   -- for backreference
   group_list:append(token)

   return token
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
   tk_sets,
   tk_char_star,
   tk_char_plus,
   tk_char_opt,
   tk_backref,
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

      if not token.isSimple then
         local tokens = tokenize(token.value, token.forbidden)
         token.childs = tokens

         fifo:append(unpack(tokens))
      end
   end

   self.tree = tree
end

local function compile_aux(token, operation)
   print(token, operation)

   local childs = token.childs
   local tktype = token.type
   local tvalue = token.value

   if childs:notEmpty() then
      local m1 = Nfa.new()

      childs:eachi(function(tok)
         local m2 = compile_aux(tok, tok.operation)

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
         
         elseif op_times == operation then
            m1 = m2:times(token.min, token.max)
         end
      end)

      return m1
   end
   
   -- build basic nfa from a simple token
   if tktype == char then
      nfa = nfa_char(tvalue)

   elseif tktype == char_star then
      nfa = nfa_char_star(tvalue)

   elseif tktype == char_plus then
      nfa = nfa_char_plus(tvalue)

   elseif tktype == set then
      nfa = nfa_set(tvalue)
   end

   return nfa
end

function Parser:compile()
-- build an nfa from a tree-of-tokens
   local nfa = Nfa.new()

   -- replace backref. tokens with referenced groups
   group_list:eachi(print)
   print "------"
   for i = 1, #back_list do
      local token = back_list[i]
      local index = token.index 
      local group = group_list[index]

      if group == nil then
         error("wrong group-backreference for group index: " .. index)
      else
         group:copy(token)
         token.type = g_backref .. index
      end
   end

   group_list:clear()
   back_list:clear()

   self.tree:eachi(function(tok)
      nfa = nfa .. compile_aux(tok, tok.operation)
   end)

   return nfa
end
-------------------------------------------------------------------------------
return Parser
-------------------------------------------------------------------------------