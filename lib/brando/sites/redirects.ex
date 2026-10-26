defmodule Brando.Sites.Redirects do
  @moduledoc false
  import Ecto.Query, only: [from: 2]

  alias Brando.Repo

  @doc """
  Removes an exact permalink redirect on a newly saved URL in its language.

  This runs before offering a redirect from the old URL, so declining that offer
  still leaves the new URL free of its previous exact rule. Pattern rules are
  preserved. Missing SEO settings are a no-op because there is no rule to remove.
  """
  def delete_permalink_redirect(url, language, user) do
    schema = Brando.Sites.SEO
    source = exact_source(URI.parse(url).path)

    result =
      Repo.transaction(fn ->
        case Repo.one(from s in schema, where: s.language == ^language, lock: "FOR UPDATE") do
          nil ->
            nil

          seo ->
            redirects = Enum.reject(seo.redirects || [], &(&1.from == source))
            store_redirects(seo, redirects, user)
        end
      end)

    Brando.Cache.SEO.update(result)
  end

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
      Repo.transaction(fn ->
        case Repo.one(from s in schema, where: s.language == ^language, lock: "FOR UPDATE") do
          nil ->
            Repo.repo().rollback(:seo_not_found)

          seo ->
            redirect = struct(Brando.Sites.Redirect, from: source, to: to, code: 301)

            redirects = retarget_redirects(seo.redirects || [], [source, destination_source], from_path, to)
            store_redirects(seo, [redirect | redirects], user)
        end
      end)

    Brando.Cache.SEO.update(result)
  end

  defp retarget_redirects(redirects, sources, from_path, to) do
    redirects
    |> Enum.reject(&(&1.from in sources))
    |> Enum.map(fn
      %{to: ^from_path} = existing -> %{existing | to: to}
      existing -> existing
    end)
  end

  defp store_redirects(%{redirects: redirects} = seo, redirects, _user), do: seo

  defp store_redirects(seo, redirects, user) do
    changeset =
      seo
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:redirects, redirects)

    case Brando.Sites.update_seo(changeset, user) do
      {:ok, updated_seo} -> updated_seo
      {:error, changeset} -> Repo.repo().rollback(changeset)
    end
  end

  @doc """
  The redirect source that matches `path` and nothing else: escaped, so a
  path can never become a pattern, and anchored at its end. A segment
  beginning with `:` is a placeholder in the matcher, so the colon is escaped
  too. For a source taken from a visitor's URL (a 404) as well as a
  permalink.
  """
  @spec exact_source(String.t()) :: String.t()
  def exact_source(path), do: path |> Regex.escape() |> String.replace(":", "\\x3A") |> Kernel.<>("$")

  @doc """
  The pattern a redirect's `from` matches with: anchored at the start, each
  `:name` segment a named capture. `{:ok, regex}`, or `:error` if it does not
  compile.
  """
  @spec compile(String.t()) :: {:ok, Regex.t()} | :error
  def compile(from) when is_binary(from) do
    "^#{from}"
    |> String.split("/")
    |> Enum.map_join("/", fn
      ":" <> segment -> "(?<#{segment}>[a-z0-9\-\_]+)"
      segment -> segment
    end)
    |> Regex.compile()
    |> case do
      {:ok, regex} -> {:ok, regex}
      {:error, _reason} -> :error
    end
  end

  def compile(_from), do: :error

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

  # A rule that does not compile (saved before `from` was checked) matches
  # nothing, rather than failing every 404 in its language
  defp match_redirect(test_url, from, to) do
    case cached_pattern(from) do
      {:ok, from_regex} -> match_redirect_pattern(test_url, from_regex, to)
      :error -> {:error, {:redirects, :no_match}}
    end
  end

  # Every 404 checks every rule, so a rule's pattern is compiled once
  defp cached_pattern(from) do
    key = {:redirect_pattern, from}

    case Brando.Cache.get(key) do
      nil ->
        compiled = compile(from)
        Brando.Cache.put(key, compiled, :timer.hours(24))
        compiled

      compiled ->
        compiled
    end
  end

  defp match_redirect_pattern(test_url, from_regex, to) do
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
