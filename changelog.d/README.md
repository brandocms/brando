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

The ordered upgrade steps live in the migration guide
(`guides/migrating_from_053.md`), which `### Upgrading` links to: a change
that adds a step edits the guide.

## Text

One line per change: what a project or an editor notices, in one sentence,
and a link to the pull request. The pull request holds the detail (how it
works, why, measurements, edge cases).

```markdown
- Opening an entry shows its fields at once, without a loading modal ([#3112](https://github.com/brandocms/brando/pull/3112)).
```

An entry that asks the reader to act (a breaking change, a deprecation, a
migration to run, config to add, code to change) follows its line with those
steps, indented two spaces: the commands and code to change, without the
reasoning.

```markdown
- `ai:` on a form input is deprecated in favour of `ai_actions:` ([#3094](https://github.com/brandocms/brando/pull/3094)).
  Replace `ai: [prompt: "…", context: [:title]]` with
  `ai_actions: [generate: [prompt: "…", from: [:title]]]`.
```

Changes a Brando project cannot see (tests, CI, refactors, agent docs) have
no entry. Add the link once the pull request is open. An entry is a list item
starting `- `, with no headings.

## Into CHANGELOG.md

`scripts/changelog collate` moves the fragments into the unreleased section
and deletes them: at release (see `RELEASE.md`), since the Hex package ships
`CHANGELOG.md`, and in a PR of its own whenever `CHANGELOG.md` on `main`
should catch up. Until then the unreleased entries are read here. The
published documentation does not include the changelog.

PRs opened before fragments existed still edit `CHANGELOG.md` directly;
nothing rejects that.
