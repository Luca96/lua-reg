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
local Nfa = require "luareg.nfa"
-------------------------------------------------------------------------------
local format = string.format
local s_char = string.char
local sub    = string.sub
local byte   = string.byte
local find   = string.find
local match  = string.match
local concat = table.concat
local sort   = table.sort
local floor  = math.floor
local huge   = math.huge
local ipairs   = ipairs
local tonumber = tonumber
local tostring = tostring
local setmetatable = setmetatable
local error_ = error

local escape = ':'
-------------------------------------------------------------------------------
-- CLASS
-------------------------------------------------------------------------------
local Parser = {}
local parser_mt = { __index = Parser }
-------------------------------------------------------------------------------
-- errors
-------------------------------------------------------------------------------
-- A syntax error is raised as a table with this metatable, so Reg.new can tell it
-- from an internal error and re-raise its message at the caller's line.
local SyntaxError = { __tostring = function(e) return e.message end }
Parser.SyntaxError = SyntaxError

local function error(message)
   error_(setmetatable({ message = message }, SyntaxError))
end

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

local function accepts_empty(m)
   -- true when the nfa accepts the empty word ""
   return m:anyAccepting(m:startStates())
end
-------------------------------------------------------------------------------
-- Repeated units (P2-14)
-------------------------------------------------------------------------------
-- power(self, node) = { unit = U, lo = l, hi = h } means that node matches what U^l,
-- U^(l+1), ..., U^h match, where U^k is k matches of U in a row and h may be huge (no
-- bound). The empty pattern is EMPTY (no unit, 0..0), which combines with any unit; a node
-- with no simpler description is its own unit, 1..1. Units are compared by key, computed
-- only when two units are compared: two nodes with the same key are the same tree, up to
-- groups, one-item sequences, the order of alternatives and the order of a set's
-- characters, so they match the same strings.
--
--    char, set, backref                      its own unit, 1..1
--    group, one-item seq or alt              the power of its item
--    seq of items with one unit U            U, the sum of the ranges: aa* is a 1..huge
--    seq of items with different units       chunks of one unit (factor), or else the
--                                            smallest period of the items: abab is (ab) 2..2
--    alt of items with one unit U            U, the union of the ranges if it has no gap:
--                                            a|aa is a 1..2, a| is a 0..1 (a|aaa: no)
--    repeat X{x,y}, X = U l..h               U x*l..y*h, if no count is left out (no_gap)
--    anything else                           its own unit, 1..1
--
-- Each step is exact: L^i L^j = L^(i+j) (sums of ranges), the union of L^S over sets of
-- counts S is L^(union of S), and k matches of L^(l..h) in a row are L^(k*l..k*h).
local EMPTY = { lo = 0, hi = 0 }

local function set_key(chars, negate)
   -- a set's characters, sorted and without duplicates ([a-ca] is "abca"); [a] keys as a
   local seen, list = {}, {}

   for i = 1, #chars do
      local c = sub(chars, i, i)

      if not seen[c] then
         seen[c] = true
         list[#list + 1] = c
      end
   end

   sort(list)
   local s = concat(list)

   if not negate and #s == 1 then
      return "c" .. s
   end

   return (negate and "N" or "S") .. #s .. ":" .. s
end

local function key(self, node)
   -- a string that names the tree of node. Every part ends with a field of fixed length
   -- or with a ':' or '}', so two different trees never get the same key
   local k = self.keys[node]

   if k == nil then
      local t = node.type

      if t == "char" then
         k = "c" .. node.char
      elseif t == "set" then
         k = set_key(node.chars, node.negate)
      elseif t == "backref" then
         k = "B" .. node.index
      elseif t == "group" then
         k = key(self, node.body)
      elseif t == "repeat" then
         k = "{" .. node.min .. "," .. (node.max or "") .. "}" .. key(self, node.node)
      elseif #node.items == 1 then
         k = key(self, node.items[1])
      else
         local keys = {}

         for i = 1, #node.items do
            keys[i] = key(self, node.items[i])
         end

         if t == "alt" then
            sort(keys)  -- the order of alternatives doesn't matter
         end

         k = (t == "seq" and "(" or "<") .. #keys .. ":" .. concat(keys)
      end

      self.keys[node] = k
   end

   return k
end

local function opaque(self, node)
   -- node is its own unit, 1..1
   return { unit = node, lo = 1, hi = 1 }
end

local function no_gap(l, h, x, y)
   -- true when the counts k*l..k*h for k = x..y (y and h may be huge) form one range.
   -- k and k + 1 leave no gap when (k + 1)*l <= k*h + 1, that is l - 1 <= k*(h - l): the
   -- smallest k, x, is the hardest. With h huge, k = 0 gives only 0, and k >= 1 gives k*l
   -- and up. (a{1,2}){1,300} is a{1,600}; (a{3}){1,2} is a{3} or a{6}: not a range
   -- (P2-14)
   if x == y then
      return true
   elseif h == huge then
      return x >= 1 or l <= 1
   end

   return l - 1 <= x * (h - l)
end

local power

local function factor(self, node)
   -- a seq whose items have different units, read as chunks of one unit U that is itself
   -- a seq of q >= 2 items: an item whose unit is U adds its range, an empty item adds
   -- nothing, and q items in a row with the keys of U's items add one match of U.
   -- ab(ab)* is (ab) 1 + (ab) 0..huge = (ab) 1..huge. Each such U among the items' units
   -- is tried; nil when none fits
   local items, tried = node.items, {}

   for i = 1, #items do
      local p = power(self, items[i])
      local unit = p.unit

      local k = unit and unit.type == "seq" and #unit.items >= 2 and key(self, unit)

      if k and not tried[k] then
         tried[k] = true

         local parts, q = unit.items, #unit.items
         local lo, hi, j = 0, 0, 1

         while j <= #items do
            local r = power(self, items[j])

            if r.unit == nil then
               j = j + 1
            elseif key(self, r.unit) == k then
               lo, hi, j = lo + r.lo, hi + r.hi, j + 1
            else
               local same = j + q - 1 <= #items

               for s = 1, q do
                  if not same then
                     break
                  end

                  same = key(self, items[j + s - 1]) == key(self, parts[s])
               end

               if not same then
                  break
               end

               lo, hi, j = lo + 1, hi + 1, j + q
            end
         end

         if j > #items then
            return { unit = unit, lo = lo, hi = hi }
         end
      end
   end

   return nil
end

local function power_of(self, node)
   local t = node.type

   if t == "group" then
      return power(self, node.body)

   elseif t == "repeat" then
      local p = power(self, node.node)

      if p.unit == nil then
         return EMPTY  -- ()*, (|){2,3}: still only ""
      end

      local x, y = node.min, node.max or huge

      if not no_gap(p.lo, p.hi, x, y) then
         return opaque(self, node)
      end

      local hi = (y == huge or p.hi == huge) and huge or y * p.hi
      return { unit = p.unit, lo = x * p.lo, hi = hi }

   elseif t ~= "seq" and t ~= "alt" then
      return opaque(self, node)  -- char, set, backref
   end

   local items = node.items

   if #items == 0 then
      return EMPTY
   elseif #items == 1 then
      return power(self, items[1])
   end

   if t == "alt" then
      local unit, k, ranges = nil, nil, {}

      for i = 1, #items do
         local p = power(self, items[i])

         if p.unit then
            if k == nil then
               unit, k = p.unit, key(self, p.unit)
            elseif key(self, p.unit) ~= k then
               return opaque(self, node)
            end
         end

         ranges[i] = p
      end

      if unit == nil then
         return EMPTY
      end

      sort(ranges, function(r, s) return r.lo < s.lo end)
      local lo, hi = ranges[1].lo, ranges[1].hi

      for i = 2, #ranges do
         if ranges[i].lo > hi + 1 then
            return opaque(self, node)  -- a count is left out: a|aaa
         elseif ranges[i].hi > hi then
            hi = ranges[i].hi
         end
      end

      return { unit = unit, lo = lo, hi = hi }
   end

   -- seq: items with one unit add their ranges
   local unit, k, lo, hi = nil, nil, 0, 0

   for i = 1, #items do
      local p = power(self, items[i])

      if p.unit then
         if k ~= nil and key(self, p.unit) ~= k then
            local f = factor(self, node)

            if f then
               return f
            end

            -- the smallest period of the items' keys: abab is (ab) 2..2
            local m, keys = #items, {}

            for j = 1, m do
               keys[j] = key(self, items[j])
            end

            for n = 1, floor(m / 2) do
               -- the last item first: a different tail ((aaa…ab)) rules a period out at once
               if m % n == 0 and keys[m] == keys[m - n] then
                  local periodic = true

                  for j = n + 1, m do
                     if keys[j] ~= keys[j - n] then
                        periodic = false
                        break
                     end
                  end

                  if periodic then
                     local first = {}

                     for j = 1, n do
                        first[j] = items[j]
                     end

                     local u = { type = "seq", items = first }
                     local count = floor(m / n)  -- an integer, also on Lua 5.3+
                     return { unit = u, lo = count, hi = count }
                  end
               end
            end

            return opaque(self, node)
         end

         unit, k, lo, hi = p.unit, k or key(self, p.unit), lo + p.lo, hi + p.hi
      end
   end

   if unit == nil then
      return EMPTY
   end

   return { unit = unit, lo = lo, hi = hi }
end

function power(self, node)
   -- memoized: each node is analysed once per compile (nested repeats would otherwise
   -- analyse their insides again at every level)
   local p = self.powers[node]

   if p == nil then
      p = power_of(self, node)
      self.powers[node] = p
   end

   return p
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

      -- one concatAll instead of chained .. : linear instead of quadratic time
      local list = {}

      for i = 1, #items do
         list[i] = compile(self, items[i])
      end

      return Nfa.concatAll(list)

   elseif t == "alt" then
      local list = {}

      for i = 1, #node.items do
         list[i] = compile(self, node.items[i])
      end

      return Nfa.unionAll(list)

   elseif t == "repeat" then
      -- count a repeated unit (P2-14): when the body matches what U^l..U^h match, the
      -- repeat {x,y} matches what U^(x*l)..U^(y*h) match, if no count is left out. So
      -- (a|aa){1,300} is a{1,600}, (aa*){1,300} is a+, (a*){0,300} is a*, ((ab)|abab){2,3}
      -- is (ab){2,6}: a few states active while matching instead of one copy per count.
      -- Also for * + ?. A new node is compiled; the tree isn't changed (backrefs share it)
      local body = power(self, node.node)

      if body.unit == nil then
         return Nfa.emptyWord()  -- ()*, (|){2,3}: only ""
      elseif body.lo ~= 1 or body.hi ~= 1 then
         local p = power(self, node)

         if p.unit ~= node then
            -- terminates: the power of a unit is the unit itself, 1..1
            return compile(self, { type = "repeat", node = p.unit, min = p.lo,
                                   max = p.hi ~= huge and p.hi or nil })
         end
      end

      local x, y = node.min, node.max
      local m = compile(self, node.node)

      if x == 0 and y == nil then
         return m:star()
      elseif x == 1 and y == nil then
         return m:plus()
      elseif x == 0 and y == 1 then
         return m:optional()
      end

      if (y == nil or y >= 2) and accepts_empty(m) then
         -- a pattern that accepts "" would keep all its copies linked through epsilons, so
         -- every copy stays active while matching (P2-14). Since "" is in L, L^k is inside
         -- L^(k+1): L{x,} = L* and L{x,y} = L^y = (L - {""}){0,y}
         if y == nil then
            return m:star()
         end

         return m:nonEmpty():times(0, y)
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

   -- an internal bug, not a syntax error: keep its position in this file
   error_(format("cannot compile node %s", tostring(t)))
end

function Parser:compile()
-- build an nfa from the syntax tree
   self.expanding = {}
   self.keys, self.powers = {}, {}  -- memo tables of the repeat analysis (P2-14)

   local m = compile(self, self.tree)

   -- a Reg keeps its parser: don't keep the memo tables with it
   self.keys, self.powers = nil, nil

   return m
end
-------------------------------------------------------------------------------
return Parser
-------------------------------------------------------------------------------
