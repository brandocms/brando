defmodule BrandoAdmin.Components.Form.Input.Options do
  @moduledoc """
  Shared expansion of the symbolic `:options` tokens a form input can declare.

  `input :language, :select, options: :languages` is resolved at render time,
  because the language lists come from config and Brando supports changing them
  at runtime (`Brando.RuntimeConfig`) — so this deliberately does NOT memoize.

  Select and MultiSelect cache prepared options against the expanded specification.
  Callable providers are loaded on mount, opening the picker, and explicit refresh.
  Declare `options_depends_on: [:language, ...]` for providers that also need to
  reload when particular form fields change. Other keystrokes do not query them.
  """

  @tokens [:languages, :admin_languages]

  @doc "The `:options` tokens this module expands."
  def tokens, do: @tokens

  @doc """
  Expand `:languages` / `:admin_languages` into `%{label:, value:}` maps.

  Both config keys hold `[[value: "en", text: "English"], …]`.
  """
  def expand(token) when token in @tokens do
    token
    |> Brando.config()
    |> Enum.map(fn [{:value, value}, {:text, text}] -> %{label: text, value: value} end)
  end

  def expand(other), do: other

  @doc false
  def assign_options(socket, load, force? \\ false) do
    %{field: field, opts: opts} = socket.assigns
    expanded_opts = Keyword.update(opts, :options, nil, &expand/1)
    dependencies = Enum.map(Keyword.get(opts, :options_depends_on, []), &{&1, field.form[&1].value})
    key = {field.form.id, field.field, expanded_opts, dependencies}

    if !force? and socket.assigns[:input_options_key] == key do
      socket
    else
      socket
      |> Phoenix.Component.assign(:input_options, load.(field, expanded_opts))
      |> Phoenix.Component.assign(:input_options_key, key)
    end
  end
end
