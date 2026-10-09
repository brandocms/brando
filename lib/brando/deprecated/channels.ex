# Deprecated names for the admin channels, which moved to `BrandoAdmin` in
# 0.55 (#2833); removed in 0.57.
#
# Phoenix runs a channel's callbacks on the module the socket registered, so
# a socket that still registers an old name needs every callback here, not
# only `child_spec/1`. Each shim delegates the callbacks its channel defines
# and logs a warning on the first join.

defmodule Brando.UserChannel do
  @moduledoc false

  alias Brando.Deprecated.RenamedModules

  def child_spec(init_arg) do
    RenamedModules.warn(__MODULE__)
    BrandoAdmin.UserChannel.child_spec(init_arg)
  end

  defdelegate start_link(triplet), to: BrandoAdmin.UserChannel
  defdelegate __socket__(key), to: BrandoAdmin.UserChannel
  defdelegate __intercepts__(), to: BrandoAdmin.UserChannel
  defdelegate join(topic, params, socket), to: BrandoAdmin.UserChannel
  defdelegate handle_out(event, payload, socket), to: BrandoAdmin.UserChannel
  defdelegate handle_info(message, socket), to: BrandoAdmin.UserChannel

  @deprecated "Use BrandoAdmin.UserChannel.alert/2 instead"
  defdelegate alert(user, message), to: BrandoAdmin.UserChannel

  @deprecated "Use BrandoAdmin.UserChannel.set_progress/2 instead"
  defdelegate set_progress(user, value), to: BrandoAdmin.UserChannel

  @deprecated "Use BrandoAdmin.UserChannel.increase_progress/2 instead"
  defdelegate increase_progress(user, value), to: BrandoAdmin.UserChannel
end

defmodule Brando.LobbyChannel do
  @moduledoc false

  alias Brando.Deprecated.RenamedModules

  def child_spec(init_arg) do
    RenamedModules.warn(__MODULE__)
    BrandoAdmin.LobbyChannel.child_spec(init_arg)
  end

  defdelegate start_link(triplet), to: BrandoAdmin.LobbyChannel
  defdelegate __socket__(key), to: BrandoAdmin.LobbyChannel
  defdelegate __intercepts__(), to: BrandoAdmin.LobbyChannel
  defdelegate join(topic, params, socket), to: BrandoAdmin.LobbyChannel
  defdelegate handle_in(event, payload, socket), to: BrandoAdmin.LobbyChannel
  defdelegate handle_out(event, payload, socket), to: BrandoAdmin.LobbyChannel
  defdelegate handle_info(message, socket), to: BrandoAdmin.LobbyChannel
end

defmodule Brando.LivePreviewChannel do
  @moduledoc false

  alias Brando.Deprecated.RenamedModules

  def child_spec(init_arg) do
    RenamedModules.warn(__MODULE__)
    BrandoAdmin.LivePreviewChannel.child_spec(init_arg)
  end

  defdelegate start_link(triplet), to: BrandoAdmin.LivePreviewChannel
  defdelegate __socket__(key), to: BrandoAdmin.LivePreviewChannel
  defdelegate __intercepts__(), to: BrandoAdmin.LivePreviewChannel
  defdelegate join(topic, params, socket), to: BrandoAdmin.LivePreviewChannel
  defdelegate handle_out(event, payload, socket), to: BrandoAdmin.LivePreviewChannel
  defdelegate handle_info(message, socket), to: BrandoAdmin.LivePreviewChannel
end
