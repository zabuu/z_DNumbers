# MSBT comparison baseline

`msbt-before-optimization-20261014.json.gz` contains the three imported MSBT
Lua sources preserved immediately before the October 14 optimization pass,
including their original author/credit headers. The JSON has a source map,
format version, date, and SHA256 values for the UTF-8 sources with normalized
line endings. It is ordinary gzip-compressed text, not executable test tooling.

`test_msbt_optimization.py` loads this immutable reference beside the current
sources to compare parser output, merge grouping/order, animations, and work
counts. It also verifies each reference hash. Keeping the fixture here makes
the test independent of local game capture/backups or Git history. The sources
in this fixture are never loaded by the game.
