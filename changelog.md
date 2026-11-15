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