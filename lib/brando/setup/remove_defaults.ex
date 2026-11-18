defmodule Brando.Setup.RemoveDefaults do
  @moduledoc """
  Takes away what `Brando.Setup.Seeds` created for the demo, once a site has
  its own content: the seed's modules (`brando-default-*`) and the homepage
  and footer fragment built from them. What `mix brando.seeds.remove_defaults`
  and `Brando.Setup.Seeds.remove_defaults/1` run.

  It lists every module of the seed's that is not in the trash, and for each
  the pages, fragments and other entries whose blocks still use it, with
  their language and admin link. With `yes: true` it moves to the trash:

    * the homepage (`index`) and the `partials/footer` fragment of each
      language, while they are exactly as the seeds created them;
    * then each module nothing uses any more.

  It never removes other content, and never a module that is still used:
  those are listed, with what to change first. Everything it removes goes to
  the trash, where it can be restored from.

  ## What counts as unchanged

  The homepage and footer are compared with what the seeds create in their
  language from the seed's modules (`Brando.Setup.Seeds`), field by field:
  every field of the entry and of each block, ref, variable and nested block,
  in order, leaving out only what a save sets by itself (ids, uids,
  timestamps, the creator, the rendered HTML, a page's breadcrumbs and
  sequence among pages, and the footer's page). The version of Brando in the
  hero's eyebrow is not compared either, so content seeded by an earlier
  version still counts. Any edit, in the admin or not, is a difference: a
  word in a ref, the title, a block hidden, taken out, added or moved, the
  status. A homepage with another fragment or a page under it is kept too:
  move those first. So is a homepage or footer with a revision that waits to
  be published (stored for later, or scheduled). Content the seeds of another
  Brando version wrote differently counts as changed, and is kept.

  With `yes: true` each environment is planned again inside the transaction
  that removes, after it has locked the page tree, the homepages and footers
  with their blocks, refs and variables, and the seed's modules. An edit or
  a new use committed before then is seen, and the plan changes with it; one
  that starts after waits for the removal to commit, and then saves to an
  entry or module in the trash, which can be restored from there. An
  environment that fails is rolled back; the error names it, and the
  environments changed before it.

  An entry in the trash counts as using its modules, so restoring it finds
  them, except the seeded homepage and footer as they were. Blocks no entry
  holds any more (kept for restoring revisions) do not count.

  ## Sites and environments

  Without tenancy it works in the application's own tables. With tenancy it
  works in every environment of every site, each on its own, narrowed by
  `:site` and `:environment`, as `mix brando.entries.resave` does.

  ## Caches

  The removals go through the content contexts, which evict the cached
  pages, fragments and modules, and render again the entries that embed a
  removed fragment. On a running node (`bin/my_app rpc`) that covers the
  node's caches, and other nodes hear of it as of an editor's delete. The Mix
  task's own VM holds no server's caches: it says to restart the server, or
  empty its caches in the admin.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Content
  alias Brando.Content.BlockReferences
  alias Brando.Pages
  alias Brando.Repo
  alias Brando.Setup.Seeds
  alias IO.ANSI

  # Each option, what it must be, and how to say so. `nil` is the default,
  # as the Mix task passes it.
  @options [
    yes: {:boolean, "true or false"},
    site: {:string, "a key, as a string"},
    environment: {:string, "a key, as a string"},
    info: {:function, "a function of one argument"}
  ]

  # What a save sets by itself, never part of the content compared
  @ignored ~w(id uid inserted_at updated_at deleted_at creator_id updated_by_id)a
  # What ties a row to what holds it, never what it refers to: a block's
  # module is content, a ref's or variable's module is its owner (a module's
  # own defaults)
  @owner_keys %{
    Content.Block => ~w(parent_id)a,
    Content.Ref => ~w(block_id module_id)a,
    Content.Var => ~w(block_id module_id page_id table_row_id table_template_id global_set_id menu_item_id)a,
    Content.TableRow => ~w(block_id)a
  }
  @entry_ignored %{
    Pages.Page => ~w(sequence breadcrumbs)a,
    Pages.Fragment => ~w(sequence page_id)a
  }

  # The hero's eyebrow names the Brando version that seeded it
  @version_line ~r/\A<p>Brando [^<]*? — installed<\/p>\z/u

  @typedoc """
  Options for `run/1`:

    * `:yes` - move what nothing uses to the trash. Without it, a dry run
      that only lists.
    * `:site` - with tenancy, only this site's environments (its key).
    * `:environment` - with tenancy, only the environment with this key, in
      each site (or in `:site`'s).
    * `:info` - prints one line of the report, a string or an `IO.ANSI`
      list. Defaults to standard output, which over `rpc` is the operator's
      session.
  """
  @type option ::
          {:yes, boolean()}
          | {:site, String.t()}
          | {:environment, String.t()}
          | {:info, (IO.ANSI.ansidata() -> any())}

  @doc """
  Lists, and with `yes: true` removes, the seed's demo content in each
  environment (see the moduledoc).

  Returns `{:ok, reports}`, one map per environment with `:site` and
  `:environment` (their keys, `nil` without tenancy), `:modules` (each with
  `:module`, `:status` — `:in_use`, `:removable` or `:removed` — and the
  `:users` that keep it) and `:entries` (the seeded homepages and footers
  that use the modules, each with `:status` — `:kept`, `:removable` or
  `:removed` — and the `:reason` one is kept). Returns `{:error, message}`,
  before anything is changed, for options it does not take, a site or
  environment that does not exist, or a node where Brando is not started;
  an environment whose removal fails is rolled back, and the error returned.
  """
  @spec run([option]) :: {:ok, [map()]} | {:error, String.t()}
  def run(opts \\ []) do
    info = printer(caller_info(opts) || (&IO.puts(ANSI.format(&1))))

    case prepare(opts) do
      # A failure says itself what was changed before it
      {:ok, targets} -> targets |> remove(opts[:yes] == true, info) |> print_error(opts, info, "")
      error -> print_error(error, opts, info, "Nothing was done: ")
    end
  end

  defp prepare(opts) do
    with :ok <- check_options(opts), :ok <- started(), do: Brando.Content.Resave.environments(opts)
  end

  # Printed here unless the caller prints it (the Mix task raises with it)
  defp print_error({:error, message} = error, opts, info, prefix) do
    unless caller_info(opts), do: info.([:red, prefix <> message])
    error
  end

  defp print_error(result, _opts, _info, _prefix), do: result

  defp caller_info(opts), do: if(Keyword.keyword?(opts) and is_function(opts[:info], 1), do: opts[:info])

  defp check_options(opts) do
    with :ok <- keyword_list(opts), :ok <- known_options(opts) do
      Enum.find_value(opts, :ok, &invalid_option/1)
    end
  end

  defp keyword_list(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, "the options must be a keyword list, got: #{inspect(opts)}"}
  end

  defp known_options(opts) do
    case opts |> Keyword.keys() |> Enum.uniq() |> Enum.reject(&Keyword.has_key?(@options, &1)) do
      [] ->
        :ok

      unknown ->
        {:error,
         "unknown option #{Enum.map_join(unknown, ", ", &"#{&1}:")}. " <>
           "It takes: #{Enum.map_join(Keyword.keys(@options), ", ", &"#{&1}:")}"}
    end
  end

  defp invalid_option({_key, nil}), do: nil

  defp invalid_option({key, value}) do
    {type, description} = Keyword.fetch!(@options, key)
    unless of_type?(type, value), do: {:error, "#{key}: must be #{description}, got: #{inspect(value)}"}
  end

  defp of_type?(:boolean, value), do: is_boolean(value)
  defp of_type?(:string, value), do: is_binary(value)
  defp of_type?(:function, value), do: is_function(value, 1)

  defp started do
    if List.keymember?(Application.started_applications(), :brando, 0),
      do: :ok,
      else: {:error, "Brando is not started on this node. In a release, run it on the running node with rpc."}
  end

  # A line the caller's output cannot take (an `rpc` session that closed) is
  # dropped rather than stopping the run
  defp printer(fun) do
    fn line ->
      try do
        fun.(line)
      catch
        _kind, _reason -> :ok
      end
    end
  end

  defp remove(targets, yes?, info) do
    case Enum.reduce_while(targets, {:ok, []}, &remove_in(&1, &2, yes?, info)) do
      {:ok, reports} ->
        reports = Enum.reverse(reports)
        finish(reports, yes?, info)
        {:ok, reports}

      {:error, message, target, reports} ->
        {:error, failed(message, target, reports)}
    end
  end

  defp remove_in(target, {:ok, reports}, yes?, info) do
    case in_environment(target, info, fn -> remove_here(yes?, info) end) do
      {:ok, report} -> {:cont, {:ok, [Map.merge(report, keys(target)) | reports]}}
      {:error, message} -> {:halt, {:error, message, target, Enum.reverse(reports)}}
    end
  end

  # The environments before the one that failed are changed: say which
  defp failed(message, target, reports) do
    changed = for report <- reports, removed?(report), do: report.name
    where = if target, do: " in #{name(target)}", else: ""

    "nothing was removed#{where}: #{message}" <>
      case changed do
        [] -> ""
        changed -> ". Already moved to the trash, as listed above: #{Enum.join(changed, ", ")}"
      end
  end

  defp removed?(report), do: Enum.any?(report.modules ++ report.entries, &(&1.status == :removed))

  defp keys(nil), do: %{site: nil, environment: nil, name: nil}
  defp keys({site, environment} = target), do: %{site: site.key, environment: environment.key, name: name(target)}

  defp name({site, environment}), do: "#{site.name} (#{site.key}) → #{environment.name} (#{environment.key})"

  defp in_environment(nil, _info, fun), do: fun.()

  defp in_environment({site, environment} = target, info, fun) do
    info.([:yellow, "\n==> #{name(target)}"])

    Boundary.with_scope(nil, fn ->
      Brando.Tenant.with_prefix(Brando.Tenant.prefix(site, environment), fun)
    end)
  end

  # ── One environment ───────────────────────────────────────────────────────

  defp remove_here(yes?, info) do
    with {:ok, plan} <- if(yes?, do: remove_planned(), else: {:ok, plan()}) do
      if plan.modules == [] and plan.entries == [] do
        info.("\nNo modules from the seeds (brando-default-*) here: nothing to remove.")
        {:ok, plan}
      else
        {:ok, show(plan, info)}
      end
    end
  end

  defp plan do
    seeded = Seeds.seeded_modules()
    uses = uses(Enum.map(Map.values(seeded), & &1.id))
    entries = uses |> Map.values() |> Enum.flat_map(&Map.keys/1) |> Enum.uniq() |> describe_entries()

    demo = demo_entries(Map.keys(entries))

    # Unchanged demo entries do not keep a module: those in the trash are
    # removed already, the others go first
    released = for {key, %{unchanged?: true}} <- demo, into: MapSet.new(), do: key

    shown_entries =
      for {key, %{trashed?: false} = entry} <- demo do
        Map.merge(Map.fetch!(entries, key), %{status: entry.status, reason: entry.reason})
      end

    modules =
      seeded
      |> Map.values()
      |> Enum.filter(&is_nil(&1.deleted_at))
      |> Enum.sort_by(&{&1.sequence, &1.uid})
      |> Enum.map(fn module ->
        {seeded_users, users} =
          uses
          |> Map.get(module.id, %{})
          |> Enum.split_with(fn {key, _count} -> MapSet.member?(released, key) end)

        users =
          users
          |> Enum.map(fn {key, count} -> Map.put(Map.fetch!(entries, key), :blocks, count) end)
          |> Enum.sort_by(&{&1.type, &1.label, &1.id})

        %{
          module: module,
          users: users,
          seeded_users: length(seeded_users),
          status: if(users == [], do: :removable, else: :in_use)
        }
      end)

    %{modules: modules, entries: Enum.sort_by(shown_entries, &{&1.type, to_string(&1.language), &1.id})}
  end

  # `%{module_id => %{{schema, entry_id} => block_count}}`, trashed entries included
  defp uses([]), do: %{}

  defp uses(module_ids) do
    blocks =
      Repo.all(from(b in Content.Block, where: b.module_id in ^module_ids, select: {b.id, b.module_id}))

    owners = BlockReferences.list_entries_for_block_ids(Enum.map(blocks, &elem(&1, 0)), include_deleted: true)

    for {block_id, module_id} <- blocks, entry <- Map.get(owners, block_id, []), reduce: %{} do
      uses -> Map.update(uses, module_id, %{entry => 1}, &Map.update(&1, entry, 1, fn count -> count + 1 end))
    end
  end

  # `%{{schema, id} => %{schema, id, type, label, url, language, trashed}}`
  defp describe_entries(keys) do
    labels = Content.Usage.labels(keys)

    rows =
      keys
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.flat_map(fn {schema, ids} ->
        fields = Enum.filter([:id, :language, :deleted_at], &(&1 in schema.__schema__(:fields)))

        from(e in schema, where: e.id in ^ids, select: map(e, ^fields))
        |> Repo.all()
        |> Enum.map(&{{schema, &1.id}, &1})
      end)
      |> Map.new()

    Map.new(keys, fn {schema, id} = key ->
      row = Map.get(rows, key, %{})
      label = Map.fetch!(labels, key)

      {key,
       %{
         schema: schema,
         id: id,
         type: schema.__naming__().singular,
         label: label.label,
         url: label.url,
         language: Map.get(row, :language),
         trashed: not is_nil(Map.get(row, :deleted_at))
       }}
    end)
  end

  # ── The seeded homepage and footer ────────────────────────────────────────

  # The homepages and footers among `keys`, each compared with what the
  # seeds create: `%{key => %{unchanged?, trashed?, status, reason}}`
  defp demo_entries(keys) do
    modules = Seeds.seeded_modules_by_key()
    footers = keys |> load(Pages.Fragment) |> Enum.filter(&(&1.parent_key == "partials" and &1.key == "footer"))
    pages = keys |> load(Pages.Page) |> Enum.filter(&(normalize(&1.uri) == "index"))

    footer_results =
      Map.new(footers, fn footer ->
        unchanged? = same?(footer, Seeds.footer_entry(footer.language, modules))
        {{Pages.Fragment, footer.id}, result(footer, unchanged?, unchanged? && waiting_revision(footer))}
      end)

    page_results =
      Map.new(pages, fn page ->
        unchanged? = same?(page, Seeds.index_page_entry(page.language, modules))
        held_by = unchanged? && (waiting_revision(page) || held_by(page, footer_results))
        {{Pages.Page, page.id}, result(page, unchanged?, held_by)}
      end)

    Map.merge(footer_results, page_results)
  end

  defp load(keys, schema) do
    case for({^schema, id} <- keys, do: id) do
      [] ->
        []

      ids ->
        preloads = Content.BlockPreloads.for_schema(schema) ++ if(schema == Pages.Page, do: [:vars], else: [])
        Repo.all(from(e in schema, where: e.id in ^ids, preload: ^preloads))
    end
  end

  defp result(entry, unchanged?, held_by) do
    trashed? = not is_nil(entry.deleted_at)

    cond do
      not unchanged? ->
        %{unchanged?: false, trashed?: trashed?, status: :kept, reason: "changed since it was seeded"}

      held_by ->
        %{unchanged?: false, trashed?: trashed?, status: :kept, reason: held_by}

      true ->
        %{unchanged?: true, trashed?: trashed?, status: :removable, reason: nil}
    end
  end

  # What keeps a homepage as seeded: pages under it, or fragments on it
  # other than a footer as seeded, which goes first
  defp held_by(page, footer_results) do
    children = Repo.all(from(p in Pages.Page, where: p.parent_id == ^page.id and is_nil(p.deleted_at)))

    fragments =
      from(f in Pages.Fragment, where: f.page_id == ^page.id and is_nil(f.deleted_at))
      |> Repo.all()
      |> Enum.reject(&match?(%{unchanged?: true}, Map.get(footer_results, {Pages.Fragment, &1.id})))

    cond do
      children != [] -> "pages are under it (#{titles(children)}): move them first"
      fragments != [] -> "fragments are on it (#{titles(fragments)}): move them to another page first"
      true -> nil
    end
  end

  # A revision stored to publish later, scheduled or not, is the editor's
  # next version of the entry: newer than the active one, or with none active
  defp waiting_revision(%schema{id: id}) do
    revisions =
      Repo.all(
        from(r in Brando.Revisions.Revision,
          where: r.entry_type == ^to_string(schema) and r.entry_id == ^id,
          select: %{revision: r.revision, active: r.active, scheduled: r.scheduled}
        )
      )

    active = revisions |> Enum.filter(& &1.active) |> Enum.map(& &1.revision) |> Enum.max(fn -> -1 end)

    if Enum.any?(revisions, &(&1.scheduled or &1.revision > active)),
      do: "a revision of it waits to be published: publish or delete it first"
  end

  defp titles(entries), do: Enum.map_join(entries, ", ", &"#{&1.title || Map.get(&1, :key)} (#{&1.language})")

  defp same?(stored, seeded), do: fingerprint(stored) == fingerprint(seeded)

  defp fingerprint(%schema{} = entry) do
    obfuscated = Keyword.get(schema.__trait__(Brando.Trait.SoftDelete) || [], :obfuscated_fields, [])

    entry
    |> record(Map.get(@entry_ignored, schema, []))
    |> Map.new(fn {field, value} -> {field, if(field in obfuscated, do: normalize(value), else: value)} end)
    |> Map.put(:blocks, entry |> Map.get(:entry_blocks) |> loaded() |> Enum.map(&join_print/1))
    |> Map.put(:vars, entry |> Map.get(:vars) |> loaded() |> Enum.map(&record/1))
  end

  defp join_print(join), do: %{sequence: join.sequence, block: block_print(join.block)}

  defp block_print(block) do
    block
    |> record(~w(rendered_html rendered_at identifier_metas sync_uid)a)
    |> Map.merge(%{
      refs: block.refs |> loaded() |> Enum.sort_by(&{&1.sequence, &1.name}) |> Enum.map(&record/1),
      vars: block.vars |> loaded() |> Enum.map(&record/1),
      table_rows: block.table_rows |> loaded() |> Enum.map(&record/1),
      children: block.children |> loaded() |> Enum.sort_by(&{&1.sequence, &1.id}) |> Enum.map(&block_print/1)
    })
  end

  # A row's own fields, without what a save sets by itself or ties it to
  # what holds it. Its embeds are compared as plain maps.
  defp record(%schema{} = row, ignored \\ []) do
    (schema.__schema__(:fields) -- (@ignored ++ Map.get(@owner_keys, schema, []) ++ ignored))
    |> Enum.reject(&rendered_field?/1)
    |> Map.new(&{&1, plain(Map.get(row, &1))})
  end

  defp rendered_field?(field), do: String.starts_with?(Atom.to_string(field), "rendered_")

  defp plain(%{__struct__: struct} = value) when struct in [DateTime, NaiveDateTime, Date, Time, Decimal], do: value

  defp plain(%{__struct__: _} = value) do
    value |> Map.from_struct() |> Map.drop([:__meta__, :id, :uid]) |> plain()
  end

  defp plain(%{} = value), do: Map.new(value, fn {key, item} -> {key, plain(item)} end)
  defp plain(value) when is_list(value), do: Enum.map(value, &plain/1)
  defp plain(value) when is_binary(value), do: String.replace(value, @version_line, "<p>Brando — installed</p>")
  # An embed's enum loads as an atom, and is built as a string
  defp plain(value) when is_atom(value) and value not in [nil, true, false], do: Atom.to_string(value)
  defp plain(value), do: value

  defp loaded(%Ecto.Association.NotLoaded{}), do: []
  defp loaded(nil), do: []
  defp loaded(list), do: list

  defp normalize(value) when is_binary(value), do: Brando.SoftDelete.Repo.normalize_field(value)
  defp normalize(value), do: value

  # ── Removing ──────────────────────────────────────────────────────────────

  # Planned in the transaction that removes, once the rows it decides on are
  # locked: an edit or a new use committed before the locks is in the plan.
  # One after them waits for the removal to commit: a block written with one
  # of the modules, whose foreign key check takes a share of the module's
  # row, or an edit of a homepage's or footer's rows.
  defp remove_planned do
    result =
      Repo.transaction(fn ->
        lock_candidates()
        plan = plan()
        entries = Enum.map(plan.entries, &remove_entry/1)
        modules = Enum.map(plan.modules, &remove_module/1)
        %{plan | entries: entries, modules: modules}
      end)

    case result do
      {:ok, plan} ->
        evict()
        {:ok, plan}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  # The page tree first, as a page's delete or parent change takes it, then
  # the entry's row, its blocks', and the modules'. An editor's save in the
  # admin writes the entry's row first (it sets `edited_at`), then its blocks,
  # and a block written with a module takes a share of the module's row: the
  # same order. A write that locks blocks before their entry (resolving stale
  # blocks, a save that leaves the entry's row alone) can deadlock with it;
  # Postgres then aborts one of the two, and nothing is lost.
  defp lock_candidates do
    Pages.lock_page_tree()

    page_ids =
      Repo.all(from(p in Pages.Page, where: p.uri == "index" and is_nil(p.deleted_at), select: p.id, lock: "FOR UPDATE"))

    fragment_ids =
      Repo.all(
        from(f in Pages.Fragment,
          where: f.parent_key == "partials" and f.key == "footer" and is_nil(f.deleted_at),
          select: f.id,
          lock: "FOR UPDATE"
        )
      )

    lock_blocks(Pages.Page.Blocks, page_ids)
    lock_blocks(Pages.Fragment.Blocks, fragment_ids)

    module_ids = Enum.map(Map.values(Seeds.seeded_modules()), & &1.id)
    Repo.all(from(m in Content.Module, where: m.id in ^module_ids, select: m.id, lock: "FOR UPDATE"))
  end

  # The rows the fingerprint reads under each entry: an edit that updates a
  # block, ref or variable in place touches neither the entry's row nor a
  # module's, so those locks alone would not wait for it. A row added under
  # them takes a share of the row it belongs to, which these locks hold.
  defp lock_blocks(_join, []), do: :ok

  defp lock_blocks(join, entry_ids) do
    root_ids =
      Repo.all(from(j in join, where: j.entry_id in ^entry_ids, select: j.block_id, lock: "FOR UPDATE"))

    block_ids = lock_tree(root_ids, [])
    Repo.all(from(r in Content.Ref, where: r.block_id in ^block_ids, select: r.id, lock: "FOR UPDATE"))
    Repo.all(from(v in Content.Var, where: v.block_id in ^block_ids, select: v.id, lock: "FOR UPDATE"))
    :ok
  end

  defp lock_tree([], locked), do: locked

  defp lock_tree(ids, locked) do
    Repo.all(from(b in Content.Block, where: b.id in ^ids, select: b.id, lock: "FOR UPDATE"))
    children = Repo.all(from(b in Content.Block, where: b.parent_id in ^ids, select: b.id))
    lock_tree(children -- locked, ids ++ locked)
  end

  # Fragments before pages: a page's delete moves the fragments still on it
  defp remove_entry(%{status: :removable, schema: Pages.Fragment} = entry),
    do: removed(entry, Pages.delete_fragment(entry.id, :system))

  defp remove_entry(%{status: :removable, schema: Pages.Page} = entry),
    do: removed(entry, Pages.delete_page(entry.id, :system))

  defp remove_entry(entry), do: entry

  defp remove_module(%{status: :removable, module: module} = entry),
    do: removed(entry, Content.delete_module(module.id, :system))

  defp remove_module(entry), do: entry

  defp removed(entry, {:ok, _deleted}), do: %{entry | status: :removed}
  defp removed(_entry, {:error, reason}), do: Repo.rollback(reason)

  # The contexts' deletes evict what they remove; the lists that hold them
  # are emptied here too, as the admin's Empty all caches would
  defp evict do
    Enum.each([Content.Module, Pages.Page, Pages.Fragment], &Brando.Cache.Query.evict_all/1)
  end

  # ── The report ────────────────────────────────────────────────────────────

  # In the order they are removed: the homepage and footer, then the modules
  defp show(plan, info) do
    if plan.entries != [] do
      info.([:yellow, "\n==> The homepage and footer from the seeds\n"])

      for entry <- plan.entries do
        info.([colour(entry.status), "    * #{entry_line(entry)}: #{entry_status(entry)}#{link(entry)}"])
      end
    end

    if plan.modules != [] do
      info.([:yellow, "\n==> Modules from the seeds\n"])
      Enum.each(plan.modules, &show_module(&1, info))
    end

    plan
  end

  defp show_module(%{module: module, status: :in_use, users: users}, info) do
    info.([:red, "    #{module_name(module)} (#{module.uid}): still used, kept"])

    for user <- users do
      notes = [blocks(user.blocks)] ++ if(user.trashed, do: ["in the trash"], else: [])
      info.("        - #{entry_line(user)}, #{Enum.join(notes, ", ")}#{link(user)}")
    end

    info.("      Take its blocks out of these, or delete them, then run this again.")

    if Enum.any?(users, & &1.trashed) do
      info.("      An entry in the trash keeps its blocks until it is deleted from the trash.")
    end
  end

  defp show_module(%{module: module, status: status, seeded_users: seeded_users}, info) do
    used = if seeded_users > 0, do: "used only by the homepage and footer as seeded", else: "not used"
    info.([colour(status), "    #{module_name(module)} (#{module.uid}): #{used}, #{removal(status)}"])
  end

  # A module's name is per admin language
  defp module_name(%{name: %{} = names}),
    do: names[Gettext.get_locale(Brando.Gettext)] || names["en"] || names |> Map.values() |> List.first()

  defp module_name(%{name: name}), do: name

  defp entry_line(entry), do: "#{String.capitalize(entry.type)} #{inspect(entry.label)}#{language(entry.language)}"

  defp language(nil), do: ""
  defp language(language), do: " (#{language})"

  defp link(%{url: url}) when is_binary(url), do: " — #{url}"
  defp link(_entry), do: ""

  defp blocks(1), do: "1 block"
  defp blocks(count), do: "#{count} blocks"

  defp entry_status(%{status: :kept, reason: reason}), do: "#{reason}, kept"
  defp entry_status(%{status: status}), do: "as seeded, #{removal(status)}"

  defp removal(:removable), do: "would be moved to the trash"
  defp removal(:removed), do: "moved to the trash"

  defp colour(:in_use), do: :red
  defp colour(:kept), do: :red
  defp colour(_status), do: :green

  defp finish(reports, yes?, info) do
    modules = Enum.flat_map(reports, & &1.modules)
    entries = Enum.flat_map(reports, & &1.entries)

    cond do
      modules == [] and entries == [] ->
        :ok

      yes? ->
        info.([:green, summary(modules, entries)])

      true ->
        info.([
          :yellow,
          "\nDry run: nothing was changed. Run it again with --yes (yes: true) to move what " <>
            "\"would be moved to the trash\" there."
        ])
    end
  end

  defp summary(modules, entries) do
    removed =
      [
        count(Enum.filter(modules, &(&1.status == :removed)), "module", "modules"),
        count(Enum.filter(entries, &(&1.status == :removed and &1.type == "page")), "page", "pages"),
        count(Enum.filter(entries, &(&1.status == :removed and &1.type == "fragment")), "fragment", "fragments")
      ]
      |> Enum.reject(&is_nil/1)

    kept = Enum.count(modules, &(&1.status == :in_use)) + Enum.count(entries, &(&1.status == :kept))

    moved =
      case removed do
        [] -> "\n==> Nothing was moved to the trash."
        removed -> "\n==> Moved #{join(removed)} to the trash, where they can be restored from."
      end

    moved <> if(kept > 0, do: " #{kept} kept: see above.", else: "")
  end

  defp count([], _one, _many), do: nil
  defp count([_], one, _many), do: "1 #{one}"
  defp count(list, _one, many), do: "#{length(list)} #{many}"

  defp join([one]), do: one
  defp join([one, two]), do: "#{one} and #{two}"
  defp join([one | rest]), do: "#{one}, " <> join(rest)
end
