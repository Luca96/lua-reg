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
-------------------------------------------------------------------------------
local Nfa = { epsilon = e }
local mt  = { __index = Nfa }
-------------------------------------------------------------------------------
-- private functions
-------------------------------------------------------------------------------
local function epsilon_closure(self, states)
   -- compute the epsilon closure of a set of states
   local fifo = Table(states)
   local size = #states

   if size == 0 then
      return Table()
   end

   local visited = {}
   local closure = Table()
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

local function computation_of(self, word)
   -- compute the extended transition function of a Nfa
   local len = word:len()

   if len == 0 then  
      return epsilon_closure(self, { self.current })
   end
   
   local char = word:sub(len, len)
   local states = computation_of(self, word:sub(1, len - 1))
   local new_states = Table()
   
   for i = 1, #states do
      local state = states[i]
      local edges = self.edges[state] or {}
      print("cr: "..char, "st: "..state)
      do
         local states = edges[char]

         if states then
            new_states:append(unpack(states))

         elseif self._undef then
            new_states:append(self._undef(char))
         end
      end
   end

   return epsilon_closure(self, new_states)
end

local function copy_states(edges, m, i)
   -- copy the states of m into the edges with offset i
   local k = 0

   for state, _edges in pairs(m.edges) do
      k = state + i
      edges[k] = {}

      for char, states in pairs(_edges) do
         states = Tclone(states):map(function(a) return a + i end)
         edges[k][char] = states
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

   for i = 1, #states do
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

   -- info
   self.dead = false  -- true: when reached the dead state
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

function Nfa:copy()
-- return a new nfa that is the exact copy of the current nfa
   local edges = Table()
   local accepting = Table()

   copy_states(edges, self, 0)
   copy_accepting(accepting, self, 0)

   return Nfa.new { edges = edges, accepting = accepting, states = self.numStates }
end
-------------------------------------------------------------------------------
-- UNION, CONCATENATION, STAR
-------------------------------------------------------------------------------
-- TODO: don't work
function Nfa.negation(m, chars)
-- creates a new nfa that recognize everything except L(m)
   local edges = Table()
   local final = m.numStates + 1

   copy_states(edges, m, 0)
   

   -- throw undefined transitions in an accepting state
   nfa._undef = function(c)
      print("c: " ..c)
      return final
   end   

   local nfa = Nfa { edges = edges, accepting = Table(final), states = m.numStates + 2 }

   print("\n\nedges")
   print(nfa.edges)
   print("\naccepting")
   print(nfa.accepting)

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

   -- new start state (that connects start state of m1 and m2)
   edges[1] = { [e] = { 2, k + 1 } }

   -- accepting states as union of accepting states of m1 and m2
   local accepting = Table()
   copy_accepting(accepting, m1, 1)
   copy_accepting(accepting, m2, k)

   return Nfa { edges = edges, accepting = accepting, states = k + m2.numStates }
end

function Nfa.concat(m1, m2)
-- create a new nfa that recognize L(m1)L(m2)
   if m2:isEmpty() then return m1 end
   if m1:isEmpty() then return m2 end

   local edges = Table()
   local k = m1.numStates

   copy_states(edges, m1, 0)
   copy_states(edges, m2, k)

   local accepting = Table()
   copy_accepting(accepting, m2, k)

   -- connect with epsilon-transition final states of m1 to start state of m2
   local initial = { k + 1 }

   m1.accepting:eachi(function(state)
      add_edge(edges, state, e, initial)
   end)

   return Nfa { edges = edges, accepting = accepting, states = k + m2.numStates }
end

function Nfa.star(m)
-- creates a new nfa recognize L(m)*
   local edges = Table()
   local start = { 2 }

   copy_states(edges, m, 1)

   local accepting = Table()
   copy_accepting(accepting, m, 1)

   -- new start state
   edges[1] = { [e] = start }

   -- connect accepting states with start state
   accepting:eachi(function(state)
      add_edge(edges, state, e, start)
   end)

   -- add start state to accepting state (to accept epsilon)
   accepting[#accepting + 1] = 1

   return Nfa { edges = edges, accepting = accepting, states = m.numStates + 1 }
end

function Nfa:plus()
-- make the current nfa recognize L(m)+
   local edges = self.edges
   local start = { 1 }
   local accepting = self.accepting

   -- connect accepting states with start state
   accepting:eachi(function(state)
      add_edge(edges, state, e, start)
   end)

   return self
end

function Nfa:optional()
-- make the current nfa recognize L(m)? (0 or 1)
   local edges = self.edges
   local start = edges[1]

   -- connect start state to accepting states
   self.accepting:eachi(function(state)
      add_edge(edges, 1, e, { state })
   end)

   return self  
end

function Nfa:times(x, y)
-- make the current nfa recognize L(m){x, y}
   if x == nil and y == nil then
      return self
   end

   if x == y then
      -- concat x - 1 times
      local m = self

      for i = 1, x - 1 do
         self = self .. m
      end

   elseif not y then
      -- concat x - 2 times + star
      local m = self

      for i = 1, x - 1 do
         self = self .. m
      end

      self = self .. m:star()

   else
      local m = self
      local z = y - x
      local a = Table()

      --
      for i = 1, x - 1 do
         self = self .. m
      end

      a:append(unpack(self.accepting))

      for i = 1, z - 1 do
         self = self .. m
         a:append(unpack(self.accepting))
      end

      self = self .. m
      --

      -- add epsilon-transition from saved acc. states to final states
      local edges = self.edges
      local final = self.accepting

      a:unique():eachi(function(state)
         add_edge(edges, state, e, final)
      end)
   end

   return self
end

mt.__add    = Nfa.union
mt.__concat = Nfa.concat
-------------------------------------------------------------------------------
return setmetatable(Nfa, { __call = function(t, ...) return Nfa.new(...) end })
-------------------------------------------------------------------------------