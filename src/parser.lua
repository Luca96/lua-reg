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
-- Parser: a recursive-descent parser that reads the pattern left to right and
-- builds a syntax tree, then compiles the tree into an Nfa.
--
--    regex := alt <end>
--    alt   := seq ('|' seq)*                -- a seq may be empty: (a|), |
--    seq   := (atom quant?)*
--    atom  := '(' alt ')' | set | ':' punct | \1 .. \5 | plain char
--    quant := '*' | '+' | '?' | '{' n '}' | '{' n? ',' m? '}'
--    set   := '[' '^'? item+ ']'
--    item  := ':' punct | c '-' c | c       -- '-' at either end is literal
-------------------------------------------------------------------------------
local Nfa = require "nfa"
-------------------------------------------------------------------------------
local format = string.format
local s_char = string.char
local sub    = string.sub
local byte   = string.byte
local find   = string.find
local match  = string.match
local concat = table.concat
local ipairs   = ipairs
local tonumber = tonumber
local tostring = tostring
local setmetatable = setmetatable
local error_ = error

local err    = "\27[1;31mError: \27[0m"
local escape = ':'
-------------------------------------------------------------------------------
-- errors
-------------------------------------------------------------------------------
local function error(message)
   error_(err .. message)
end
-------------------------------------------------------------------------------
-- CLASS
-------------------------------------------------------------------------------
local Parser = {}
local parser_mt = { __index = Parser }

-- characters with a meaning outside sets; escape them with ':' to match them
local special = {
   ['('] = true, [')'] = true, ['['] = true, [']'] = true, ['{'] = true,
   ['}'] = true, ['*'] = true, ['+'] = true, ['?'] = true, ['|'] = true,
   [escape] = true,
}

local quantifier = { ['*'] = true, ['+'] = true, ['?'] = true, ['{'] = true }

-- the classes a range x-y must stay inside
local range_intervals = {
   { 48,  57 },  -- 0-9
   { 65,  90 },  -- A-Z
   { 97, 122 },  -- a-z
}
-------------------------------------------------------------------------------
-- reading helpers
-------------------------------------------------------------------------------
function Parser:peek(offset)
-- the character at the current position (+ offset), or "" past the end
   local k = self.pos + (offset or 0)
   return sub(self.input, k, k)
end

function Parser:fail(message, pos)
-- raise a syntax error that names the position in the pattern
   error(format("%s at position %d in %s", message, pos or self.pos, self.input))
end

function Parser:escaped(pos)
-- the character after the escape at pos (checked), for ':x' outside or inside sets
   local c = sub(self.input, pos + 1, pos + 1)

   if c == "" then
      self:fail("the pattern ends with the escape character ':'", pos)

   elseif match(c, "%w") then
      -- letters and digits are reserved for future classes such as :d
      self:fail(format("unknown escape ':%s' (only punctuation can be escaped)", c), pos)
   end

   return c
end
-------------------------------------------------------------------------------
-- grammar
-------------------------------------------------------------------------------
function Parser:parse_alt()
-- alt := seq ('|' seq)*
   local items = { self:parse_seq() }

   while self:peek() == '|' do
      self.pos = self.pos + 1
      items[#items + 1] = self:parse_seq()
   end

   if #items == 1 then
      return items[1]
   end

   return { type = "alt", items = items }
end

function Parser:parse_seq()
-- seq := (atom quant?)*, up to a '|', a ')' or the end
   local items = {}

   while true do
      local c = self:peek()

      if c == "" or c == '|' or c == ')' then
         break
      end

      local node = self:parse_atom()

      if quantifier[self:peek()] then
         node = self:parse_quant(node)

         if quantifier[self:peek()] then
            self:fail(format("quantifier '%s' follows another quantifier", self:peek()))
         end
      end

      items[#items + 1] = node
   end

   return { type = "seq", items = items }
end

function Parser:parse_atom()
   local c   = self:peek()
   local pos = self.pos

   if c == '(' then
      return self:parse_group()

   elseif c == '[' then
      return self:parse_set()

   elseif c == escape then
      local x = self:escaped(pos)
      self.pos = pos + 2
      return { type = "char", char = x }

   elseif quantifier[c] then
      self:fail(format("quantifier '%s' has nothing to repeat", c))

   elseif c == ']' or c == '}' then
      self:fail(format("unbalanced '%s'", c))
   end

   local b = byte(c)

   if b >= 1 and b <= 5 then
      -- \1 .. \5 in the Lua string: a group backreference
      self.pos = pos + 1
      local node = { type = "backref", index = b, pos = pos }
      self.backrefs[#self.backrefs + 1] = node
      return node
   end

   self.pos = pos + 1
   return { type = "char", char = c }
end

function Parser:parse_group()
-- '(' alt ')'; groups are numbered by their '(' from left to right
   local open = self.pos
   self.ngroups = self.ngroups + 1

   local node = { type = "group", index = self.ngroups }
   self.groups[node.index] = node

   self.pos = open + 1
   node.body = self:parse_alt()

   if self:peek() ~= ')' then
      self:fail("unbalanced '(': missing ')'", open)
   end

   self.pos = self.pos + 1
   return node
end

local function expand_range(parser, c1, c2, pos)
-- the characters c1..c2, if both are in the same class (0-9, A-Z or a-z)
   local i, j = byte(c1), byte(c2)

   for _, interval in ipairs(range_intervals) do
      if i >= interval[1] and j <= interval[2] and i <= j then
         local s = {}

         for k = i, j do
            s[#s + 1] = s_char(k)
         end

         return concat(s)
      end
   end

   parser:fail(format("Invalid range %s-%s", c1, c2), pos)
end

function Parser:parse_set()
-- '[' '^'? item+ ']'. Inside a set only ']', ':', a leading '^' and a '-'
-- between two characters are special: [(*)] is the set of '(', '*' and ')'.
   local open = self.pos
   local negate = false
   local chars = {}

   self.pos = open + 1

   if self:peek() == '^' then
      negate = true
      self.pos = self.pos + 1
   end

   while true do
      local c   = self:peek()
      local pos = self.pos

      if c == "" then
         self:fail("unbalanced '[': missing ']'", open)

      elseif c == ']' then
         if #chars == 0 then
            self:fail("empty set (write a literal ']' as ':]')", open)
         end

         self.pos = pos + 1
         break

      elseif c == escape then
         chars[#chars + 1] = self:escaped(pos)
         self.pos = pos + 2

      else
         local c2 = self:peek(2)

         if self:peek(1) == '-' and c ~= '-' and c2 ~= '-' and c2 ~= ']' and c2 ~= "" then
            chars[#chars + 1] = expand_range(self, c, c2, pos + 1)
            self.pos = pos + 3
         else
            chars[#chars + 1] = c
            self.pos = pos + 1
         end
      end
   end

   return { type = "set", chars = concat(chars), negate = negate }
end

function Parser:parse_quant(node)
-- wrap node in a repeat: * + ? {n} {n,} {,m} {n,m}
   local c = self:peek()
   local pos = self.pos

   if c ~= '{' then
      self.pos = pos + 1

      if c == '*' then
         return { type = "repeat", node = node, min = 0 }
      elseif c == '+' then
         return { type = "repeat", node = node, min = 1 }
      end

      return { type = "repeat", node = node, min = 0, max = 1 }
   end

   local input = self.input
   local close = find(input, "}", pos + 1, true)

   if close == nil then
      self:fail("unterminated quantifier: missing '}'", pos)
   end

   local text = sub(input, pos, close)
   local body = sub(input, pos + 1, close - 1)
   local n, comma, m = match(body, "^%s*(%d*)%s*(,?)%s*(%d*)%s*$")

   if n == nil then
      self:fail(format("bad quantifier %s (expected {n}, {n,}, {,m} or {n,m})", text), pos)
   end

   n, m = tonumber(n), tonumber(m)

   if comma == "" then
      -- {n}
      if n == nil then
         self:fail(format("bad quantifier %s: n must be specified", text), pos)
      elseif n <= 0 then
         self:fail(format("bad quantifier %s: n must be > 0", text), pos)
      end

      m = n
   else
      -- {n,} {,m} {n,m}
      if n == nil and m == nil then
         self:fail(format("bad quantifier %s: specify at least n or m", text), pos)
      end

      n = n or 0

      if m and m <= 0 then
         self:fail(format("bad quantifier %s: m must be > 0", text), pos)
      elseif m and m < n then
         self:fail(format("bad quantifier %s: n must be <= m", text), pos)
      end
   end

   self.pos = close + 1
   return { type = "repeat", node = node, min = n, max = m }
end
-------------------------------------------------------------------------------
-- Builders for basic nfa
-------------------------------------------------------------------------------
local function nfa_char(char)
   -- build an nfa that recognize a single character
   return Nfa {
      states = 2,
      edges  = { [1] = { [char] = { 2 } } },
      accepting = { 2 },
   }
end

local function nfa_set(chars, complement)
   -- build a 2-state nfa that reads one character of the set (state 1 -> 2).
   -- A complement [^...] gives each listed character an explicit empty edge
   -- (no move) and every other character the default edge to state 2.
   local start = {}

   for i = 1, chars:len() do
      start[chars:sub(i, i)] = complement and {} or { 2 }
   end

   if complement then
      start[Nfa.default] = { 2 }
   end

   return Nfa {
      states = 2,
      edges  = { [1] = start },
      accepting = { 2 },
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
-- build the syntax tree (needed by Parser:compile)
   self.pos      = 1
   self.ngroups  = 0
   self.groups   = {}
   self.backrefs = {}

   local tree = self:parse_alt()

   if self.pos <= #self.input then
      -- parse_alt only stops early at a ')' that closes no group
      self:fail("unbalanced ')'")
   end

   for i = 1, #self.backrefs do
      local ref = self.backrefs[i]

      if self.groups[ref.index] == nil then
         self:fail("wrong group-backreference for group index: " .. ref.index, ref.pos)
      end
   end

   self.tree = tree
end

local function compile(self, node)
   local t = node.type

   if t == "char" then
      return nfa_char(node.char)

   elseif t == "set" then
      return nfa_set(node.chars, node.negate)

   elseif t == "seq" then
      local items = node.items

      if #items == 0 then
         return Nfa.emptyWord()
      end

      local m = Nfa.new()

      for i = 1, #items do
         m = m .. compile(self, items[i])
      end

      return m

   elseif t == "alt" then
      local m = Nfa.new()

      for i = 1, #node.items do
         m = m + compile(self, node.items[i])
      end

      return m

   elseif t == "repeat" then
      local m = compile(self, node.node)
      local x, y = node.min, node.max

      if x == 0 and y == nil then
         return m:star()
      elseif x == 1 and y == nil then
         return m:plus()
      elseif x == 0 and y == 1 then
         return m:optional()
      end

      return m:times(x, y)

   elseif t == "group" then
      local index = node.index

      if self.expanding[index] then
         -- a backreference inside the group it refers to: that is recursion,
         -- which a finite automaton can't express
         error(format("group-backreference \\%d is inside the group it refers to "
            .. "(recursion is not supported) in %s", index, self.input))
      end

      self.expanding[index] = true
      local m = compile(self, node.body)
      self.expanding[index] = nil

      return m

   elseif t == "backref" then
      -- a backreference repeats the group's pattern (not the text it matched)
      return compile(self, self.groups[node.index])
   end

   error(format("cannot compile node %s", tostring(t)))
end

function Parser:compile()
-- build an nfa from the syntax tree
   self.expanding = {}
   return compile(self, self.tree)
end
-------------------------------------------------------------------------------
return Parser
-------------------------------------------------------------------------------
