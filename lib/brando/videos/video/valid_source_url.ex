defmodule Brando.Videos.Video.ValidSourceURL do
  @moduledoc """
  Refuses a video address with a scheme other than http(s). An address without
  a scheme, as editors paste them (`vimeo.com/123456789`), is accepted.
  """
  use Brando.Trait
  use Gettext, backend: Brando.Gettext

  # What a browser strips from an address before it reads the scheme
  @stripped ~r/[\x00-\x20\x7F]/
  @scheme ~r/\A([A-Za-z][A-Za-z0-9+.-]*):/

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    Ecto.Changeset.validate_change(changeset, :source_url, fn :source_url, url ->
      if allowed?(url), do: [], else: [source_url: gettext("must be an http or https address")]
    end)
  end

  @doc "Whether `url` is safe to use as a link: http(s), or without a scheme."
  @spec allowed?(term()) :: boolean()
  def allowed?(url) when is_binary(url) do
    case Regex.run(@scheme, String.replace(url, @stripped, "")) do
      [_match, scheme] -> String.downcase(scheme) in ~w(http https)
      nil -> true
    end
  end

  def allowed?(_url), do: false
end
