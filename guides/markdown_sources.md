# Markdown sources

Connect a public GitHub Markdown file to a **Markdown source** ref in an ordinary
content module. The module controls presentation; each placement selects its
own publishing policy. A signed push refreshes the locally stored document and
updates Follow placements without an editor save.

## Install and configure

Apply upgrade migration `Brando171AddMarkdownSources`. It adds source, version,
and audit tables to public and existing tenant schemas, shared webhook receipts,
and publication context to SSG builds. Newly created environments inherit the
content tables through the normal tenant migration/structure-cloning flow.

Configure connections in the application's `runtime.exs`. Repository identity
and permitted destinations are server settings, never webhook or editor input:

```elixir
config :brando, :markdown_sources,
  connections: %{
    "documentation" => %{
      repository: "your-organization/documentation",
      repository_id: 123456789,
      secret: System.fetch_env!("DOCUMENTATION_WEBHOOK_SECRET"),
      destinations: [nil]
    }
  }
```

Use the repository's numeric GitHub ID. Generate a separate random secret of at
least 32 bytes for each connection, store it in the deployment secret manager,
and configure the same value in GitHub. For installations without tenancy use
`[nil]`; for named environments use explicit prefixes, for example
`["tenant_acme_production", "tenant_acme_staging"]`. At most 16 destinations are
allowed per connection. Only active sites and existing configured environments
are eligible. There is no wildcard or request-selected destination.

Mount the optional plug in the application's endpoint **before `Plug.Parsers`**:

```elixir
plug BrandoWeb.Plugs.GitHubMarkdownWebhook
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Phoenix.json_library()
```

The plug requires an HTTPS connection by default. Expose the endpoint through HTTPS with valid certificates. If TLS terminates at a trusted proxy, configure the endpoint’s existing SSL/proxy rewriting before this plug. `allow_insecure: true` is available only for explicit local test setups. Configure GitHub's
repository webhook with content type `application/json`, SSL verification
enabled, the secret above, and only push events:

```text
https://cms.example.com/api/markdown-sources/webhooks/documentation
```

An authenticated setup ping returns 202. Inspect GitHub's delivery result and
the source's history after the first push. The connection name in the URL only
selects configuration; it does not authenticate the request.

## Connect a document to an entry

1. Open **Configuration → Markdown sources**, choose the configured connection,
   and enter an exact branch ref (such as `refs/heads/main`) and relative file
   path (such as `guides/installation.md`). Save and refresh to import it.
2. Add a **Markdown source** ref to a content module. Render it like any other
   ref: `{% ref refs.document %}` in Liquid, or
   `<.ref block={@block} ref={:document} />` in HEEx.
3. Add the module to an entry, choose the source, select a policy, and save.

| Policy | Behavior |
| --- | --- |
| Review updates (default) | Preview a commit, choose **Use displayed version**, then save the entry. New imports remain pending until accepted. |
| Follow updates automatically | Saving opts this placement into subsequent successful imports. No further approval is required for a push. |
| Pin a version | Select and save an immutable commit. It remains selected until explicitly changed. |

Approval always selects the exact displayed local version. Another import does
not broaden that approval. Previewing and selecting a version are separate from
saving the entry. Imported Markdown is read-only; surrounding content remains
editable. Workers update source state and stored renders, leaving open forms
and their unsaved fields alone. Entry status and block activation continue to
control public visibility.

**Check available versions** reloads locally imported versions. **Refresh from
GitHub** in the source manager fetches the configured branch. Neither public
rendering nor version preview contacts GitHub.

Connections, policies, and accepted version IDs are ordinary persisted ref data.
They survive module template updates, copy/paste, form recovery, and entry
revisions. Reviewed and pinned revisions render their selected local version.
**Restoring a Follow revision resumes following the current source**, as the
policy notice in the editor states; choose a historical version and pin it to
reproduce older content. All imported versions are retained indefinitely in this
release, including versions referenced only by revisions. Do not prune these
tables independently of revision and placement retention.

Detach a placement by clearing its source and saving the entry. Disable a source
to stop synchronization while retaining the last successful content. Once a
document is imported, its connection/ref/path identity is immutable: create a
new source to connect a different document. No destructive source deletion is
exposed while versions and placements may reference it.

## Automatic static publishing

Dynamic sites serve the rerendered local content immediately. For a live named
environment on a static site, opt the server connection into the existing SSG
build/deployment pipeline:

```elixir
%{
  repository: "your-organization/documentation",
  repository_id: 123456789,
  secret: System.fetch_env!("DOCUMENTATION_WEBHOOK_SECRET"),
  destinations: ["tenant_acme_production"],
  auto_deploy: true,
  publisher_id: 42
}
```

The publisher must be an active CMS account authorized for Markdown publishing
and the site's SSG build/deploy operations. Configure the site's deployment
strategy, persistent artifact storage, and SSG workers through
`Brando.SSG.Builds` and `Brando.SSG.Deploy`. Staging imports never automatically deploy. Source updates rerender
Follow consumers, including fragment dependencies, before requesting a build.
Saving an accepted Review/Pinned version also requests publication when enabled.

Import failures preserve the previous local version. Build or deploy failures
preserve the previous deployed artifact. Source history reports imports and
publication requests; the source row links its status to the associated build
state. Use the build's log and normal SSG retry/deploy controls for deployment
failures. Superseded Markdown artifacts are ineligible for deployment: the
source/configuration, placements, environment, publisher permissions, and
newest requested site build are checked again immediately before deployment.

## Permissions

Group authorization exposes `brando.markdown_sources.read`, `.create`, `.update`,
`.sync`, and `.publish` in standalone/site scopes. Grant backend access and the
normal entry permissions as well. `.publish` controls attachment, detachment,
policy changes, and accepting an exact version. Source management and manual
refresh require their own grants. Static automation additionally requires the
publisher's existing SSG permissions. In legacy mode, editors can read and
connect/approve placements; administrators manage and refresh sources. Tenant
membership and current account activation are rechecked server-side.

## Security and recovery

The plug authenticates a strict HMAC-SHA256 signature over the complete raw body
using constant-time comparison, before JSON parsing. Ambiguous/missing headers,
wrong repositories, unsupported events, oversized and incomplete bodies fail
closed. It accepts at most 1 MiB and limits requests per node to 120 per client
address and 1,200 globally per minute; apply distributed rate limits at the edge
when running multiple nodes. Do not trust forwarded client IP headers without a
trusted proxy configuration.

Receipt uniqueness covers both connection-scoped delivery IDs and verified body
fingerprints. Renaming a delivery header cannot replay the same body. Receipts retain the accepted Oban job IDs for processing-status lookup. Receipt
and job creation are transactional; persistence failures return 503. Jobs
coalesce queued refresh signals and serialize fetching/activation per source.
The event triggers reconciliation of the **current configured ref**, never
publication of its supplied `after` commit. Delayed deliveries and legitimate
force pushes therefore converge to the current source.

GitHub requests use fixed provider endpoints with TLS verification, pinned
public DNS addresses, no redirects or credentials, read deadlines, a 2 MB
response cap, and a 512 KB UTF-8 Markdown cap. Repository IDs and public status
are verified. Traversal, symlinks, submodules, truncated trees, compressed
responses, and non-document results are rejected. Private repositories and
arbitrary external URLs are outside this release.

External Markdown has a separate renderer from trusted CMS Markdown. It supports
paragraphs, headings, lists, blockquotes, code, tables, strikethrough, links, and
images. Raw HTML/templates, scripts, SVG, event attributes, and unsafe URL
schemes are excluded in both preview and public output. Heading IDs are stable
slugs with numeric suffixes for duplicates. Relative document links target
GitHub, and relative images target GitHub's raw host, at the imported immutable
commit. Relative paths cannot escape that repository/commit root. Absolute
HTTP(S) links/images and mail links are supported. Images load in the browser;
Brando does not fetch or proxy them. Cross-document site routing is not inferred.

The worker retries transient import failures up to five attempts. Missing refs,
deleted files, rate limits, and invalid documents retain the last good version
and expose a sanitized error. Fix the upstream/configuration problem and use
**Refresh from GitHub** to reconcile. GitHub does not automatically redeliver
failed deliveries; manual refresh also recovers deliveries the CMS never received.

Set `enabled: false` on a connection to revoke it, or remove its destination.
Workers revalidate this configuration. To rotate a secret, change the server
setting and GitHub webhook together, then verify a ping and refresh sources to
recover work cancelled during rotation. Secrets, raw webhook/document bodies,
and authorization headers are excluded from job arguments and diagnostics.
Receipt metadata is retained independently of content versions; a future receipt
retention policy must preserve in-flight work. Even without a historical receipt,
current-ref reconciliation and immutable output hashes prevent stale activation
and redundant publishing.
