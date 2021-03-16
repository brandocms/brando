defmodule Brando.Plug.Fragment do
  @moduledoc """
  Add a fragment to conn assigns

  Plug this in your controller or pipeline

      plug Brando.Plug.Fragment, parent_key: "partials", as: :partials

  """

  alias Brando.Pages

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, opts) when is_list(opts) do
    locale = Gettext.get_locale(Brando.web_module(Gettext))
    parent_key = Keyword.fetch!(opts, :parent_key)
    name = Keyword.fetch!(opts, :as)

    fragment_opts = %{
      filter: %{parent_key: parent_key, language: locale},
      cache: {:ttl, :infinite}
    }

    {:ok, fragments} = Pages.get_fragments(fragment_opts)

    Plug.Conn.assign(conn, name, fragments)
  end

  def call(_, _) do
    raise """
    Brando.Plug.Fragment must be called with a keyword list as arg:

        plug Brando.Plug.Fragment, parent_key: "partials", as: :partials

    """
  end
end
