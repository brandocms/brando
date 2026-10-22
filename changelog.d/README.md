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

One line per change: what a project or an editor notices, in one sentence.
The pull request holds the detail (how it works, why, measurements, edge
cases).

```markdown
- Opening an entry shows its fields at once, without a loading modal.
```

An entry that asks the reader to act (a breaking change, a deprecation, a
migration to run, config to add, code to change) follows its line with those
steps, indented two spaces: the commands and code to change, without the
reasoning.

```markdown
- `ai:` on a form input is deprecated in favour of `ai_actions:`.
  Replace `ai: [prompt: "…", context: [:title]]` with
  `ai_actions: [generate: [prompt: "…", from: [:title]]]`.
```

Changes a Brando project cannot see (tests, CI, refactors, agent docs) have
no entry. An entry is a list item starting `- `, with no headings.

Leave the pull request link out, so the PR needs no second commit once it is
open: collation adds it. It finds the merge that brought the fragment into the
branch ("Merge pull request #N from …") and ends the entry's first sentence
with `([#N](https://github.com/brandocms/brando/pull/N))`, before its full
stop. An entry that already links or numbers a pull request keeps it: write
the link yourself for a change that reached `main` through another pull
request, such as one stacked on it.

`scripts/changelog check` (part of `mix check` and CI) validates the names
and text.

## Into CHANGELOG.md

`scripts/changelog collate` moves the fragments into the unreleased section,
adding the pull request links, and deletes them: at release (see `RELEASE.md`), since the Hex package ships
`CHANGELOG.md`, and in a PR of its own whenever `CHANGELOG.md` on `main`
should catch up. Until then the unreleased entries are read here. The
published documentation does not include the changelog.

PRs opened before fragments existed still edit `CHANGELOG.md` directly;
nothing rejects that.
