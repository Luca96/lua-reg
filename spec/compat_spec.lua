-- Regression tests for Lua 5.2+ support: the library used the global `unpack` and
-- `table.maxn`, which Lua 5.2 removed.
local Nfa = require "luareg.nfa"
local h = require "helpers"

describe("Lua 5.2+ compatibility", function()

   -- reload lua-reg's modules, so they cache `unpack` while the global is missing
   local function fresh_reg()
      for _, name in ipairs { "luareg", "luareg.parser", "luareg.nfa" } do
         package.loaded[name] = nil
      end
      return require "luareg"
   end

   it("compiles and matches without a global unpack", function()
      local saved = rawget(_G, "unpack")
      _G.unpack = nil

      local ok, result = pcall(function()
         return (fresh_reg()("([a-z]+|[0-9]+)x"):matches("abcx"))
      end)

      _G.unpack = saved
      assert.is_true(ok, result)
      assert.is_true(result)
   end)

   it("copies nfas without table.maxn", function()
      local saved = rawget(table, "maxn")
      table.maxn = nil

      local ok, result = pcall(h.accepts, "(ab)+c", "ababc")

      table.maxn = saved
      assert.is_true(ok, result)
      assert.is_true(result)
   end)

   it("copies every state of an nfa whose edges table has holes", function()
      -- state 2 has no outgoing edges, so edges[2] is nil: # could stop at 1
      local m = Nfa {
         states = 4,
         edges  = { [1] = { a = { 3 } }, [3] = { b = { 4 } } },
         accepting = { 4 },
      }

      assert.is_true((m:copy():compute("ab")))
      assert.is_true(((m .. m):compute("abab")))
   end)
end)
