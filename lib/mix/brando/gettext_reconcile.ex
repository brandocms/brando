defmodule Mix.Brando.GettextReconcile do
  @moduledoc false
  # The catalog work behind `mix brando.gettext.reconcile`, given the POT
  # files Gettext's extractor produced: merge each backend's existing locales,
  # fill empty translations from sibling catalogs, delete the 0.53 Blueprint
  # domains (`<domain>_naming`, `_forms`, `_listings`) the merge leaves
  # without messages, and report what each Blueprint domain kept and lost.
  #
  # Everything is computed in memory first, so a dry run reads the same
  # result without writing.

  alias Expo.Message
  alias Expo.Messages
  alias Expo.PluralForms
  alias Expo.PO
  alias Gettext.Merger

  @legacy_domain ~r/\A(?<domain>.+)_(?:naming|forms|listings)\z/
  @two_forms "nplurals=2; plural=(n != 1);"
  @new_po_comment """
  # "msgid"s in this file come from POT (.pot) files.
  ##
  ## Do not add, change, or remove "msgid"s manually here as
  ## they're tied to the ones in the corresponding POT file
  ## (with the same domain).
  ##
  ## Use "mix gettext.extract --merge" or "mix gettext.merge"
  ## to merge POT files into PO files.
  """

  defmodule Domain do
    @moduledoc false
    # What one Blueprint domain kept in one locale. `carried` counts the
    # translations it had (in its own catalog or the 0.53 ones) that it still
    # has; `filled` and `dropped` list msgids; `untranslated` counts the
    # messages left without a translation.
    defstruct [:domain, :locale, carried: 0, filled: [], dropped: [], untranslated: 0]
  end

  @type report :: %{
          dir: String.t(),
          written: [String.t()],
          deleted: [String.t()],
          domains: [%Domain{}],
          warnings: [String.t()]
        }

  @doc """
  Reconciles the catalogs of the backend whose priv directory is `dir`.

  `pots` maps each extracted POT path (absolute, or relative to the current
  directory) to its contents. Options:

    * `:dry_run` - compute and report, write nothing.
    * `:blueprint_domains` - the Blueprint domains to report on, besides
      those that still have 0.53 catalogs.
    * `:gettext_config` - the project's `:gettext` configuration.
  """
  @spec reconcile(String.t(), %{String.t() => iodata()}, keyword()) :: report()
  def reconcile(dir, pots, opts \\ []) do
    config = Keyword.get(opts, :gettext_config, [])
    raw_pots = raw_pots(dir, pots)
    pots = Map.new(raw_pots, fn {path, contents} -> {Path.basename(path, ".pot"), PO.parse_string!(contents)} end)
    legacy = legacy_domains(dir, pots, Keyword.get(opts, :blueprint_domains, []))
    blueprint_domains = MapSet.new(Keyword.get(opts, :blueprint_domains, []) ++ Map.values(legacy))

    # A legacy domain nothing extracts to any more merges with an empty template.
    templates = Map.merge(Map.new(Map.keys(legacy), &{&1, %Messages{messages: []}}), pots)

    {catalogs, domains, warnings} =
      dir
      |> locales()
      |> Enum.reduce({%{}, [], []}, fn locale, {catalogs, domains, warnings} ->
        {merged, found, warned} = reconcile_locale(dir, locale, templates, legacy, blueprint_domains, config)
        {Map.merge(catalogs, merged), domains ++ found, warnings ++ warned}
      end)

    pot_files = Map.new(pots, fn {domain, messages} -> {Path.join(dir, domain <> ".pot"), messages} end)

    {deleted, written} =
      pot_files
      |> Map.merge(catalogs)
      |> Enum.sort()
      |> Enum.split_with(fn {path, messages} -> legacy_file?(path, legacy) and messages.messages == [] end)

    written =
      for {path, messages} <- written,
          contents = contents(path, messages, raw_pots),
          File.read(path) != {:ok, contents},
          do: {path, contents}

    deleted = for {path, _messages} <- deleted, File.exists?(path), do: path

    if !Keyword.get(opts, :dry_run, false) do
      Enum.each(written, fn {path, contents} -> write!(path, contents) end)
      Enum.each(deleted, &File.rm!/1)
    end

    %{dir: dir, written: Enum.map(written, &elem(&1, 0)), deleted: deleted, domains: domains, warnings: warnings}
  end

  # The extracted POT files directly under `dir`, by their path there.
  defp raw_pots(dir, pots) do
    expanded = Path.expand(dir)

    for {path, contents} <- pots, Path.dirname(Path.expand(path)) == expanded, into: %{} do
      {Path.join(dir, Path.basename(path)), IO.iodata_to_binary(contents)}
    end
  end

  # `%{legacy_domain => domain}` for the 0.53 catalogs of a domain 0.55
  # extracts to, or of a Blueprint domain, found as a .pot or in a locale.
  defp legacy_domains(dir, pots, blueprint_domains) do
    known = MapSet.new(Map.keys(pots) ++ blueprint_domains)

    [Path.join(dir, "*.pot"), Path.join(dir, "*/LC_MESSAGES/*.po")]
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.map(&Path.rootname(Path.basename(&1)))
    |> Kernel.++(Map.keys(pots))
    |> Enum.uniq()
    |> Enum.flat_map(fn name ->
      case Regex.named_captures(@legacy_domain, name) do
        %{"domain" => domain} -> if domain in known, do: [{name, domain}], else: []
        nil -> []
      end
    end)
    |> Map.new()
  end

  defp legacy_file?(path, legacy), do: Map.has_key?(legacy, Path.rootname(Path.basename(path)))

  defp locales(dir) do
    dir
    |> Path.join("*/LC_MESSAGES")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(&(&1 |> Path.dirname() |> Path.basename()))
    |> Enum.sort()
  end

  defp reconcile_locale(dir, locale, templates, legacy, blueprint_domains, config) do
    locale_dir = Path.join([dir, locale, "LC_MESSAGES"])

    existing =
      locale_dir
      |> Path.join("*.po")
      |> Path.wildcard()
      |> Enum.sort()
      |> Map.new(&{Path.basename(&1, ".po"), PO.parse_file!(&1)})

    header = plural_forms_header(locale, Map.values(existing))

    merged =
      Map.new(templates, fn {domain, pot} ->
        old = Map.get_lazy(existing, domain, fn -> new_catalog(locale, header) end)
        {domain, merge(old, pot, locale, header, config)}
      end)

    {merged, filled} = fill(merged, existing)

    domains =
      for {domain, catalog} <- Enum.sort(merged), domain in blueprint_domains do
        before =
          [domain | for({old, base} <- legacy, base == domain, do: old)]
          |> Enum.flat_map(&translated(existing[&1]))
          |> Map.new()

        report_domain(domain, locale, catalog, before, templates[domain], Map.get(filled, domain, []))
      end

    warnings =
      if header == @two_forms and not match?({:ok, _}, PluralForms.plural_form(locale)) and
           Enum.any?(Map.keys(merged), &(not Map.has_key?(existing, &1))),
         do: ["#{locale_dir}: #{locale} is not a locale Gettext knows; its new catalogs got `#{@two_forms}`."],
         else: []

    {Map.new(merged, fn {domain, catalog} -> {Path.join(locale_dir, domain <> ".po"), catalog} end), domains, warnings}
  end

  # The Plural-Forms header the locale's catalogs already declare, or the one
  # Gettext knows for the locale, or the two-form rule.
  defp plural_forms_header(locale, catalogs) do
    declared =
      Enum.find_value(catalogs, fn catalog ->
        header = catalog |> Messages.get_header("Plural-Forms") |> IO.iodata_to_binary() |> String.trim()
        if header != "" and match?({:ok, _}, PluralForms.parse(header)), do: header
      end)

    cond do
      declared ->
        declared

      match?({:ok, _}, PluralForms.plural_form(locale)) ->
        locale |> PluralForms.plural_form() |> elem(1) |> PluralForms.to_string()

      true ->
        @two_forms
    end
  end

  defp new_catalog(locale, header) do
    %Messages{
      top_comments: String.split(@new_po_comment, "\n", trim: true),
      headers: ["", "Language: #{locale}\n", "Plural-Forms: #{header}\n"],
      messages: []
    }
  end

  defp merge(old, pot, locale, header, config) do
    opts = [
      fuzzy: true,
      fuzzy_threshold: config[:fuzzy_threshold] || 0.8,
      on_obsolete: :delete,
      store_previous_message_on_fuzzy_match: false
    ]

    # A catalog's own Plural-Forms header decides its plural count, as in
    # `mix gettext.merge`; one without gets the locale's.
    opts =
      if IO.iodata_to_binary(Messages.get_header(old, "Plural-Forms")) == "",
        do: Keyword.put(opts, :plural_forms_header, header),
        else: opts

    {merged, _stats} = Merger.merge(old, pot, locale, opts, config)
    Merger.prune_references(merged, config)
  end

  # Fills an empty single-line translation of a singular message without
  # context from the first sibling catalog that translates the same msgid on
  # one line, as `scripts/sync_gettext.sh` does: the merged catalogs first,
  # then the catalogs as they were before the merge, which still hold what
  # the merge dropped from a sibling. Plural, contextual and multiline
  # messages are left alone.
  defp fill(merged, existing) do
    sources =
      (Enum.sort(merged) ++ Enum.sort(existing))
      |> Enum.flat_map(fn {_domain, catalog} -> catalog.messages end)
      |> Enum.reduce(%{}, fn message, acc ->
        case fillable(message) do
          {msgid, translation} when translation != "" -> Map.put_new(acc, msgid, translation)
          _other -> acc
        end
      end)

    Enum.reduce(merged, {merged, %{}}, fn {domain, catalog}, {merged, filled} ->
      {messages, found} =
        Enum.map_reduce(catalog.messages, [], fn message, found ->
          with {msgid, ""} <- fillable(message),
               {:ok, translation} <- Map.fetch(sources, msgid) do
            {%{message | msgstr: [translation]}, [msgid | found]}
          else
            _ -> {message, found}
          end
        end)

      {Map.put(merged, domain, %{catalog | messages: messages}), Map.put(filled, domain, Enum.reverse(found))}
    end)
  end

  defp fillable(%Message.Singular{msgctxt: nil, obsolete: false, msgid: msgid, msgstr: msgstr}) do
    with [_] <- Enum.reject(msgid, &(&1 == "")),
         segments when length(segments) <= 1 <- Enum.reject(msgstr, &(&1 == "")) do
      {IO.iodata_to_binary(msgid), IO.iodata_to_binary(segments)}
    else
      _ -> nil
    end
  end

  defp fillable(_message), do: nil

  # `[{key, msgid}]` for the translated messages of a catalog.
  defp translated(nil), do: []

  defp translated(catalog) do
    for message <- catalog.messages, not message.obsolete, translated?(message) do
      {Message.key(message), IO.iodata_to_binary(message.msgid)}
    end
  end

  defp translated?(%Message.Singular{msgstr: msgstr}), do: IO.iodata_to_binary(msgstr) != ""

  defp translated?(%Message.Plural{msgstr: msgstr}),
    do: Enum.any?(msgstr, fn {_, value} -> IO.iodata_to_binary(value) != "" end)

  defp report_domain(domain, locale, catalog, before, pot, filled) do
    after_keys = catalog |> translated() |> Map.new()
    in_source = MapSet.new(pot.messages, &Message.key/1)

    %Domain{
      domain: domain,
      locale: locale,
      carried: Enum.count(after_keys, fn {key, _msgid} -> Map.has_key?(before, key) end),
      filled: filled,
      dropped: for({key, msgid} <- Enum.sort_by(before, &elem(&1, 1)), key not in in_source, do: msgid),
      untranslated: length(catalog.messages) - map_size(after_keys)
    }
  end

  # A POT is written as the extractor composed it.
  defp contents(path, messages, raw_pots),
    do: Map.get_lazy(raw_pots, path, fn -> messages |> PO.compose() |> IO.iodata_to_binary() end)

  defp write!(path, contents) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end
end
