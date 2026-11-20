defmodule Brando.AI.WorkTranslationTest do
  # Translating a synchronized translation's open work units with the
  # configured model, for the form to fill in. The model is a stub.
  use ExUnit.Case, async: false

  alias Brando.AI.WorkTranslation

  setup do
    Brando.AIStub.configure()
    :ok
  end

  defp unit(key, kind, source, opts \\ []) do
    %{key: key, kind: kind, answerable: true, label: key, format: Keyword.get(opts, :format, "plain"), source: source}
    |> then(fn unit -> if opts[:current], do: Map.put(unit, :current, opts[:current]), else: unit end)
  end

  # The items the prompt sends, by id
  defp items(prompt) do
    [json] = Regex.run(~r/\{"items":.*\}/s, prompt)
    json |> Jason.decode!() |> Map.fetch!("items")
  end

  defp answer(fun) do
    Brando.AIStub.reply(fn prompt ->
      prompt |> items() |> Map.new(&{&1["n"], fun.(&1)}) |> Jason.encode!()
    end)
  end

  test "translates every unit and returns its text by key" do
    answer(fn item -> "EN " <> item["source"] end)

    units = [unit("title", "translate", "Tittel"), unit("subtitle", "translate", "Undertittel")]

    assert {:ok, %{texts: texts, problems: problems}} = WorkTranslation.translate(units, "no", "en")
    assert texts == %{"title" => "EN Tittel", "subtitle" => "EN Undertittel"}
    assert problems == %{}
  end

  test "a review unit sends the source and the translation, to be brought up to date" do
    test = self()

    Brando.AIStub.reply(fn prompt ->
      send(test, {:prompt, prompt})
      ~s({"1": "The new text"})
    end)

    units = [unit("title", "review", "Ny tekst", current: "The old text")]
    assert {:ok, %{texts: %{"title" => "The new text"}}} = WorkTranslation.translate(units, "no", "en")

    assert_received {:prompt, prompt}
    assert [%{"source" => "Ny tekst", "translation" => "The old text"}] = items(prompt)
    assert prompt =~ "up to date"
  end

  test "a unit whose reply lost the markup or a placeholder is not returned, with why" do
    answer(fn
      %{"source" => "<p>Hei</p>"} -> "Hello"
      %{"source" => "Hei {{ name }}"} -> "Hello name"
      item -> "EN " <> item["source"]
    end)

    units = [
      unit("body", "translate", "<p>Hei</p>", format: "html"),
      unit("greeting", "translate", "Hei {{ name }}"),
      unit("title", "translate", "Tittel")
    ]

    assert {:ok, %{texts: texts, problems: problems}} = WorkTranslation.translate(units, "no", "en")
    assert texts == %{"title" => "EN Tittel"}
    assert [%{code: "html_changed"}] = problems["body"]
    assert [%{code: "placeholders_changed"}] = problems["greeting"]
  end

  test "a unit the reply leaves out is a problem, not an empty text" do
    Brando.AIStub.reply(~s({"1": "Title"}))

    units = [unit("title", "translate", "Tittel"), unit("subtitle", "translate", "Undertittel")]

    assert {:ok, %{texts: %{"title" => "Title"}, problems: %{"subtitle" => [%{code: "missing"}]}}} =
             WorkTranslation.translate(units, "no", "en")
  end

  test "a reply in a code fence is read" do
    Brando.AIStub.reply(~s(```json\n{"1": "Title"}\n```))

    assert {:ok, %{texts: %{"title" => "Title"}}} =
             WorkTranslation.translate([unit("title", "translate", "Tittel")], "no", "en")
  end

  test "units without text, or not answerable, are not sent" do
    test = self()

    Brando.AIStub.reply(fn prompt ->
      send(test, {:prompt, prompt})
      ~s({"1": "Title"})
    end)

    units = [
      unit("title", "translate", "Tittel"),
      unit("empty", "translate", ""),
      %{key: "entry_blocks/x/identifiers", kind: "awaiting_translation", answerable: false, label: "x"}
    ]

    assert {:ok, %{texts: texts}} = WorkTranslation.translate(units, "no", "en")
    assert texts == %{"title" => "Title"}
    assert_received {:prompt, prompt}
    assert length(items(prompt)) == 1
  end

  test "long work goes in batches, and progress is reported per batch" do
    test = self()
    answer(fn item -> "EN " <> item["source"] end)

    units = for n <- 1..3, do: unit("t#{n}", "translate", String.duplicate("a", 5_000) <> "#{n}")

    progress = fn step -> send(test, {:progress, step}) end

    assert {:ok, %{texts: texts}} = WorkTranslation.translate(units, "no", "en", progress: progress, batch_chars: 6_000)
    assert map_size(texts) == 3
    assert_received {:progress, {0, 3}}
    assert_received {:progress, {1, 3}}
    assert_received {:progress, {3, 3}}
  end

  test "a failed call fails the whole run" do
    Brando.AIStub.reply(fn _prompt -> {:error, 500} end)
    assert {:error, _reason} = WorkTranslation.translate([unit("title", "translate", "Tittel")], "no", "en")
  end

  test "a reply that is not JSON fails the run" do
    Brando.AIStub.reply("Sorry, I can't")
    assert {:error, :invalid_response} = WorkTranslation.translate([unit("title", "translate", "Tittel")], "no", "en")
  end
end
