# Measures the admin search (Brando.Search) on 10,000 entries.
#
#   cd e2e && source .envrc && MIX_ENV=e2e mix run bench/search_bench.exs [--entries 10000] [--keep]
#
# Stop the E2E server first: this starts the application, endpoint included.
#
# Multiplies the E2E seed data: inserts N projects (half English, half
# Norwegian) with titles and 2–5 KB introductions drawn from a word list
# with a Zipf-like spread, so a few words are on almost every entry and most
# are rare. Their identifiers are inserted as `mix brando.identifiers.sync`
# would make them. Then:
#
#   1. rebuilds the index with `Brando.Search.rebuild/1` and reports the time;
#   2. times `Brando.Search.Query.run/3` and the search page's whole query
#      (`BrandoAdmin.Search.results/3`) for common, rare, half-typed and
#      phrase queries, with and without filters (median and p95 of 20 runs);
#   3. prints EXPLAIN ANALYZE for the broadest query;
#   4. times the command palette's title search on `content_identifiers`
#      against a title search on `search_documents`.
#
# Everything it inserted is removed at the end, unless --keep.

import Ecto.Query

alias Brando.Repo
alias Brando.Search.Document
alias Brando.Search.Query

{opts, _, _} = OptionParser.parse(System.argv(), strict: [entries: :integer, keep: :boolean])
n = Keyword.get(opts, :entries, 10_000)
runs = 20
prefix = "bench-search-"

Logger.configure(level: :warning)

english = ~w(
  hotel room sea view garden house light water city coast harbour island mountain
  forest river street village market church museum gallery bridge tower station
  school library theatre restaurant kitchen table window door floor roof wall stone
  wood glass steel concrete brick timber facade courtyard terrace balcony stair
  hall corridor studio office workshop warehouse factory pier boat ferry train
  morning evening night summer winter spring autumn weather wind rain snow sun
  quiet open small large old new warm cold bright dark green blue white black
  design build restore renovate extend convert plan draw model render present
  client team architect engineer builder owner guest visitor resident neighbour
  history memory story place space time year decade century future past present
  landscape park square plaza lawn tree hedge path road route walk ride drive
  north south east west upper lower inner outer central local regional national
)

norwegian = ~w(
  hotell rom hav utsikt hage hus lys vann by kyst havn øy fjell skog elv gate
  landsby marked kirke museum galleri bro tårn stasjon skole bibliotek teater
  restaurant kjøkken bord vindu dør gulv tak vegg stein tre glass stål betong
  murstein tømmer fasade tun terrasse balkong trapp hall gang atelier kontor
  verksted lager fabrikk brygge båt ferje tog morgen kveld natt sommer vinter
  vår høst vær vind regn snø sol stille åpen liten stor gammel ny varm kald lys
  mørk grønn blå hvit svart tegne bygge restaurere utvide bygge planlegge modell
  kunde lag arkitekt ingeniør byggmester eier gjest besøkende beboer nabo
  historie minne fortelling sted rom tid år tiår århundre fremtid fortid
  landskap park torg plen tre hekk sti vei rute tur nord sør øst vest øvre
  nedre indre ytre sentral lokal regional nasjonal
)

# A word list with a Zipf-like spread: word k is drawn with weight 1/k
pick = fn words ->
  count = length(words)
  r = :rand.uniform()
  index = trunc(:math.pow(count, r)) - 1
  Enum.at(words, min(max(index, 0), count - 1))
end

sentence = fn words, length -> Enum.map_join(1..length, " ", fn _ -> pick.(words) end) end

paragraphs = fn words ->
  Enum.map_join(1..Enum.random(4..10), "", fn _ ->
    "<p>" <> String.capitalize(sentence.(words, Enum.random(50..90))) <> ".</p>"
  end)
end

timed = fn fun ->
  {micros, result} = :timer.tc(fun)
  {micros / 1000, result}
end

stats = fn fun ->
  times = Enum.map(1..runs, fn _ -> elem(timed.(fun), 0) end) |> Enum.sort()
  median = Enum.at(times, div(runs, 2))
  p95 = Enum.at(times, trunc(runs * 0.95) - 1)
  {Float.round(median, 1), Float.round(p95, 1)}
end

cleanup = fn ->
  ids = Repo.all(from(p in E2eProject.Projects.Project, where: like(p.slug, ^"#{prefix}%"), select: p.id))
  schema = to_string(E2eProject.Projects.Project)

  ids
  |> Enum.chunk_every(5_000)
  |> Enum.each(fn chunk ->
    Repo.delete_all(from(d in Document, where: d.schema == ^E2eProject.Projects.Project and d.entry_id in ^chunk))
    Repo.delete_all(from(i in "content_identifiers", where: i.schema == ^schema and i.entry_id in ^chunk))
    Repo.delete_all(from(p in E2eProject.Projects.Project, where: p.id in ^chunk))
  end)

  length(ids)
end

removed = cleanup.()
if removed > 0, do: IO.puts("Removed #{removed} entries from an earlier run")

user = Repo.one!(from(u in Brando.Users.User, where: u.email == "admin@brandocms.com"))

client =
  Repo.one(from(c in E2eProject.Projects.Client, where: c.slug == "bench-search-client")) ||
    Repo.insert!(%E2eProject.Projects.Client{
      name: "Bench client",
      slug: "bench-search-client",
      status: :published,
      language: :en,
      creator_id: user.id
    })

:rand.seed(:exsss, {1, 2, 3})
now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

IO.puts("Inserting #{n} projects…")

{insert_ms, _} =
  timed.(fn ->
    1..n
    |> Enum.chunk_every(1_000)
    |> Enum.each(fn chunk ->
      rows =
        Enum.map(chunk, fn i ->
          {language, words} = if rem(i, 2) == 0, do: {:en, english}, else: {:no, norwegian}

          status =
            case :rand.uniform(20) do
              x when x <= 12 -> :published
              x when x <= 18 -> :draft
              19 -> :pending
              _ -> :disabled
            end

          title = String.capitalize(sentence.(words, Enum.random(2..5)))
          # One entry in a thousand carries a word no other has
          intro = paragraphs.(words) <> if(rem(i, 1_000) == 7, do: "<p>Kvitsøyfyret #{i}</p>", else: "")

          %{
            title: title,
            slug: "#{prefix}#{i}",
            introduction: intro,
            language: language,
            status: status,
            client_id: client.id,
            creator_id: user.id,
            full_case: false,
            sequence: i,
            inserted_at: NaiveDateTime.add(now, -i * 60, :second),
            updated_at: NaiveDateTime.add(now, -i * 60, :second)
          }
        end)

      Repo.insert_all(E2eProject.Projects.Project, rows)
    end)
  end)

IO.puts("  #{Float.round(insert_ms / 1000, 1)} s")

schema = to_string(E2eProject.Projects.Project)

Repo.repo().query!(
  """
  INSERT INTO content_identifiers (entry_id, schema, title, status, language, updated_at)
  SELECT id, $1, title, status, language, updated_at FROM projects_projects WHERE slug LIKE $2
  ON CONFLICT (entry_id, schema) DO NOTHING
  """,
  [schema, prefix <> "%"]
)

IO.puts("Rebuilding the index…")
{rebuild_ms, {:ok, count}} = timed.(fn -> Brando.Search.rebuild() end)
IO.puts("  #{count} documents in #{Float.round(rebuild_ms / 1000, 1)} s (#{round(count / (rebuild_ms / 1000))}/s)")

Repo.repo().query!("VACUUM ANALYZE search_documents")
Repo.repo().query!("VACUUM ANALYZE content_identifiers")

%{rows: [[size, toast]]} =
  Repo.repo().query!(
    "SELECT pg_size_pretty(pg_total_relation_size('search_documents')), pg_size_pretty(pg_relation_size('search_documents_document_index'))"
  )

IO.puts("  table with indexes #{size}, GIN index #{toast}")

types = BrandoAdmin.Search.types(user)
project_type = Enum.find(types, &(&1.schema == E2eProject.Projects.Project))

cases = [
  {"common word (on every entry)", "hotel", []},
  {"mid-frequency word", "harbour", []},
  {"common word, Norwegian", "hotell", []},
  {"two words", "hotel room", []},
  {"half typed", "gard", []},
  {"one letter", "h", []},
  {"rare word", "kvitsøyfyret", []},
  {"phrase", ~s("sea view"), []},
  {"leave a word out", "hotel -room", []},
  {"common, published, type, language", "hotel",
   [status: :published, schemas: [E2eProject.Projects.Project], language: "en"]},
  {"common, page 10", "hotel", [offset: 180]},
  {"common, by date", "hotel", [sort: :updated]},
  {"nothing matches", "zzqxv", []}
]

IO.puts("\nQuery.run/3, #{runs} runs each (ms, median / p95), and the matches")

for {label, q, opts} <- cases do
  opts = Keyword.merge([limit: 20], opts)
  {median, p95} = stats.(fn -> Query.run(Document, q, opts) end)
  total = Query.run(Document, q, opts).total
  IO.puts(String.pad_trailing("  #{label} (#{q})", 58) <> "#{median} / #{p95}   #{total} matches")
end

IO.puts("\nThe search page's whole query (BrandoAdmin.Search.results/3, with authorization and rows)")

for {label, q, filters} <- [
      {"common word", "hotel", %{}},
      {"common, filtered", "hotel", %{type: project_type.key, status: "published", language: "en"}},
      {"rare word", "kvitsøyfyret", %{}}
    ] do
  f = Map.merge(%{q: q, type: nil, language: nil, status: nil, sort: "relevance", page: 1}, filters)
  {median, p95} = stats.(fn -> BrandoAdmin.Search.results(user, types, f) end)
  IO.puts(String.pad_trailing("  #{label} (#{q})", 58) <> "#{median} / #{p95}")
end

IO.puts("\nEXPLAIN ANALYZE, the broadest query (\"hotel\"): the page")

{:prefix, tsq} = Query.parse("hotel")

for {title, sql} <- [
      {"page",
       """
       SELECT d.id FROM search_documents d
       WHERE (d.config = 'norwegian' AND d.document @@ to_tsquery('norwegian', $1))
          OR (d.config = 'english' AND d.document @@ to_tsquery('english', $1))
          OR (d.config = 'simple' AND d.document @@ to_tsquery('simple', $1))
       ORDER BY CASE WHEN lower(d.title) = 'hotel' THEN 0 WHEN lower(d.title) LIKE 'hotel%' THEN 1 ELSE 2 END,
         ts_rank_cd(d.document, CASE d.config WHEN 'norwegian' THEN to_tsquery('norwegian', $1)
           WHEN 'english' THEN to_tsquery('english', $1) ELSE to_tsquery('simple', $1) END) DESC,
         CASE d.status WHEN 0 THEN 2 WHEN 2 THEN 1 WHEN 3 THEN 3 ELSE 0 END, d.updated_at DESC NULLS LAST, d.id DESC
       LIMIT 20
       """},
      {"counts",
       """
       SELECT d.schema, count(d.id) FROM search_documents d
       WHERE (d.config = 'norwegian' AND d.document @@ to_tsquery('norwegian', $1))
          OR (d.config = 'english' AND d.document @@ to_tsquery('english', $1))
          OR (d.config = 'simple' AND d.document @@ to_tsquery('simple', $1))
       GROUP BY d.schema
       """}
    ] do
  IO.puts("\n-- #{title}")
  %{rows: rows} = Repo.repo().query!("EXPLAIN (ANALYZE, BUFFERS) " <> sql, [tsq])
  Enum.each(rows, fn [line] -> IO.puts("  " <> line) end)
end

IO.puts("\nThe command palette: titles (ms, median / p95)")

palette_scope = BrandoAdmin.CommandPalette.entry_scope(user)

for q <- ["hot", "hotel", "garden house", "zzqx"] do
  {median, p95} = stats.(fn -> BrandoAdmin.CommandPalette.entries(user, q, scope: palette_scope) end)

  {fts_median, fts_p95} =
    stats.(fn ->
      Query.run(Document, q, limit: 6)
    end)

  IO.puts(
    String.pad_trailing("  #{q}", 20) <>
      "identifiers (palette today) #{median} / #{p95}    search_documents #{fts_median} / #{fts_p95}"
  )
end

if Keyword.get(opts, :keep, false) do
  IO.puts("\nKept the #{n} entries (slug #{prefix}*)")
else
  IO.puts("\nRemoved #{cleanup.()} entries")
end
