defmodule Mix.Tasks.Brando.Gen.Languages do
  use Mix.Task

  @shortdoc "Generate identities and seo tables for new languages"

  @moduledoc """
  Generate identites and seo tables for new languages
  """
  @spec run([]) :: no_return
  def run([]) do
    Application.put_env(:phoenix, :serve_endpoints, true)
    Application.put_env(:logger, :level, :error)

    Mix.Tasks.Run.run([])

    Mix.shell().info("""

    ---------------------------
    % Brando Generate Languages
    ---------------------------
    """)

    languages =
      []
      |> create_language()
      |> Enum.reverse()

    first_language_code = languages |> List.first() |> elem(0) |> to_string

    default_language =
      prompt_with_default("Enter default language", first_language_code)
      |> String.to_atom()

    Mix.shell().info([:blue, "\n==> Creating SEO and identity tables for languages.\n"])
    # create identities
    for {lang, _} <- languages do
      try do
        Brando.Sites.create_default_identity(lang)
      rescue
        Ecto.ConstraintError ->
          Mix.shell().info([:red, "(!) Error: identity table for [#{lang}] already exists!"])
      end

      try do
        Brando.Sites.create_default_seo(lang)
      rescue
        Ecto.ConstraintError ->
          Mix.shell().info([:red, "(!) Error: SEO table for [#{lang}] already exists!"])
      end
    end

    Mix.shell().info([:green, "\n==> Done.\n"])

    language_conf =
      Enum.map(languages, fn {key, label} -> [{:value, to_string(key)}, {:text, label}] end)

    instructions = """
    Add your languages to `config/brando.exs`:

        config :brando,
          default_language: #{inspect(to_string(default_language))},
          languages: #{inspect(language_conf, pretty: true)}

    Also remember to set `BRANDO_DEFAULT_LANGUAGE` in your .envrc files

        BRANDO_DEFAULT_LANGUAGE=#{inspect(to_string(default_language))}

    """

    Mix.shell().info(instructions)
  end

  defp create_language(acc) do
    label = prompt_with_default("Enter language label", "English")
    key = prompt_with_default("Enter language key", "en") |> String.to_atom()
    acc = [{key, label} | acc]

    if Mix.shell().yes?("Create another language?") do
      create_language(acc)
    else
      acc
    end
  end

  defp prompt_with_default(prompt, default) do
    case Mix.shell().prompt("+ #{prompt} [#{default}]") |> String.trim("\n") do
      "" -> default
      ret -> ret
    end
  end
end
