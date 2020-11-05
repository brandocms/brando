defmodule Brando.Plug.I18n do
  @moduledoc """
  A plug for checking i18n
  """
  import Brando.Utils, only: [current_user: 1]
  alias Brando.I18n

  @doc """
  Assign current locale.
  """
  @spec put_locale(Plug.Conn.t(), Keyword.t()) :: Plug.Conn.t()
  def put_locale(conn, opts) do
    opts = Enum.into(opts, %{})
    extracted_language = extract_language(conn, opts)
    Gettext.put_locale(Brando.web_module(Gettext), extracted_language)

    conn
    |> maybe_prefix_language_to_path(extracted_language, opts)
    |> put_and_assign_language(extracted_language, opts)
  end

  @doc """
  Set locale to current user's language

  This sets both Brando.Gettext (the default gettext we use in the backend),
  as well as delegating to the I18n module for setting proper locale for all
  registered gettext modules.
  """
  @spec put_admin_locale(Plug.Conn.t(), Keyword.t()) :: Plug.Conn.t()
  def put_admin_locale(conn, []) do
    language =
      case current_user(conn) do
        nil -> Brando.config(:default_admin_language)
        user -> Map.get(user, :language, Brando.config(:default_admin_language))
      end

    # set for default brando backend
    Gettext.put_locale(Brando.Gettext, language)
    conn
  end

  defp put_and_assign_language(conn, extracted_language, %{skip_session: _}) do
    I18n.assign_language(conn, extracted_language)
  end

  defp put_and_assign_language(conn, extracted_language, _) do
    conn
    |> I18n.put_language(extracted_language)
    |> I18n.assign_language(extracted_language)
  end

  defp extract_language(conn, %{by_host: host_map}) do
    case Map.get(host_map, conn.host) do
      nil -> extract_language(conn, %{})
      language -> language
    end
  end

  defp extract_language(conn, _) do
    {extracted_language, _} = I18n.parse_path(conn.path_info)
    extracted_language
  end

  defp maybe_prefix_language_to_path(%{path_info: ["admin" | _]} = conn, _, %{force_path: _}),
    do: conn

  defp maybe_prefix_language_to_path(conn, extracted_language, %{force_path: _}) do
    %{conn | path_info: [extracted_language | conn.path_info]}
  end

  defp maybe_prefix_language_to_path(conn, _, _), do: conn
end
