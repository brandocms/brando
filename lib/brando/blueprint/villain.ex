defmodule Brando.Blueprint.Villain do
  def maybe_add_villain_html_fields(attrs) do
    Enum.reduce(attrs, attrs, fn attr, updated_attrs ->
      if attr.type == :villain do
        html_attr =
          attr.name
          |> to_string
          |> String.replace("data", "html")
          |> String.to_atom()

        [%{name: html_attr, opts: [], type: :text} | updated_attrs]
      else
        updated_attrs
      end
    end)
  end
end
