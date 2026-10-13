defmodule BrandoAdmin.Components.Form.I18nInputTest do
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
  import Ecto.Changeset, only: [cast: 3, change: 1, get_field: 2]
  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Content.Var
  alias Brando.Type.I18nString
  alias BrandoAdmin.Components.Form.Input

  setup do
    put_test_env(:admin_languages, [[value: "en", text: "English"], [value: "no", text: "Norsk"]])
    put_test_env(:languages, [[value: "en", text: "English"], [value: "fr", text: "Français"]])
    :ok
  end

  for kind <- [:i18n_text, :i18n_textarea], {source, other_language} <- [admin: "no", content: "fr"] do
    test "#{kind} with #{source} languages excludes LiveView metadata after validation" do
      stored = %{"en" => "English", unquote(other_language) => "Translated", "de" => "Deutsch"}
      var = %Var{label: stored}
      unused = Map.new(stored, fn {language, _} -> {"_unused_#{language}", ""} end)
      validated = cast(var, %{"label" => Map.merge(stored, unused)}, [:label])
      html = render_input(unquote(kind), validated, unquote(source))

      label = get_field(cast(var, submitted_params(html), [:label]), :label)
      assert {:ok, ^stored} = I18nString.dump(label)
    end

    test "#{kind} with #{source} languages preserves unlisted translations and allows clearing a tab" do
      stored = %{"en" => "English", "de" => "Größe & \"Maße\" <cm>", "ja" => "一行目\n二行目"}
      var = %Var{label: stored}
      html = render_input(unquote(kind), var, unquote(source))

      # Serialize the actual controls, as the browser does, rather than
      # handing cast/3 the map we expect the component to submit.
      submitted = submitted_params(html)
      expected = Map.put(stored, unquote(other_language), "")
      assert get_field(cast(var, submitted, [:label]), :label) == expected

      cleared = submitted_params(html, %{"var[label][en]" => ""})
      label = get_field(cast(var, cleared, [:label]), :label)
      assert label == Map.put(expected, "en", "")
      assert {:ok, dumped} = I18nString.dump(label)
      assert dumped["en"] == nil
      assert Map.take(dumped, ["de", "ja"]) == Map.take(stored, ["de", "ja"])
    end

    test "#{kind} with #{source} languages retains a legacy string whose language has no tab" do
      put_test_env(:default_language, "de")
      var = %Var{label: "Alte Beschriftung"}
      html = render_input(unquote(kind), var, unquote(source))

      assert get_field(cast(var, submitted_params(html), [:label]), :label) == %{
               "de" => "Alte Beschriftung",
               "en" => "",
               unquote(other_language) => ""
             }
    end
  end

  for kind <- [:i18n_text, :i18n_textarea] do
    test "disabled #{kind} does not submit a partial translation map" do
      var = %Var{label: %{"en" => "English", "de" => "Deutsch"}}
      html = render_input(unquote(kind), var, :admin, disabled: true)

      assert submitted_params(html) == %{}
      assert get_field(cast(var, submitted_params(html), [:label]), :label) == var.label
    end
  end

  defp render_input(kind, var, source, opts \\ []) do
    form = var |> change() |> to_form(as: :var)
    opts = if source == :admin, do: opts, else: Keyword.put(opts, :languages, :content)
    render_component(Function.capture(Input, kind, 1), field: form[:label], label: "Label", opts: opts)
  end

  defp submitted_params(html, edited \\ %{}) do
    html
    |> Floki.parse_document!()
    |> Floki.find("input[name]:not([disabled]), textarea[name]:not([disabled])")
    |> Enum.map(fn {tag, _, _} = node ->
      [name] = Floki.attribute(node, "name")
      value = if tag == "textarea", do: Floki.text(node), else: List.first(Floki.attribute(node, "value")) || ""
      {name, Map.get(edited, name, value)}
    end)
    |> URI.encode_query()
    |> Plug.Conn.Query.decode()
    |> Map.get("var", %{})
  end
end
