-----------------------------------------------------------------------------------------
-- Shared helpers for the lua-reg spec files
-----------------------------------------------------------------------------------------
local Reg = require "luareg"
local luassert = require "luassert"

local unpack = table.unpack or unpack
local helpers = {}

local function pack(...)
   return { n = select("#", ...), ... }
end

-- Recursive copy with every metatable dropped.
-- findall/split return luatable "enhanced" tables, which carry __eq = table.equal (a
-- flattening compare); luassert's `same`/`equal` honour __eq, so compare plain copies.
function helpers.plain(v, seen)
   if type(v) ~= "table" then
      return v
   end

   seen = seen or {}
   if seen[v] then
      return seen[v]
   end

   local copy = {}
   seen[v] = copy

   for k, x in next, v do
      copy[helpers.plain(k, seen)] = helpers.plain(x, seen)
   end

   return copy
end

-- Drain an iterator into a list of tuples: { {a, b}, {c, d}, ... }.
-- A safety limit stops runaway iterators from hanging the suite.
function helpers.collect(iter, limit)
   limit = limit or 1000
   local out = {}

   while true do
      local values = pack(iter())

      if values[1] == nil then
         return out
      end

      out[#out + 1] = { unpack(values, 1, values.n) }
      assert(#out <= limit, "iterator did not terminate after " .. limit .. " steps")
   end
end

-- Run fn(Reg) against freshly loaded lua-reg modules, then restore the previous ones.
-- Tests that compile patterns which raise errors use this, so that an error can never
-- leave state behind for the tests that run after them (the parser once kept its group
-- lists at module level, and a failed compile broke the next one: P0-1 in the changelog).
function helpers.fresh(fn)
   local names = { "luareg", "luareg.parser", "luareg.nfa" }
   local saved = {}

   for _, name in ipairs(names) do
      saved[name] = package.loaded[name]
      package.loaded[name] = nil
   end

   local ok, err = pcall(fn, require "luareg")

   for _, name in ipairs(names) do
      package.loaded[name] = saved[name]
   end

   if not ok then
      error(err, 0)
   end
end

-- True when the regex `pattern` matches the whole string `s`.
-- (Reg:matches also returns the word; keep only the boolean.)
function helpers.accepts(pattern, s)
   return (Reg(pattern):matches(s))
end

-- Assert that `pattern` matches every string in `yes` and none of the strings in `no`.
function helpers.check(pattern, yes, no)
   local r = Reg(pattern)

   for _, s in ipairs(yes or {}) do
      luassert.is_true(r:matches(s), ("%q should match %q"):format(pattern, s))
   end

   for _, s in ipairs(no or {}) do
      luassert.is_false(r:matches(s), ("%q should not match %q"):format(pattern, s))
   end
end

return helpers
