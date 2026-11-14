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
-------------------------------------------------------------------------------
local Nfa = { epsilon = e }
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

local function computation_of(self, word)
   -- compute the extended transition function of a Nfa
   local len = word:len()

   if len == 0 then  
      return epsilon_closure(self, { self.current })
   end
   
   local char = word:sub(len, len)
   local states = computation_of(self, word:sub(1, len - 1))
   local new_states = table()
   
   for i = 1, #states do
      local state = states[i]
      local edges = self.edges[state] or {}

      do
         local states = edges[char]

         if states then
            new_states:append(unpack(states))
         
         elseif edges.undeft then
            -- handle undefined-transitions on state
            new_states:append(edges.undeft(state, char))
         end
      end
   end

   return epsilon_closure(self, new_states)
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
      edges[k] = { undeft = edge.undeft }

      for char, states in pairs(edge) do
         -- do not consider undeft
         if char ~= "undeft" then
            states = tb_clone(states):map(table.sum, i)
            edges[k][char] = states
         end
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

local function add_edge(edges, state, char, states)
   -- add a new edge to edges
   local edges_state = edges[state]

   if edges_state == nil then
      edges[state] = { [char] = states }

   elseif edges_state[char] == nil then
      edges_state[char] = states
   else
      -- add states to edges[state][char] (edge already exist)
      edges_state[char] = table(edges_state[char]):append(unpack(states)):unique()
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
         if type(states) == "table" then
            for j = 1, #states do
               count = max(count, states[j])
            end
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
-- creates a non-deterministic finite acceptor
   params = params or {}
   
   local self = setmetatable({}, mt)

   -- structure
   self.edges = table(params.edges)
   self.current = params.start or 1
   self.accepting = table(params.accepting)

   -- info
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
   self.accepting = table(states)
   return self
end

function Nfa:isEmpty()
-- check if the nfa has no edges
   return #self.edges == 0
end

function Nfa:copy()
-- return a new nfa that is the exact copy of the current nfa
   local edges = table()
   local accepting = table()

   copy_states(edges, self, 0)
   copy_accepting(accepting, self, 0)

   return Nfa { edges = edges, accepting = accepting, states = self.numStates }
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
   edges[1] = { [e] = { 2, k + 1 } }

   -- accepting states as union of accepting states of m1 and m2
   local accepting = table()
   copy_accepting(accepting, m1, 1)
   copy_accepting(accepting, m2, k)

   return Nfa { edges = edges, accepting = accepting, states = k + m2.numStates }
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
   local initial = { k + 1 }

   m1.accepting:eachi(function(state)
      add_edge(edges, state, e, initial)
   end)

   return Nfa { edges = edges, accepting = accepting, states = k + m2.numStates }
end

function Nfa.star(m)
-- creates a new nfa recognize L(m)*
   local edges = table()
   local start = { 2 }
   
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

   return Nfa { edges = edges, accepting = accepting, states = m.numStates + 1 }
end

function Nfa.plus(m)
-- creates an nfa that recognize L(m)+
   local edges = tb_clone(m.edges)
   local start = { 1 }
   local accepting = tb_clone(m.accepting)
   
   -- connect accepting states with start state
   accepting:eachi(function(state)
      add_edge(edges, state, e, start)
   end)   

   return Nfa {
      states = m.numStates,
      edges  = edges,
      accepting = accepting 
   }
end

function Nfa.optional(m)
-- creates an nfa that recognize L(m)? (0 or 1)
   local edges = tb_clone(m.edges)
   local accepting = tb_clone(m.accepting)

   -- connect start state to accepting states
   accepting:eachi(function(state)
      add_edge(edges, 1, e, { state })
   end)   

   return Nfa {
      states = m.numStates,
      edges  = edges,
      accepting = accepting
   }
end

-- TODO: make times build a new nfa
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
      local a = table()

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