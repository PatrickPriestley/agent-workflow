# Keep pull requests reviewable

`pr-size` (from agent-workflow) counts the lines a branch adds, leaving out generated files
(lockfiles, fixtures, captures, snapshots, anything marked `linguist-generated`). Aim for 400
or fewer; above 1,000, split before review. One review pass, by a person or a model, covers a
large diff poorly, and a reviewer with a prompt limit silently drops files.

Split along the work, not the files:

- **One task, one pull request.** Each carries its own red test, code and mutation check,
  and passes on its own.
- **A refactor that changes no behaviour** (rename, move, extract) goes first, alone.
- **Vertical slices:** one path working end to end before the next, not one layer at a time.
- **Dependent parts as stacked pull requests:** each branch cut from the one before, merged
  in order.
- **Generated evidence** (fixtures, captures, snapshots) in a commit of its own.
- **A feature that cannot ship half done** merges behind a flag or an unwired entry point.

When fixes found along the way (review findings, live runs) would push a branch past the
limit, put them on a follow-up branch instead of growing this one. A change that truly
cannot be split (one migration, one generated client) stays whole: say why in the record's
Decisions and in the pull request.

A multi-PR change is tier 2 (see `tiers.md`): the record is approved once, and each PR body
names it.
