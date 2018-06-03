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
local Table = require "luatable"
-------------------------------------------------------------------------------
local setmetatable = setmetatable 
local unpack = unpack 
local insert = table.insert 
local remove = table.remove 
local pairs  = pairs 
local iter   = Table.iter
local ipairs = ipairs 
local type   = type 
local max    = math.max 

local Teachi   = Table.eachi
local Tclone   = Table.clone
local Tappend  = Table.append
local Tunique  = Table.unique
local TkeyList = Table.keyList

local e = "epsilon"  -- epsilon
local reject = -1    -- reject state index
-------------------------------------------------------------------------------
local Nfa = { epsilon = e, reject = reject }
local mt  = { __index = Nfa }
-------------------------------------------------------------------------------
-- private functions
-------------------------------------------------------------------------------
local function epsilon_closure(self, set)
   -- compute the epsilon closure of set
   local fifo = Table()

   if #set == 0 then -- to avoid warnings
      return Table()
   end
   
   fifo:append(unpack(set))

   set = {}

   while fifo:notEmpty() do
      local state = fifo:head()
      set[state]  = true

      local transt = self.edges[state] or {}
      local states = transt[e] or {}
      local len = #states

      for i = 1, len do
         local state = states[i]

         if not set[state] then
            fifo:append(state)
         end
      end
   end

   return TkeyList(set)
end

local function computation_of(self, word)
   -- compute the extended transition function of a Nfa
   local len = word:len()

   if len == 0 or current == reject then  
      return epsilon_closure(self, { self.current })
   end

   local char = word:sub(len, len)
   local states = computation_of(self, word:sub(1, len - 1))
   local new_states = Table()

   for i = 1, #states do
      local state = states[i]
      local edges = self.edges[state] or {}

      do
         local states = edges[char]

         if states then
            new_states:append(unpack(states))
         else
            new_states:append(reject)
         end
      end
   end

   return epsilon_closure(self, new_states)
end

local function copy_states(edges, m, i)
   -- copy the states of m into the edges with offset i
   local k = 0

   for state, _edges in pairs(m.edges) do
      if state ~= reject then
         k = state + i
         edges[k] = {}

         for char, states in pairs(_edges) do
            states = Tclone(states):map(function(a) return a + i end)
            edges[k][char] = states
         end
      end
   end

   return k
end

local function copy_reject(edges, m)
   -- copy the reject state of m to edges
   edges[reject] = Tclone(m.edges[reject])
end

local function copy_accepting(accepting, m, i)
   -- copy accepting states into accepting with offset i
   for state in m.accepting:iter() do
      if state == reject then
         accepting:append(reject)
      else
         accepting:append(state + i)
      end
   end 
end

local function add_edge(edges, state, char, states)
   -- add a new edge to edges
   local edges_state = edges[state]

   if edges_state == nil then
      edges[state] = { [char] = states }

   elseif edges_state[char] == nil then
      edges_state[char] = states

   else
      -- add states to edges[state][char]
      edges_state[char] = Table(edges_state[char]):append(unpack(states)):unique()
   end
end

local function merge_reject(m1, m2)
   -- return a new reject state which is the merge between reject of m1 and m2
   local m1_reject = m1.edges[reject]
   local m2_reject = m2.edges[reject]

   local state = Tclone(m1_reject)

   for char, states in pairs(m2_reject) do
      local state_char = state[char]

      if state_char == nil then
         state[char] = { [char] = states }

      else
         state[char] = Tunique(Tappend(state_char, unpack(states)))
      end
   end

   return state
end

local function count_states(m)
   -- return the number of states of m
   local count = 0
   local edges = m.edges
   local accepting = m.accepting

   for i = 1, #edges do
      local edge = edges[i] or {}

      for _, states in pairs(edge) do
         for j = 1, #states do
            count = max(count, states[j])
         end
      end
   end

   for i = 1, #accepting do
      count = max(count, accepting[i])
   end

   return count or 0
end
-------------------------------------------------------------------------------
-- COMPUTATION
-------------------------------------------------------------------------------
function Nfa:compute(word)
   local states = computation_of(self, word)
   local finals = self.accepting
   
   local size  = #states
   local index = states:find(reject)

   if index ~= nil and size > 1 then
      remove(states, index)
   end

   for i = 1, size do
      if finals:has(states[i]) then
         return true, word
      end
   end

   return false, word
end
-------------------------------------------------------------------------------
-- NEW
-------------------------------------------------------------------------------
function Nfa.new(params)
   --
   params = params or {}
   
   local self = setmetatable({}, mt)

   -- structure
   self.edges = Table(params.edges)
   self.current = params.start or 1
   self.accepting = Table(params.accepting)

   -- reject state
   self.edges[reject] = self.edges[reject] or {}

   -- info
   self.dead = false  -- true: when reached the dead state
   -- self.i = 0         -- start-index of the accepted word
   -- self.j = 0         -- end-index of the accepted word
   self.numStates = params.states or count_states(self) or 0

   return self
end
-------------------------------------------------------------------------------
-- building
-------------------------------------------------------------------------------
function Nfa:addEdge(state, char, states)
-- add a new edge to current nfa
   add_edge(self.edges, state, char, states)
end

function Nfa:acceptingStates(states)
-- change the accepting states of the current nfa 
   self.accepting = Table(states)
   return self
end

function Nfa:isEmpty()
-- check if the nfa has no edges
   return #self.edges == 0
end
-------------------------------------------------------------------------------
-- UNION, CONCATENATION, STAR
-------------------------------------------------------------------------------
-- TODO: don't work
function Nfa.negation(m)
-- creates a new nfa that recognize everything except L(m)
   local edges = Table()

   copy_states(edges, m, 0)
   copy_reject(edges, m)

   local nfa = Nfa.new { 
      edges  = edges, 
      states = m.numStates, 
      accepting = Table(reject)
   }

   return nfa
end

-- TODO: testing
function Nfa.union(m1, m2)
-- creates a new nfa that recognize L(m1 U m2)
   if m2:isEmpty() then return m1 end
   if m1:isEmpty() then return m2 end

   local edges = Table()
   local k = m1.numStates + 1

   copy_states(edges, m1, 1)
   copy_states(edges, m2, k)

   -- reject state
   edges[reject] = merge_reject(m1, m2)

   -- new start state (that connects start state of m1 and m2)
   edges[1] = { [e] = { 2, k + 1 } }

   -- accepting states as union of accepting states of m1 and m2
   local accepting = Table()
   copy_accepting(accepting, m1, 1)
   copy_accepting(accepting, m2, k)

   return Nfa.new { edges = edges, accepting = accepting, states = k + m2.numStates }
end

function Nfa.concat(m1, m2)
-- create a new nfa that recognize L(m1)L(m2)
   if m2:isEmpty() then return m1 end
   if m1:isEmpty() then return m2 end

   local edges = Table()
   local k = m1.numStates

   copy_states(edges, m1, 0)
   copy_states(edges, m2, k)

   -- reject state
   edges[reject] = merge_reject(m1, m2)

   local accepting = Table()
   copy_accepting(accepting, m2, k)

   -- connect with epsilon-transition final states of m1 to start state of m2
   local initial = { k + 1 }

   m1.accepting:eachi(function(state)
      add_edge(edges, state, e, initial)
   end)

   return Nfa.new { edges = edges, accepting = accepting, states = k + m2.numStates }
end

function Nfa.star(m)
-- creates a new nfa that recognize L(m)*
   local edges = Table()
   local start = { 2 }

   copy_states(edges, m, 1)

   local accepting = Table()
   copy_accepting(accepting, m, 1)

   -- reject state
   copy_reject(edges, m)

   -- new start state
   edges[1] = { [e] = start }

   -- connect accepting states with start state
   accepting:eachi(function(state)
      add_edge(edges, state, e, start)
   end)

   -- add start state to accepting state (to accept epsilon)
   accepting[#accepting + 1] = 1

   return Nfa.new { edges = edges, accepting = accepting, states = m.numStates + 1 }
end

function Nfa.plus(m)
-- creates a new nfa that recognize L(m)+
   local edges = Table()
   local start = { 1 }
   local accepting = Table()

   copy_states(edges, m, 0)
   copy_accepting(accepting, m, 0)

   -- reject state
   copy_reject(edges, m)

   -- connect accepting states with start state
   accepting:eachi(function(state)
      add_edge(edges, state, e, start)
   end)

   return Nfa.new { edges = edges, accepting = accepting, states = m.numStates }
end

-- function Nfa.qmark(m)
-- -- recognize L(m)? (0 or 1)
-- end

mt.__add = Nfa.union
mt.__concat = Nfa.concat
-------------------------------------------------------------------------------
return Nfa
-------------------------------------------------------------------------------