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
-- Nfa: Non-deterministic Finite Acceptors
-------------------------------------------------------------------------------
local table = require "luatable"
-------------------------------------------------------------------------------
local setmetatable = setmetatable 
local unpack = table.unpack or unpack
local insert = table.insert
local remove = table.remove 
local pairs  = pairs
local next   = next
local iter   = table.iter
local ipairs = ipairs 
local type   = type 
local max    = math.max 

local tb_eachi  = table.eachi
local tb_clone  = table.clone
local tb_append = table.append
local tb_insert = table.insert
local tb_unique = table.unique
local tb_klist  = table.keyList

local void = function() end
local e = "epsilon"  -- epsilon
local d = "default"  -- taken on a character that has no edge of its own
-------------------------------------------------------------------------------
local Nfa = { epsilon = e, default = d }
local mt  = { __index = Nfa }
-------------------------------------------------------------------------------
-- private functions
-------------------------------------------------------------------------------
local function epsilon_closure(self, states)
   -- compute the epsilon closure of a set of states
   local fifo = table(states)
   local size = #states

   if size == 0 then
      return table()
   end

   local visited = {}
   local closure = table()
   local edges = self.edges
   local n = #fifo
   local k = 1

   local base = 1
   local top  = #fifo 

   while base <= top do
      local state = fifo[base]
      base = base + 1
      
      if not visited[state] then
         visited[state] = true
         closure[k] = state
         k = k + 1

         local states = (edges[state] or {})[e]

         if states then

            for i = 1, #states do
               local state = states[i]
               top = top + 1
               fifo[top] = states[i]
            end
         end
      end
   end

   return closure
end


local function maxn(t)
   -- largest positive integer key of t (table.maxn was removed in Lua 5.2);
   -- unlike #t it is not fooled by holes in the edges table
   local n = 0

   for k in pairs(t) do
      if type(k) == "number" and k > n and k % 1 == 0 then
         n = k
      end
   end

   return n
end

local function copy_states(edges, m, i)
   -- copy the states of m into the edges with offset i
   local k = 0
   local m_edges = m.edges

   for state = 1, maxn(m_edges) do
      local edge = m_edges[state] or {}
      
      k = state + i
      edges[k] = {}

      -- every value is a list of states (characters, epsilon and default alike)
      for char, states in pairs(edge) do
         edges[k][char] = tb_clone(states):map(table.sum, i)
      end
   end

   return k
end

local function copy_accepting(accepting, m, i)
   -- copy accepting states into accepting with offset i
   for state in m.accepting:iter() do
      accepting:append(state + i)
   end 
end

local function copy_list(states)
   -- a fresh enhanced copy of a list of states
   local list = table()

   for i = 1, #states do
      list[i] = states[i]
   end

   return list
end

local function add_edge(edges, state, char, states)
   -- add a new edge to edges.
   -- Edge lists are values: they are never changed in place, so several states (or
   -- several nfas) can share one list. A new edge stores a copy of `states`; adding
   -- to an existing edge builds a new merged list.
   local edges_state = edges[state]

   if edges_state == nil then
      edges[state] = { [char] = copy_list(states) }

   elseif edges_state[char] == nil then
      edges_state[char] = copy_list(states)
   else
      local merged = copy_list(edges_state[char])
      merged:append(unpack(states))
      edges_state[char] = merged:unique()
   end
end

local function count_states(edges, accepting, start)
   -- the number of states: the highest state that has edges, is the target of an
   -- edge, is accepting or is the start state (holes in edges don't matter)
   local count = max(maxn(edges), start or 0)

   for _, edge in pairs(edges) do
      for _, states in pairs(edge) do
         for j = 1, #states do
            count = max(count, states[j])
         end
      end
   end

   for i = 1, #accepting do
      count = max(count, accepting[i])
   end

   return count
end
-------------------------------------------------------------------------------
-- COMPUTATION
-------------------------------------------------------------------------------
function Nfa:startStates()
-- the states the nfa is in before reading anything (the start state's closure)
   return epsilon_closure(self, { self.current })
end

function Nfa:step(states, char)
-- the states reached from `states` by reading the one-character string `char`.
-- A state follows its edge for char; if it has none, its default edge (if any).
-- An explicit empty list ({}) for char means "no move", even with a default edge.
   local edges = self.edges
   local out, n = {}, 0

   for i = 1, #states do
      local edge = edges[states[i]]

      if edge then
         local targets = edge[char] or edge[d]

         if targets then
            for j = 1, #targets do
               n = n + 1
               out[n] = targets[j]
            end
         end
      end
   end

   return epsilon_closure(self, out)
end

function Nfa:anyAccepting(states)
-- true when one of `states` is an accepting state
   local accepting = self.accepting
   local set = {}

   for i = 1, #accepting do
      set[accepting[i]] = true
   end

   for i = 1, #states do
      if set[states[i]] then
         return true
      end
   end

   return false
end

local function closure_cache(self)
-- the epsilon closure of each single state, computed on first use and kept on
-- the nfa (Nfa:addEdge drops it, since a new edge can change closures)
   local cache = self.closures

   if cache == nil then
      cache = {}
      self.closures = cache
   end

   return function(state)
      local c = cache[state]

      if c == nil then
         c = epsilon_closure(self, { state })
         cache[state] = c
      end

      return c
   end
end

function Nfa:search(str, init)
-- leftmost-longest match of the nfa inside str, starting at index init or later.
-- Returns the start and end index of the match (end = start - 1 for an empty
-- match), or nil. One pass over str (time linear in its length), like a Pike VM:
-- a thread is a state plus the index where its match started. Threads are kept
-- ordered by start, earliest first; when two reach the same state the earlier one
-- wins, since both have the same future. A new thread starts at each index until
-- a match is found; from then on later-starting threads are dropped, and the
-- earliest start keeps extending its end while it can.
   local n = #str
   local edges = self.edges
   local closure = closure_cache(self)
   local start = closure(self.current)

   local accepting = {}

   for i = 1, #self.accepting do
      accepting[self.accepting[i]] = true
   end

   local states, starts, present = {}, {}, {}
   local best_start, best_end
   local pos = init or 1

   while true do
      -- start a new thread at pos while nothing has matched yet
      if best_start == nil then
         for k = 1, #start do
            local s = start[k]

            if not present[s] then
               present[s] = true
               states[#states + 1] = s
               starts[#starts + 1] = pos
            end
         end
      end

      -- the first accepting thread has the earliest start
      for k = 1, #states do
         if accepting[states[k]] then
            if best_start == nil or starts[k] <= best_start then
               best_start, best_end = starts[k], pos - 1
            end

            break
         end
      end

      -- once something matched, threads that started later can't win
      if best_start then
         local m = #states

         while m > 0 and starts[m] > best_start do
            states[m], starts[m] = nil, nil
            m = m - 1
         end
      end

      if pos > n or (best_start and #states == 0) then
         break
      end

      -- step every thread on the character at pos, keeping the order
      local char = str:sub(pos, pos)
      local next_states, next_starts, next_present = {}, {}, {}

      for k = 1, #states do
         local edge = edges[states[k]]
         local targets = edge and (edge[char] or edge[d])

         if targets then
            for j = 1, #targets do
               local c = closure(targets[j])

               for h = 1, #c do
                  local s = c[h]

                  if not next_present[s] then
                     next_present[s] = true
                     next_states[#next_states + 1] = s
                     next_starts[#next_starts + 1] = starts[k]
                  end
               end
            end
         end
      end

      states, starts, present = next_states, next_starts, next_present
      pos = pos + 1
   end

   return best_start, best_end
end

function Nfa:compute(word)
-- true when the nfa accepts the whole word (also returns the word).
-- A plain loop over the characters: no recursion and no substring copies.
   local states = self:startStates()
   local sub = word.sub

   for k = 1, #word do
      if #states == 0 then
         break
      end

      states = self:step(states, sub(word, k, k))
   end

   return self:anyAccepting(states), word
end
-------------------------------------------------------------------------------
-- NEW
-------------------------------------------------------------------------------
local function make(edges, accepting, states, start)
-- builds an nfa that adopts the given tables: only for tables the caller has just
-- built and keeps no reference to (Nfa.new copies what it is given)
   local self = setmetatable({}, mt)

   -- structure
   self.edges = table(edges)
   self.current = start or 1
   self.accepting = table(accepting)

   -- info
   self.numStates = states or count_states(edges, accepting, start)

   return self
end

function Nfa.new(params)
-- creates a non-deterministic finite acceptor from
-- { edges = { [state] = { [char] = { states } } }, accepting = { states },
--   states = number of states (optional), start = start state (default 1) }.
-- The given tables are copied: changing the nfa doesn't change them, or vice versa.
   params = params or {}

   local edges = table()

   for state, edge in pairs(params.edges or {}) do
      local copy = {}

      for char, states in pairs(edge) do
         copy[char] = copy_list(states)
      end

      edges[state] = copy
   end

   return make(edges, copy_list(params.accepting or {}), params.states, params.start)
end

function Nfa.emptyWord()
-- creates a one-state nfa that accepts only the empty word "".
-- Unlike Nfa.new() (no edges: the identity that union and concat skip), it has
-- an edges[1] entry, so union, concat, star... treat it as a real operand.
-- Concatenating it leaves a language unchanged: L .. {""} = L.
   return make({ [1] = {} }, { 1 }, 1)
end
-------------------------------------------------------------------------------
-- building
-------------------------------------------------------------------------------
function Nfa:addEdge(state, char, states)
-- add a new edge to current nfa
   add_edge(self.edges, state, char, states)
   self.closures = nil  -- cached epsilon closures may have changed
end

function Nfa:acceptingStates(states)
-- change the accepting states of the current nfa 
   self.accepting = table(states)
   return self
end

function Nfa:isEmpty()
-- check if the nfa has no edges
   return next(self.edges) == nil
end

function Nfa:copy()
-- return a new nfa that is the exact copy of the current nfa
   local edges = table()
   local accepting = table()

   copy_states(edges, self, 0)
   copy_accepting(accepting, self, 0)

   return make(edges, accepting, self.numStates, self.current)
end
-------------------------------------------------------------------------------
-- UNION, CONCATENATION, STAR,...
-------------------------------------------------------------------------------
function Nfa.union(m1, m2)
-- creates a new nfa that recognize L(m1 U m2)
   if m2:isEmpty() then return m1 end
   if m1:isEmpty() then return m2 end

   local edges = table()
   local k = m1.numStates + 1
   
   copy_states(edges, m1, 1)
   copy_states(edges, m2, k)

   -- new start state (that connects start state of m1 and m2)
   edges[1] = { [e] = { m1.current + 1, m2.current + k } }

   -- accepting states as union of accepting states of m1 and m2
   local accepting = table()
   copy_accepting(accepting, m1, 1)
   copy_accepting(accepting, m2, k)

   return make(edges, accepting, k + m2.numStates)
end

function Nfa.concat(m1, m2)
-- create a new nfa that recognize L(m1)L(m2)
   if m2:isEmpty() then return m1 end
   if m1:isEmpty() then return m2 end

   local edges = table()
   local k = m1.numStates
   
   copy_states(edges, m1, 0)
   copy_states(edges, m2, k)

   local accepting = table()
   copy_accepting(accepting, m2, k)

   -- connect with epsilon-transition final states of m1 to start state of m2
   local initial = { m2.current + k }

   m1.accepting:eachi(function(state)
      add_edge(edges, state, e, initial)
   end)

   return make(edges, accepting, k + m2.numStates, m1.current)
end

local function non_empty(list)
-- the operands of list that aren't empty nfas (Nfa.new(): the identity of .. and +)
   local out = {}

   for i = 1, #list do
      if not list[i]:isEmpty() then
         out[#out + 1] = list[i]
      end
   end

   return out
end

function Nfa.concatAll(list)
-- creates an nfa that recognize L(m1)L(m2)...L(mn), for list = { m1, ..., mn }.
-- The result is the same as m1 .. m2 .. ... .. mn (same states, edges, start and
-- accepting states), but each operand is copied only once: chaining .. copies
-- everything built so far at every step, which takes time quadratic in n.
-- Empty nfas are skipped, as .. does; with no operand left the result is Nfa.new(),
-- with one it is that operand itself.
   local ms = non_empty(list)

   if #ms == 0 then
      return Nfa.new()
   elseif #ms == 1 then
      return ms[1]
   end

   local edges = table()
   local k = 0
   local last  -- the accepting states of the previous operand, at their offset

   for i = 1, #ms do
      local m = ms[i]
      copy_states(edges, m, k)

      if last then
         -- connect with epsilon-transitions the previous operand to this one's start
         local initial = { m.current + k }

         for j = 1, #last do
            add_edge(edges, last[j], e, initial)
         end
      end

      last = table()
      copy_accepting(last, m, k)
      k = k + m.numStates
   end

   return make(edges, last, k, ms[1].current)
end

function Nfa.unionAll(list)
-- creates an nfa that recognize L(m1) U L(m2) U ... U L(mn), for list = { m1, ..., mn }.
-- Same language as m1 + m2 + ... + mn, but with a single new start state (state 1)
-- linked to every operand's start, and each operand copied only once (chaining +
-- copies everything built so far at every step, and nests one start state per +).
-- Empty nfas are skipped, as + does; with no operand left the result is Nfa.new(),
-- with one it is that operand itself.
   local ms = non_empty(list)

   if #ms == 0 then
      return Nfa.new()
   elseif #ms == 1 then
      return ms[1]
   end

   local edges = table()
   local accepting = table()
   local starts = {}
   local k = 1

   for i = 1, #ms do
      local m = ms[i]
      copy_states(edges, m, k)
      copy_accepting(accepting, m, k)
      starts[i] = m.current + k
      k = k + m.numStates
   end

   -- new start state (that connects the start states of every operand)
   edges[1] = { [e] = starts }

   return make(edges, accepting, k)
end

function Nfa.star(m)
-- creates a new nfa recognize L(m)*
   local edges = table()
   local start = { m.current + 1 }
   
   copy_states(edges, m, 1)

   local accepting = table()
   copy_accepting(accepting, m, 1)

   -- new start state
   edges[1] = { [e] = start }

   -- connect accepting states with start state
   accepting:eachi(function(state)
      add_edge(edges, state, e, start)
   end)

   -- add start state to accepting state (to accept epsilon)
   accepting[#accepting + 1] = 1

   return make(edges, accepting, m.numStates + 1)
end

function Nfa.plus(m)
-- creates an nfa that recognize L(m)+
   local edges = tb_clone(m.edges)
   local start = { m.current }
   local accepting = tb_clone(m.accepting)
   
   -- connect accepting states with start state
   accepting:eachi(function(state)
      add_edge(edges, state, e, start)
   end)   

   return make(edges, accepting, m.numStates, m.current)
end

function Nfa.optional(m)
-- creates an nfa that recognize L(m)? (0 or 1)
-- union with a one-state nfa that accepts only the empty word: the union adds a
-- new start state, so loops back into m's start state can't be skipped through
-- (an epsilon from m's own start state to its accepting states would allow that)
   return Nfa.emptyWord() + m
end

function Nfa:times(x, y)
-- returns a new nfa that recognize L(m){x, y}: x copies of m followed by y - x
-- optional copies (or by m* when y is nil). x defaults to 0. Without bounds, or
-- when the result is a single copy, the current nfa itself is returned.
-- Built with one Nfa.concatAll, so the time is linear in the number of copies.
   if x == nil and y == nil then
      return self
   end

   x = x or 0

   local list = {}

   for i = 1, x do
      list[i] = self
   end

   if y == nil then
      list[#list + 1] = self:star()
   else
      local opt = self:optional()

      for i = 1, y - x do
         list[#list + 1] = opt
      end
   end

   return Nfa.concatAll(list)
end

mt.__add    = Nfa.union
mt.__concat = Nfa.concat
-------------------------------------------------------------------------------
return setmetatable(Nfa, { __call = function(t, ...) return Nfa.new(...) end })
-------------------------------------------------------------------------------