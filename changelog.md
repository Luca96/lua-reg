# Lua-Reg Changelog

## Unreleased

### Tests and docs
- **CI.** A GitHub Actions workflow (`.github/workflows/test.yml`) runs the busted suite on
  Lua 5.1, 5.2, 5.3, 5.4 and LuaJIT 2.1 on every push and pull request. All 139 tests pass on
  each of them with no code changes, so the README now lists them as supported instead of
  "tested on Lua 5.4 only", and the CI item is gone from the Roadmap.

## (0.5.0) 16/11/2026
Versions now follow [semantic versioning](https://semver.org): this release comes after 0.04.
The parser and the search engine were rewritten, and every issue found in an audit of the
engine is fixed (the IDs P0-1 … P3-10 below also name their regression tests in `spec/`).
Some changes break code written for 0.04: see *Upgrading from 0.04* in the README.

### Breaking changes
- **Group numbering.** Groups are numbered by their `(` from left to right, as in other engines,
  and a quantified group counts once: in `(ab(123))+(000)*`, `\1` is `(ab(123))`, `\2` is `(123)`
  and `\3` is `(000)`. They used to be numbered outermost first, and `(a)*` took two numbers
  (`\1` = `(a)*`, `\2` = `(a)`)
- **Strict syntax.** A malformed pattern raises an error that names the position, instead of being
  matched literally: unbalanced `(`, `)`, `[`, `]` (P2-2), a stray `}`, a quantifier with nothing
  to repeat (`*a`, `+`) or after another quantifier (`a**`, `a*?`), a bad count (`a{1,2,3}`,
  `a{1.5}`, `a{x}`; no more warning printed to stdout), an empty set `[]`, a trailing `:` (P3-2).
  Write a literal `]` as `:]`, e.g. `:[abc:]`
- **Escaped letters and digits are errors** (`:a`, `:5`), reserved for future classes such as
  `:d`; punctuation can still be escaped
- **Empty matches are reported.** `Reg"a*":find"bbb"` returns `"", 1` (it was `"", 0`), and
  `findall`/`finder`/`split` include empty matches, following Lua 5.4's `string.gmatch`:
  `Reg"a*":findall"baaac"` gives `"", "aaa", ""`
- **`{,n}` allows zero repetitions** (0 to n), as in other regex engines; it used to mean 1 to n
- **A lone `|` matches the empty string** (two empty alternatives); it used to match a literal `|`
- **A negative `init` in `find(str, init)` counts from the end** of the string, as in
  `string.find` (it used to be treated as 1); `init` may also be a numeric string, and anything
  else raises *bad argument #2 to 'find'*
- **The modules are namespaced.** `parser.lua` and `nfa.lua` moved to `src/luareg/`:
  `require "nfa"` is now `require "luareg.nfa"` (and `"parser"` is `"luareg.parser"`).
  `require "luareg"` is unchanged

### New
- runs on Lua 5.2 – 5.4 too (`unpack` is now `table.unpack`, `table.maxn` replaced by a local
  helper); tested on 5.4
- a recursive-descent parser reads the pattern left to right and builds a syntax tree, replacing
  the token rules that scanned the whole pattern
- a one-pass search: `find(str, init)` returns the leftmost-longest match at `init` or later, and
  `finder`, `findall` and `split` share one iteration rule (matches come in order)
- arguments are checked like Lua's string functions: a `nil` subject is `""` in every method, a
  number subject or pattern becomes a string (`Reg"1":matches(1)`, `Reg(123)`), and any other type
  raises *bad argument #1 to 'matches' (string expected, got table)* (P3-1)
- errors are plain messages without color codes, and syntax errors point at the line that
  compiled the regex instead of a line in `parser.lua` (P3-8)
- Nfa class:
  - `Nfa.emptyWord()`: an nfa that accepts only the empty string;
  - `Nfa.default` edges, taken on a character that has no edge of its own (they replace the
    `undeft` function);
  - `Nfa:search(str, init)` (start and end of the leftmost-longest match),
    `Nfa:startStates()` and `Nfa:step(states, char)`;
  - `Nfa.concatAll(list)` and `Nfa.unionAll(list)`, which build an nfa from many operands and
    copy each one once

### Fixed
- wrong results (P0):
  - a failed compile no longer breaks later ones: each parse keeps its own group and
    backreference lists (P0-1)
  - `?` after a group no longer accepts wrong strings, e.g. `(a*b)?` matching `a` (P0-2)
  - `{n,m}` after a group no longer accepts wrong strings, e.g. `(ba*|c){1,2}` matching `ca` (P0-3)
  - zero bounds work: `{0,m}` allows 0 to m repetitions and `{0,}` is `*` (P0-4)
  - `|` works outside a group (`a|b`, `x(a)|b`), and an escaped `:|` can be quantified (P0-5)
- crashes and hangs (P1):
  - a `%` inside a set no longer crashes: `[%]`, `[a%]`, `[%a-c]` (P1-1)
  - an unterminated quantifier such as `[a]{2` or `(a){2` raises an "unterminated quantifier"
    error instead of overflowing the stack (P1-2)
  - an empty group `()` matches only the empty string, also with a quantifier (`()*`, `(){2}`)
    and in a union: `(a|())` means "a or nothing" (P1-3)
  - `{,0}` and negative lower bounds such as `{-1,2}` are rejected with a quantifier error
    instead of crashing or being accepted (P1-4)
  - the empty pattern `Reg ""` (and `Reg(nil)`) matches only the empty string (P1-5)
  - a group inside a set, like the `(a)` of `[(a)](b)\1`, no longer takes a group number, so
    `\1` refers to `(b)` instead of failing to compile (P1-6)
  - a backreference inside the group it refers to, like `(a\1)`, raises an error instead of
    overflowing the stack (P1-7)
- parsing, search and speed (P2):
  - an escape inside a set is not part of the set: `[:]a]` is `]` or `a` (P2-1)
  - an empty alternative works: `(a|)` is "a or nothing", and so are `(|a)`, `(a||b)`, `a|`
    (P2-3)
  - a backreference can be quantified: `(a)\1*` (P2-4)
  - escapes pair up from the left: `:::*` is a literal `:` followed by a literal `*` (P2-5)
  - a `)` inside a set doesn't close a group: `(a[)]b)` matches `a)b` (P2-6)
  - `{n}` counts apply to single characters: `a{2}` matches `aa` (P2-7)
  - `finder` returns indices into the original string, and ends (P2-8)
  - `find` no longer skips earlier matches or misses one-character inputs, so `findall` returns
    matches in order and `split` finds every split point (P2-9)
  - set complement works: `[^abc]` accepts every other character, also inside groups, unions and
    repeats (P2-10)
  - long input (P2-11): `matches` loops over the characters instead of recursing (300,000
    characters take about 1 s; it used to run out of memory), and searching is linear (`a*b` on
    20,000 characters takes 0.1 s; `find` used to be O(n³))
  - big patterns compile in linear time (P2-12): `[a]{1000}` takes milliseconds instead of 6 s,
    and long literals or many alternatives no longer slow down quadratically
  - a wide `{n,m}` range matches in time linear in the subject (P2-13): `[a]{1,1000}` on 1,000
    characters takes about 7 ms instead of 1.7 s, and its nfa has half the states. `{n,m}` is
    built as m copies whose accepting states, from the n-th on, are accepting, instead of a
    chain of optional copies that kept every copy left active (that chain came from the P0-3
    fix; 0.04 was fast here only through the bug P0-3 fixed)
- robustness and code quality (P3):
  - `Nfa:addEdge` changes only the given state: edge lists are never changed in place, so lists
    that several states share (after `..`, `star`, `plus`) stay intact (P3-6)
  - `Nfa.new` copies the tables it is given (it used to keep them and set their metatable), and
    counts states and checks for emptiness without `#`, so an nfa without `edges[1]` is no longer
    taken for an empty one (P3-7)
  - compiling a regex no longer sets a global `nfa` (P3-9)
  - `copy`, `..`, `+`, `star` and `plus` keep an nfa's start state when it isn't state 1
    (`Nfa{ ..., start = 3 }`); they used to assume state 1 (P3-10)
  - removed unused local variables from the sources

### Tests and docs
- a busted unit test suite (`spec/`), with a regression test for every fix above
- README: two examples fixed (a literal `:` must be escaped as `::`; the backreference sample
  follows the documented group numbering), new *Limitations* and *Upgrading from 0.04* sections,
  and a roadmap of what is still missing

## (0.04) 17/07/2018:
- updated code due to luatable update
- added set-complement feature
- various fix in nfa class
- token rules for char now are unified into tk_chars

## (0.03) 28/06/2018:
- added: Reg.find(), Reg.finder(), Reg.split()
- improved Reg.split()
- now reserved characters can be escaped with ':' 

## (0.02) 17/06/2018:
- optimized epsilon_closure of nfa, now is about 2x faster
- fixed a bug into tk_groups (_token.input_ instead of _token.value_)
- fixed a bug about the wrong behavior of tk_group (solved by balancing brakets)
- added token-rules for group-backreference
- now token:isSimple() is a property
- added Reg:findall()
- fixed a bug into tk_char_star, tk_char_plus and tk_char_opt
- implemented unions inside groups: `(A|B|C)`
- some fix about unions of expressions

## (0.01) 03/06/2018:
- added: group, group star, group plus
- added token-rule to fix groups inside a set
- fixed a bug inside tk_sets
- code clean-up and optimization for tk_sets and tk_groups
- new quantifier: ?
- new token-rules: char_opt, set_opt, grp_opt
- added new quantifiers: {n}, {n, m}, {,n}, {n,} and corresponding tokens