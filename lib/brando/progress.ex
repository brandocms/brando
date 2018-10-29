defmodule Brando.Progress do
  @moduledoc """
  Progress sent through user channel
  """

  @doc """
  Send progress through channel
  """
  def update_progress(:system, _) do
    :ignore
  end

  def update_progress(user, status) do
    Brando.endpoint().broadcast!("user:#{user.id}", "progress:update", %{status: status})
  end

  def update_progress(user, status, percent) do
    Brando.endpoint().broadcast!("user:#{user.id}", "progress:update", %{status: status, percent: percent})
  end

  def show_progress(:system), do: :ignore
  def show_progress(user) do
    Brando.endpoint().broadcast!("user:#{user.id}", "progress:show", %{})
  end

  def hide_progress(:system), do: :ignore
  def hide_progress(user) do
    Brando.endpoint().broadcast!("user:#{user.id}", "progress:hide", %{})
  end
end