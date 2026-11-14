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
local table = require "luatable"
local Nfa   = require "nfa"
-------------------------------------------------------------------------------
local type   = type 
local pairs  = pairs 
local abs    = math.abs 
local s_char = string.char 
local format = string.format 
local unpack = table.unpack or unpack
local remove = table.remove
local error_ = error 
local assert = assert 
local tostring = tostring 
local tonumber = tonumber 
local setmetatable = setmetatable 
local getmetatable = getmetatable 

local err  = "\27[1;31mError: \27[0m"
local warn = "\27[1;33mWarning: \27[0m"
local epsilon = Nfa.epsilon
local escape  = ':'
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
   ['|'] = true,
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
      childs    = table(),
      forbidden = table(),  -- not allowed childs's type
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

-- for group backreference and union: filled by tk_groups and tk_backref while
-- Parser:parse runs. Each parse rebinds them to fresh tables and keeps its own
-- (self.groups, self.backrefs), so a parse or compile that fails halfway can't
-- leave stale tokens for the next one.
local group_list = table()
local back_list  = table()
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
local set_comp  = "set_complement"
local set_opt   = "set_optional"
local set_times = "set_times"
local group     = "group"
local grp_star  = "group_star"
local grp_plus  = "group_plus"
local grp_opt   = "group_optional"
local grp_times = "group_times"
local g_backref = "group_backref"
local token_or  = "token_or"
-------------------------------------------------------------------------------
-- token operation constants
-------------------------------------------------------------------------------
local op_concat = "op_concat"
local op_union  = "op_union"
local op_star   = "op_star"
local op_plus   = "op_plus"
local op_comp   = "op_complement"
local op_opt    = "op_optional"
local op_times  = "op_times" 
-------------------------------------------------------------------------------
-- token forbidden types
-------------------------------------------------------------------------------
local forb_set = table {
   char_star, 
   char_plus, 
   char_opt , 
   group    , 
   grp_star , 
   grp_plus , 
   grp_opt  ,
   g_backref
}
-------------------------------------------------------------------------------
-- Ranges:
-------------------------------------------------------------------------------
local range_intervals = table (
   48,  57 ,  --0-9
   65,  90 ,  --A-Z
   97,  122   --a-z
)

local function find_ranges(input)
   -- finds all ranges inside input string
   local k = 1
   local i = 0
   local n = input:len()
   local ranges = table()

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
      end

      -- {,m} means {0,m}
      n = n or 0

      if n < 0 then
         error("bad number for quantifier {n, m} in " .. input .. ", n must be >= 0!")
      end

      if m then
         if m <= 0 then
            error("bad number for quantifier {n, m} in " .. input .. ", m must be > 0!")

         elseif m < n then
            error("bad numbers for quantifier {n, m} in " .. input .. ", n must be <= m!")
         end
      end

      return n, m, d
   end
end

local function handle_or(group)
   -- check if group contains some balanced unions
   local tokens = group.childs
   local size = #tokens
   local list = {}
   local k = 1

   for i = 1, size do
      local tok = tokens[i]

      if tok.type == token_or then
         -- check if prev and next tokens are not token_or
         if i == 1 or i == size then
            return {}         
         else
            local prev = tokens[i - 1]
            local next = tokens[i + 1]

            if prev.type == token_or or next.type == token_or then
               return {}
            else
               list[k] = i
               k = k + 1
            end
         end   
      end
   end

   return list 
end
-------------------------------------------------------------------------------
-- Tokens definitions
-------------------------------------------------------------------------------
local function tk_char(input)
   local len = input:len()
   local tok = nil

   if len == 1 then
      tok = Token(1, 1, char, input:sub(1, 1))
      tok.isSimple = true

      return tok

   elseif len >= 2 then
      local c1 = input:sub(1, 1)
      local c2 = input:sub(2, 2)

      if c1 == escape then
         tok = Token(1, 2, char, c2)
      else
         tok = Token(1, 1, char, c1)
      end

      tok.isSimple = true

      return tok
   end
end

local function tk_chars(input)
   local len = input:len()
   local snd = nil
   local trd = nil

   for k = 1, len do
      local c = input:sub(k, k)

      if (c == '*' or c == '+' or c == '?') and snd then
         -- handle escaped characters
         if trd == escape then
            local tk_value = input:sub(k - 1, k - 1)

            -- determine token type
            if c == '*' then
               local token = Token(k - 2, k, char_star, tk_value)
               token.isSimple = true
               return token

            elseif c == '+' then
               local token = Token(k - 2, k, char_plus, tk_value)
               token.isSimple = true
               return token
            else
               return Token(k - 2, k, char_opt, tk_value, op_opt)
            end

         elseif snd ~= escape and not reserved[snd] then
            k = k - 1
            local tk_value = input:sub(k, k)

            -- determine token type
            if c == '*' then
               local token = Token(k, k + 1, char_star, tk_value)
               token.isSimple = true
               return token

            elseif c == '+' then
               local token = Token(k, k + 1, char_plus, tk_value)
               token.isSimple = true
               return token
            else
               return Token(k, k + 1, char_opt, tk_value, op_opt)
            end
         end
      end

      -- keep track of 2nd and trd char behind c
      trd = snd
      snd = c
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
   local len  = input:len()
   local snd  = nil 
   local trd  = nil
   local i, j = 0, 0

   for k = 1, len do
      local c = input:sub(k, k)

      if c == '[' and i == 0 then
         -- handle escaped chars
         if snd ~= escape or trd == escape then
            i = k
         end

      elseif c == ']' then
         -- handle escaped chars
         if snd ~= escape or trd == escape then
            j = k
            break
         end
      end

      -- keep track of 2nd and trd char behind c
      trd = snd
      snd = c
   end

   if i == 0 or j == 0 or i >= j then
      return nil
   end

   -- determine set type
   local k = j + 1 
   local ends  = input:sub(k, k)
   local token = nil 

   -- set star:
   if ends == '*' then
      token = Token(i, k, set_star, input:sub(i, j), op_star)
      token.forbidden = forb_set 

   -- set plus:
   elseif ends == "+" then
      token = Token(i, k, set_plus, input:sub(i, j), op_plus)
      token.forbidden = forb_set

   -- set opt:
   elseif ends == "?" then
      token = Token(i, k, set_opt, input:sub(i, j), op_opt)
      token.forbidden = forb_set

   -- set times:
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

   -- set complement:
   elseif input:sub(i + 1, i + 1) == '^' then
      token = Token(i, j, set, handle_ranges(input:sub(i + 2, j - 1)))
      token.negate = true
      token.isSimple = true 

   -- set:
   else
      token = Token(i, j, set, handle_ranges(input:sub(i + 1, j - 1)))
      token.isSimple = true
   end

   return token
end

local function tk_groups(input)
   local len  = input:len()
   local snd  = nil 
   local trd  = nil
   local i, j = 0, 0
   local h = 0

   for k = 1, len do
      local c = input:sub(k, k)

      if c == '(' then
         -- handle escaped chars
         if snd ~= escape or trd == escape then
            h = h + 1

            if i == 0 then
               i = k
            end
         end

      elseif c == ')' then
         -- handle escaped chars
         if snd ~= escape or trd == escape then
            h = h - 1

            if h == 0 then
               -- parenthesis are balanced (group is valid)
               j = k
               break
            end
         end
      end

      -- keep track of 2nd and trd char behind c
      trd = snd
      snd = c
   end

   if i == 0 or j == 0 or i >= j then
      return nil
   end

   -- determine group type
   local k = j + 1
   local ends  = input:sub(k, k)
   local token = nil

   -- group star:
   if ends == '*' then
      token = Token(i, k, grp_star, input:sub(i, j), op_star) 

   -- group plus:
   elseif ends == '+' then
      token = Token(i, k, grp_plus, input:sub(i, j), op_plus)

   -- group opt:
   elseif ends == '?' then
      token = Token(i, k, grp_opt, input:sub(i, j), op_opt)

   -- group times:
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

   -- group:
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

local function tk_or(input)
   local c = input:sub(1, 1)
   
   if c == '|' then
      local token = Token(1, 1, token_or, c)
      token.isSimple = true

      return token
   end
end

local Tokens = {
   tk_fix_gis,
   tk_groups,
   tk_sets,
   tk_or,
   tk_chars,
   tk_backref,
   tk_char,
}
-------------------------------------------------------------------------------
-- tokenizer
-------------------------------------------------------------------------------
local function tokenize(input, forbidden)
   local list = table()
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
         list:push(unpack(before))
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

   return Nfa {
      states = 2,
      edges  = {
         [1] = { [char] = { 2 } },
      },

      accepting = { 2 }
   }
end

local function nfa_char_star(char)
   -- build an nfa that recognize char*

   return Nfa {
      states = 1,
      edges  = { 
         [1] = { [char] = { 1 } }
      },
      
      accepting = { 1 } 
   }
end

local function nfa_char_plus(char)
   -- build an nfa that recognize char+

   return Nfa {
      states = 2,
      edges  = { 
         [1] = { [char] = { 2 } },
         [2] = { [char] = { 2 } },
      },
      accepting = { 2 } 
   }
end

local function nfa_set(chars, complement)
   -- build an nfa that recognize c1 U c2 U ... U cn
   local len   = chars:len()
   local edges = { [1] = { [epsilon] = table.init(len, table.increase) } }
   local count = len + 2
   local final = { count }
      
   if complement then
      -- handle set-complement
      count = count + 1

      for i = 1, len do
         local c = chars:sub(i, i)
         
         edges[i + 1] = { 
            [c] = { count },
            undeft = function(state, char)
               -- check that char in not inside chars
               for i = 1, len do
                  if char == chars:sub(i, i) then
                     return
                  end
               end

               return state + count - i
            end
         }
      end 
   else
      -- set without complement
      for i = 1, len do
         local c = chars:sub(i, i)
         edges[i + 1] = { [c] = final }
      end
   end

   return Nfa {
      states = count,
      edges  = edges,
      accepting = final, 
   }
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
   group_list = table()
   back_list  = table()
   self.groups   = group_list
   self.backrefs = back_list

   local tree = table()
   local fifo = tokenize(self.input, table())

   tree:append(unpack(fifo))

   while not fifo:empty() do
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
   -- print(token, operation)

   local childs = token.childs
   local tktype = token.type
   local tvalue = token.value

   if not childs:empty() then
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

         elseif op_times == operation then
            m1 = m2:times(token.min, token.max)
         end
      end)

      return m1
   end
   
   -- build basic nfa from a simple token
   if tktype == char then
      return nfa_char(tvalue)

   elseif tktype == char_star then
      return nfa_char_star(tvalue)

   elseif tktype == char_plus then
      return nfa_char_plus(tvalue)

   elseif tktype == set then
      -- consider set-complement
      return nfa_set(tvalue, token.negate)

   elseif tktype == token_or then
      -- a '|' left outside any union, e.g. the escaped '|' of ':|?'
      return nfa_char(tvalue)
   end

   error(format("cannot compile token %s (%s)", tostring(tvalue), tostring(tktype)))
end

local function split_unions(group)
   -- rebuild group.childs as a union when it contains balanced '|' tokens
   local index  = handle_or(group)
   local size   = #index
   local childs = group.childs

   if size > 0 then
      -- group contains unions, so:
      group.operation = op_union

      local root = table()
      local c = 1

      size = size + 1
      index[size] = #childs + 1

      -- rebuilt group.childs by adding tokens between '|'
      for k = 1, size do
         local t = table()
         local j = index[k] - 1

         -- token info
         local v = ""

         for h = c, j do
            local tok = childs[h]
            v = v .. tok.value
            t:append(tok)
         end

         c = j + 2

         -- this will make parser concatenate tokens between '|'
         local token  = Token(0, 0, token_or, v, op_concat)
         token.childs = t

         root:append(token)
      end

      --
      group.childs = root

   else
      -- threat the '|' token as char token
      for i = 1, #childs do
         local tok = childs[i]

         if tok.type == token_or then
            tok.type = char
         end
      end
   end
end

local function resolve_backrefs(groups, backrefs)
   -- replace backref. tokens with referenced groups
   for i = 1, #backrefs do
      local token = backrefs[i]
      local index = token.index
      local group = groups[index]

      if group == nil then
         error("wrong group-backreference for group index: " .. index)
      else
         group:copy(token)
         token.type = g_backref .. index
      end
   end
end

function Parser:compile()
-- build an nfa from a tree-of-tokens
   -- the top-level tokens act as an (unnumbered) group, so that top-level unions
   -- like a|b are split the same way as (a|b)
   local root = Token(0, 0, group, self.input, op_concat)
   root.childs = self.tree

   split_unions(root)

   for i = 1, #self.groups do
      split_unions(self.groups[i])
   end

   resolve_backrefs(self.groups, self.backrefs)

   return compile_aux(root, root.operation)
end
-------------------------------------------------------------------------------
return Parser
-------------------------------------------------------------------------------