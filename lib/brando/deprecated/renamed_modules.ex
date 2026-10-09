defmodule Brando.Deprecated.RenamedModules do
  @moduledoc false
  # Public modules renamed in 0.55 (#2833). Each old name is a deprecated
  # shim in `lib/brando/deprecated/` until it is removed in 0.57:
  # `mix brando.migrate55` rewrites references to the old names, and
  # `mix brando.doctor` lists the ones left in an application's `lib/`.
  #
  # Module atoms only, so nothing here depends on the modules at compile time.

  require Logger

  @removed_in "0.57"

  @renamed %{
    Brando.Config => Brando.Sites.Config,
    Brando.ErrorHTML => BrandoAdmin.ErrorHTML,
    Brando.Link => Brando.Sites.Link,
    Brando.LivePreviewChannel => BrandoAdmin.LivePreviewChannel,
    Brando.LobbyChannel => BrandoAdmin.LobbyChannel,
    Brando.Meta => Brando.Sites.Meta,
    Brando.PreviewController => BrandoWeb.PreviewController,
    Brando.SEOController => BrandoWeb.SEOController,
    Brando.SitemapController => BrandoWeb.SitemapController,
    Brando.UserChannel => BrandoAdmin.UserChannel
  }

  @doc "Old module => new module."
  def all, do: @renamed

  @doc "The module `old` was renamed to, or nil."
  def new_name(old), do: Map.get(@renamed, old)

  def removed_in, do: @removed_in

  @doc "Why `old` is deprecated, as the doctor and the shims' warnings say it."
  def reason(old) do
    "renamed to #{inspect(Map.fetch!(@renamed, old))}; the old name is removed in Brando #{@removed_in}. " <>
      "mix brando.migrate55 updates references"
  end

  @doc """
  Logs once per node that `old` was used. For the names a router, socket or
  endpoint config holds, which are looked up at runtime and so never see a
  compile-time `@deprecated` warning.
  """
  def warn(old) do
    key = {__MODULE__, old}

    unless :persistent_term.get(key, false) do
      :persistent_term.put(key, true)
      Logger.warning("#{inspect(old)} is deprecated: #{reason(old)}.")
    end

    :ok
  end
end
