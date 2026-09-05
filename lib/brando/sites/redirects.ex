defmodule Brando.Sites.Redirects do
  @moduledoc false
  import Ecto.Query, only: [from: 2]

  @doc """
  Stores a confirmed permalink redirect in the previous language's SEO settings.

  The source is an escaped, exact path. Earlier redirects for that source are
  replaced, links to the previous path are updated, and an exact rule on the new
  path is removed to avoid loops when renaming back. Unrelated rules are kept.
  Locking the SEO row prevents concurrent confirmations from overwriting one another.
  """
  def create_permalink_redirect(%{from: from_path, to: to, language: language}, user) do
    schema = Brando.Sites.SEO
    source = exact_source(from_path)
    destination_source = exact_source(URI.parse(to).path)

    result =
      Brando.Repo.transaction(fn ->
        case Brando.Repo.one(from s in schema, where: s.language == ^language, lock: "FOR UPDATE") do
          nil ->
            Brando.Repo.repo().rollback(:seo_not_found)

          seo ->
            redirect = struct(Brando.Sites.Redirect, from: source, to: to, code: 301)

            redirects =
              (seo.redirects || [])
              |> Enum.reject(&(&1.from in [source, destination_source]))
              |> Enum.map(fn
                %{to: ^from_path} = existing -> %{existing | to: to}
                existing -> existing
              end)

            changeset =
              seo
              |> Ecto.Changeset.change()
              |> Ecto.Changeset.put_embed(:redirects, [redirect | redirects])

            case Brando.Sites.update_seo(changeset, user) do
              {:ok, updated_seo} -> updated_seo
              {:error, changeset} -> Brando.Repo.repo().rollback(changeset)
            end
        end
      end)

    Brando.Cache.SEO.update(result)
  end

  # A segment beginning with ':' is a placeholder in the redirect matcher.
  # Escape the colon as well so a literal path can never become a pattern.
  defp exact_source(path), do: path |> Regex.escape() |> String.replace(":", "\\x3A") |> Kernel.<>("$")

  @doc """
  Check `test_path` against registered redirects
  """
  @spec test_redirect(list, binary) ::
          {:ok, {:redirect, {binary, binary}}} | {:error, {:redirects, :no_match}}
  def test_redirect(test_path, language) do
    test_url = "/" <> Enum.join(test_path, "/")
    seo = Brando.Cache.SEO.get(language)
    redirects = seo.redirects || []

    Enum.reduce_while(redirects, {:error, {:redirects, :no_match}}, fn redirect, _acc ->
      case match_redirect(test_url, redirect.from, redirect.to) do
        {:error, _} ->
          {:cont, {:error, {:redirects, :no_match}}}

        url ->
          url = Brando.HTML.replace_timestamp(url)
          {:halt, {:ok, {:redirect, {url, redirect.code}}}}
      end
    end)
  end

  defp match_redirect(test_url, from, to) do
    from_regex =
      "^#{from}"
      |> String.split("/")
      |> Enum.map_join("/", fn
        ":" <> segment -> "(?<#{segment}>[a-z0-9\-\_]+)"
        segment -> segment
      end)
      |> Regex.compile!()

    case Regex.named_captures(from_regex, test_url) do
      nil ->
        {:error, {:redirects, :no_match}}

      captured_segments ->
        to
        |> String.split("/")
        |> Enum.map_join("/", fn
          ":" <> segment -> Map.get(captured_segments, segment, ":#{segment}")
          segment -> segment
        end)
    end
  end
end
