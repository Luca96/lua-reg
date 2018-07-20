# Lua-Reg Changelog

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