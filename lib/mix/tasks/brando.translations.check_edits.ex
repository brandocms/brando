defmodule Mix.Tasks.Brando.Translations.CheckEdits do
  use Mix.Task

  import Ecto.Query, only: [from: 2]

  alias Brando.Revisions
  alias Brando.Revisions.Revision
  alias Brando.Translations.EditCheck
  alias Brando.Translations.Sync
  alias NimbleCSV.RFC4180, as: CSV

  @shortdoc "Runs the translation edit check over past text edits, for review"

  @moduledoc """
  Collects past edits to translatable texts from revision history and runs
  `Brando.Translations.EditCheck` on each, so its verdicts can be compared
  with what an editor would decide before the check is used anywhere.

      mix brando.translations.check_edits --output edits.csv
      mix brando.translations.check_edits --limit 300 --language no --no-model

  Every pair of consecutive revisions of an entry whose blueprint has
  `trait :translatable` is compared text by text, as translation sync
  flattens them. The CSV has one row per changed text, with the verdict and
  the model's answers, and an empty `label` column to fill in (`minor` or
  `review`) by hand.

  Options:

    * `--output` — the CSV file (default `translation_edit_check.csv`)
    * `--limit` — the most edits to check (default 200)
    * `--language` — only entries in this language
    * `--no-model` — only collect the edits; the checks code decides still run
    * `--concurrency` — model calls at a time (default 8)

  Uses the `:evaluate` model in `config :brando, Brando.AI`. It reads the
  current environment only, and changes nothing.
  """

  @switches [output: :string, limit: :integer, language: :string, model: :boolean, concurrency: :integer]
  @headers ~w(schema entry_id language path from_revision to_revision before after verdict reason kind confidence retranslate model label)

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: @switches)
    Application.put_env(:logger, :level, :error)
    Mix.Tasks.Run.run([])

    output = Keyword.get(opts, :output, "translation_edit_check.csv")
    model? = Keyword.get(opts, :model, true)

    if model? and not Brando.AI.evaluation_configured?() do
      Mix.raise("No evaluation model is configured. Set `models: [evaluate: ...]` in Brando.AI, or pass --no-model.")
    end

    edits = opts |> edits() |> Enum.take(Keyword.get(opts, :limit, 200))
    Mix.shell().info("Checking #{length(edits)} edits…")

    rows =
      edits
      |> Task.async_stream(&check(&1, model?),
        max_concurrency: Keyword.get(opts, :concurrency, 8),
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.zip(edits)
      |> Enum.map(fn
        {{:ok, result}, edit} -> row(edit, result)
        {{:exit, reason}, edit} -> row(edit, {:error, reason})
      end)

    File.write!(output, CSV.dump_to_iodata([@headers | rows]))
    summarize(rows)
    Mix.shell().info("Wrote #{output}")
  end

  @doc false
  def edits(opts) do
    language = opts[:language]

    Brando.Blueprint.list_blueprints(:include_brando)
    |> Enum.uniq()
    |> Enum.filter(&function_exported?(&1, :__translatable_config__, 0))
    |> Stream.flat_map(fn schema ->
      schema
      |> revision_numbers()
      |> Stream.flat_map(fn {entry_id, numbers} -> entry_edits(schema, entry_id, numbers, language) end)
    end)
  end

  defp revision_numbers(schema) do
    entry_type = to_string(schema)

    from(r in Revision,
      where: r.entry_type == ^entry_type,
      order_by: [asc: r.entry_id, asc: r.revision],
      select: {r.entry_id, r.revision}
    )
    |> Brando.Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.filter(fn {_, numbers} -> length(numbers) > 1 end)
  end

  defp entry_edits(schema, entry_id, numbers, language) do
    numbers
    |> Stream.map(&{&1, decode(schema, entry_id, &1)})
    |> Stream.reject(fn {_, entry} -> is_nil(entry) end)
    |> Stream.filter(fn {_, entry} -> is_nil(language) or to_string(Map.get(entry, :language)) == language end)
    |> Stream.chunk_every(2, 1, :discard)
    |> Stream.flat_map(fn [{from, before}, {to, after_entry}] ->
      before_texts = texts(before, schema)

      for {path, value} <- texts(after_entry, schema),
          previous <- [Map.get(before_texts, path)],
          present?(previous) and present?(value) and previous != value do
        %{
          schema: inspect(schema),
          entry_id: entry_id,
          language: to_string(Map.get(after_entry, :language)),
          path: path,
          from: from,
          to: to,
          before: previous,
          after: value
        }
      end
    end)
  end

  defp decode(schema, entry_id, number) do
    case Revisions.get_revision(schema, entry_id, number) do
      {:ok, {_revision, {_number, entry}}} -> entry
      _ -> nil
    end
  end

  defp texts(entry, schema) do
    for {path, :text, value} <- Sync.flatten_entry(entry, schema), is_binary(value), into: %{}, do: {path, value}
  rescue
    _ -> %{}
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp check(edit, true), do: EditCheck.check(edit.before, edit.after, language: edit.language)

  defp check(edit, false) do
    case EditCheck.precheck(edit.before, edit.after) do
      :ask -> {:ok, :not_asked}
      decided -> decided
    end
  end

  defp row(edit, result) do
    base = [edit.schema, edit.entry_id, edit.language, edit.path, edit.from, edit.to, edit.before, edit.after]

    answers =
      case result do
        {:ok, :not_asked} ->
          ["", "not_asked", "", "", "", ""]

        {:ok, r} ->
          [r.verdict, r.reason, r.kind, r.confidence, r.retranslate, r.model]

        {:error, reason} ->
          ["", "error: #{inspect(reason)}", "", "", "", ""]
      end

    Enum.map(base ++ answers ++ [""], &to_string(&1 || ""))
  end

  defp summarize(rows) do
    rows
    |> Enum.frequencies_by(fn row -> {Enum.at(row, 8), Enum.at(row, 9)} end)
    |> Enum.sort()
    |> Enum.each(fn {{verdict, reason}, count} ->
      Mix.shell().info("  #{String.pad_trailing(verdict, 7)} #{String.pad_trailing(reason, 10)} #{count}")
    end)
  end
end
