# Changelog fragments

A change's CHANGELOG entry goes in a file here, not in `CHANGELOG.md`, so two
pull requests never edit the same lines. GitHub's merge queue merges on the
server, without the repository's merge drivers, and drops a PR whose
CHANGELOG.md conflicts with one merged before it.

## Name

`<branch>.<section>.md`, the branch name with `/` written as `-`: branch
`wave8/migrate55-scoping` writes `wave8-migrate55-scoping.fixes.md`. A PR with
entries in two sections adds two files; several entries in one section share
a file, a blank line between them.

| Section        | Collates under      |
| -------------- | ------------------- |
| `breaking`     | `#### Breaking`     |
| `improvements` | `#### Improvements` |
| `features`     | `#### Features`     |
| `fixes`        | `#### Fixes`        |
| `dependencies` | `#### Dependencies` |
| `security`     | `#### Security`     |

The upgrade steps under `### Upgrading` are ordered prose that a change
rewrites in place: edit those in `CHANGELOG.md` itself.

## Text

The entry as `CHANGELOG.md` would hold it, in the style of the entries
already there: a list item starting `- `, with a bold lead, continuation lines
indented two spaces, and no headings.

```markdown
- **A selection whose option is no longer offered can be removed.**
  In a multi-select over a `has_many` relation, …
```

Leave the PR number out, so the PR needs no second commit once it is open:
collation adds it. It finds the merge that brought the fragment into the
branch ("Merge pull request #N from …") and puts `(#N)` after each bold lead
that has no number, moving a full stop that ends the lead after it:
`**… can be removed** (#1234).` An entry that already has a number right
after its bold lead, or at the end of it, keeps it.

`scripts/changelog check` (part of `mix check` and CI) validates the names
and text.

## Into CHANGELOG.md

`scripts/changelog collate` moves the fragments into the unreleased section,
adding the PR numbers, and deletes them: at release (see `RELEASE.md`), since the Hex package ships
`CHANGELOG.md`, and in a PR of its own whenever `CHANGELOG.md` on `main`
should catch up. Until then the unreleased entries are read here. The
published documentation does not include the changelog.

PRs opened before fragments existed still edit `CHANGELOG.md` directly;
nothing rejects that.
