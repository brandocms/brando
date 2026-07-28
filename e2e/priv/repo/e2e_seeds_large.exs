# Large-entry fixtures for block editor benchmarking.
#
# NOT part of the normal e2e seed run — the entries here are big enough to slow
# down every test that lists pages. Run explicitly:
#
#   cd e2e && source .envrc && MIX_ENV=e2e mix run priv/repo/e2e_seeds_large.exs
#
# Creates two pages, both idempotent (dropped and rebuilt on re-run):
#
#   /bench-flat-5, /bench-flat-40, /bench-flat-115   flat entries, mixed module
#                  types. 115 is the regime that produced the worst numbers in
#                  this repo's history (see the assessment doc).
#   /bench-nested  40 root containers x 1 multi block x 2 entries = 160 blocks
#                  across 3 nesting levels
#
# Blocks mirror their module's refs/vars the same way
# `BlockField.build_block/5` does, so they are shaped exactly like blocks the
# editor itself would create.

import Ecto.Query

alias Brando.Content.Block
alias Brando.Content.Blocks
alias Brando.Content.Container
alias Brando.Content.Module, as: ContentModule
alias Brando.Content.Ref
alias Brando.Pages.Page
alias E2eProject.Repo

require Logger

user = Repo.one!(from(u in Brando.Users.User, order_by: [asc: u.id], limit: 1))

# Page.language is an Ecto.Enum over atoms, but the app config carries a string.
language = String.to_existing_atom(Brando.config(:default_language) || "en")

fetch_module = fn name ->
  Repo.one!(
    from(m in ContentModule,
      where: fragment("?->>'en' = ?", m.name, ^name) and is_nil(m.deleted_at),
      preload: [:vars, :refs],
      limit: 1
    )
  )
end

# Mirror of BlockField.build_block/5 — fresh uids on refs, PKs stripped from
# both refs and vars so each block owns its own copies.
build_block = fn module, type, sequence ->
  refs =
    (module.refs || [])
    |> Blocks.remove_pk_from_refs()
    |> Enum.map(fn ref ->
      %Ref{
        name: ref.name,
        description: ref.description,
        data: ref.data,
        sequence: ref.sequence,
        uid: Brando.Utils.generate_uid()
      }
    end)

  %Block{
    uid: Brando.Utils.generate_uid(),
    type: type,
    creator_id: user.id,
    module_id: module.id,
    source: Elixir.Brando.Pages.Page.Blocks,
    multi: module.multi,
    sequence: sequence,
    refs: refs,
    vars: Blocks.remove_pk_from_vars(module.vars || []),
    table_rows: [],
    block_identifiers: [],
    children: []
  }
end

delete_page = fn uri ->
  case Repo.one(from(p in Page, where: p.uri == ^uri and p.language == ^language)) do
    nil ->
      :ok

    page ->
      # Deleting the page only cascades the join rows — the blocks themselves
      # would be left orphaned and accumulate on every re-run. Drop the roots
      # explicitly; children cascade via the parent_id FK.
      root_ids =
        Repo.all(from(pb in "pages_blocks", where: pb.entry_id == ^page.id, select: pb.block_id))

      Repo.delete!(page)
      Repo.delete_all(from(b in Block, where: b.id in ^root_ids))
  end
end

# ------------------------------------------------------------------ flat pages

mixed_modules =
  Enum.map(
    ["Styled Header", "Rich Text Article", "Heading", "Video Player", "Map Embed"],
    fetch_module
  )

build_flat_page = fn count ->
  uri = "bench-flat-#{count}"
  delete_page.(uri)

  blocks =
    for i <- 0..(count - 1) do
      module = Enum.at(mixed_modules, rem(i, length(mixed_modules)))
      %Brando.Pages.Page.Blocks{block: build_block.(module, :module, i), sequence: i}
    end

  page =
    Repo.insert!(%Page{
      creator_id: user.id,
      title: "Bench — #{count} blocks",
      uri: uri,
      language: language,
      # Required by the Page changeset. Without it every save from a bench
      # fixture fails validation — the benchmark still reports a save latency,
      # because it times the round trip, not the outcome.
      template: "default.html",
      status: :published,
      is_homepage: false,
      breadcrumbs: [],
      fragments: [],
      entry_blocks: blocks
    })

  Logger.info("seeded /#{uri} with #{count} root blocks")
  {count, page.id}
end

# The size curve. 115 is the regime that produced the worst numbers in this
# repo's history (the 4 MB upload / 106 s render storm).
flat_sizes = [5, 40, 115]
flat_pages = Map.new(flat_sizes, build_flat_page)

# --------------------------------------------------------------- bench-nested

delete_page.("bench-nested")

container =
  Repo.one(from(c in Container, where: c.name == "Bench Container", limit: 1)) ||
    Repo.insert!(%Container{
      type: :liquid,
      name: "Bench Container",
      namespace: "bench",
      help_text: "Container used by the block editor benchmark fixture",
      code: "<div b-tpl=\"bench-container\">{{ content }}</div>"
    })

team_section = fetch_module.("Team Section")
team_member = fetch_module.("Team Member")

nested_blocks =
  for i <- 0..39 do
    members =
      for j <- 0..1 do
        %{build_block.(team_member, :module_entry, j) | children: []}
      end

    multi = %{build_block.(team_section, :module, 0) | children: members}

    root = %Block{
      uid: Brando.Utils.generate_uid(),
      type: :container,
      creator_id: user.id,
      container_id: container.id,
      source: Elixir.Brando.Pages.Page.Blocks,
      multi: false,
      sequence: i,
      refs: [],
      vars: [],
      table_rows: [],
      block_identifiers: [],
      children: [multi]
    }

    %Brando.Pages.Page.Blocks{block: root, sequence: i}
  end

nested_page =
  Repo.insert!(%Page{
    creator_id: user.id,
    title: "Bench — nested",
    uri: "bench-nested",
    language: language,
    template: "default.html",
    status: :published,
    is_homepage: false,
    breadcrumbs: [],
    fragments: [],
    entry_blocks: nested_blocks
  })

Logger.info("seeded /bench-nested with #{length(nested_blocks)} roots x 3 levels (160 blocks)")

# The benchmark needs stable entry ids to deep-link into the editor. Page ids
# change whenever the fixture is rebuilt, so publish them rather than making the
# bench scrape the pages list.
ids_path = Path.join([__DIR__, "..", "..", "e2e", "playwright", "bench", "fixture-ids.json"])
File.mkdir_p!(Path.dirname(ids_path))

File.write!(
  ids_path,
  Jason.encode!(
    %{
      flat: Map.new(flat_pages, fn {count, id} -> {Integer.to_string(count), id} end),
      nested: nested_page.id
    },
    pretty: true
  )
)

Logger.info("wrote #{ids_path}")
