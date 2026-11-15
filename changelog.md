# Lua-Reg Changelog

## Unreleased
- runs on Lua 5.2 – 5.4 (`unpack` is now `table.unpack`, `table.maxn` replaced by a local helper)
- added a busted unit test suite (`spec/`)
- fixed two README examples: a literal `:` must be escaped as `::`, and the backreference sample
  string now follows the documented group numbering
- added a "Known issues & roadmap" section to the README
- audited the engine: the known issues are now sorted by priority (P0 – P3), each with an ID and a
  `#knownbug` test, and the README has a new "Limitations" section. Newly found: a failed compile
  breaks the next one, `?` and `{n,m}` on groups accept wrong strings, zero quantifier bounds are
  wrong, and crashes on `%` in sets, empty groups and unterminated quantifiers
- added regression tests for nested and bounded unions, optional groups, `{n}` on sets and
  ranges followed by `-`
- fixed all P0 issues:
  - a failed compile no longer breaks later ones: each parse keeps its own group and
    backreference lists (P0-1)
  - `?` after a group no longer accepts wrong strings, e.g. `(a*b)?` matching `a` (P0-2)
  - `{n,m}` after a group no longer accepts wrong strings, e.g. `(ba*|c){1,2}` matching `ca` (P0-3)
  - zero bounds work: `{0,m}` allows 0 to m repetitions and `{0,}` is `*` (P0-4)
  - `|` works outside a group (`a|b`, `x(a)|b`), and an escaped `:|` can be quantified (P0-5)
- **behaviour change:** `{,n}` now allows zero repetitions (0 to n), as in other regex engines;
  it used to mean 1 to n
- `{,0}` and negative lower bounds such as `{-1,2}` are rejected with a quantifier error instead of
  crashing or being accepted (P1-4)
- compiling a regex no longer sets a global `nfa` (P3-9)
- fixed all P1 issues:
  - a `%` inside a set no longer crashes: `[%]`, `[a%]`, `[%a-c]` (P1-1)
  - an unterminated quantifier such as `[a]{2` or `(a){2` raises an "unterminated quantifier"
    error instead of overflowing the stack (P1-2)
  - an empty group `()` matches only the empty string, also with a quantifier (`()*`, `(){2}`)
    and in a union: `(a|())` means "a or nothing" (P1-3)
  - the empty pattern `Reg ""` (and `Reg(nil)`) matches only the empty string (P1-5)
  - a group inside a set, like the `(a)` of `[(a)](b)\1`, no longer takes a group number, so
    `\1` refers to `(b)` instead of failing to compile (P1-6)
- new `Nfa.emptyWord()`: an nfa that accepts only the empty string
- new parser: a recursive-descent parser reads the pattern left to right and builds a syntax
  tree, replacing the token rules that scanned the whole pattern. It fixes all P2 parsing issues:
  - an escape inside a set is not part of the set: `[:]a]` is `]` or `a` (P2-1)
  - an empty alternative works: `(a|)` is "a or nothing", and so are `(|a)`, `(a||b)`, `a|`
    (P2-3)
  - a backreference can be quantified: `(a)\1*` (P2-4)
  - escapes pair up from the left: `:::*` is a literal `:` followed by a literal `*` (P2-5)
  - a `)` inside a set doesn't close a group: `(a[)]b)` matches `a)b` (P2-6)
  - `{n}` counts apply to single characters: `a{2}` matches `aa` (P2-7)
- a backreference inside the group it refers to, like `(a\1)`, raises an error instead of
  overflowing the stack (P1-7)
- set complement works: `[^abc]` accepts every other character, also inside groups, unions and
  repeats (P2-10). Nfa edges can have a `default` key (`Nfa.default`), taken on a character that
  has no edge of its own; it replaces the `undeft` function
- new search: `find(str, init)` returns the leftmost-longest match, found in one pass over the
  string, so it no longer skips earlier matches or misses one-character inputs (P2-9). `finder`,
  `findall` and `split` share one iteration rule: matches come in order, and `finder` returns
  indices into the original string and ends (P2-8). New `Nfa:search(str, init)` returns the start
  and end of the match
- faster on long input (P2-11): `matches` loops over the characters instead of recursing (300,000
  characters take about 1 s; it used to run out of memory), and searching is linear (`a*b` on
  20,000 characters takes 0.1 s; `find` used to be O(n³)). New `Nfa:startStates()` and
  `Nfa:step(states, char)`
- **breaking: group numbering.** Groups are numbered by their `(` from left to right, as in other
  engines, and a quantified group counts once: in `(ab(123))+(000)*`, `\1` is `(ab(123))`, `\2` is
  `(123)` and `\3` is `(000)`. They used to be numbered outermost first, and `(a)*` took two
  numbers (`\1` = `(a)*`, `\2` = `(a)`)
- **breaking: strict syntax.** A malformed pattern raises an error that names the position,
  instead of being matched literally: unbalanced `(`, `)`, `[`, `]` (P2-2), a stray `}`, a
  quantifier with nothing to repeat (`*a`, `+`) or after another quantifier (`a**`, `a*?`), a bad
  count (`a{1,2,3}`, `a{1.5}`, `a{x}`; no more warning printed to stdout), an empty set `[]`, a
  trailing `:` (P3-2). Write a literal `]` as `:]`, e.g. `:[abc:]`
- **breaking: escaped letters and digits are errors** (`:a`, `:5`), reserved for future classes
  such as `:d`; punctuation can still be escaped
- **breaking: empty matches are reported.** `Reg"a*":find"bbb"` returns `"", 1` (it was `"", 0`),
  and `findall`/`finder`/`split` include empty matches, following Lua 5.4's `string.gmatch`:
  `Reg"a*":findall"baaac"` gives `"", "aaa", ""`
- a lone `|` matches the empty string (two empty alternatives); it used to match a literal `|`

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