defmodule Brando.Progress do
  @moduledoc """
  Progress sent through user channel
  """

  @doc """
  Send progress through channel
  """
  def update_progress(:system, _), do: :ignore
  def update_progress(user, status, opts \\ [])
  def update_progress(:system, _, _), do: :ignore

  def update_progress(%Brando.User{id: id}, status, opts), do: update_progress(id, status, opts)

  def update_progress(id, status, opts) do
    Brando.endpoint().broadcast!("user:#{id}", "progress:update", %{
      status: status,
      percent: Keyword.get(opts, :percent, nil),
      key: Keyword.get(opts, :key, nil)
    })
  end

  @doc """
  Shows the progress window on user's client
  """
  def show_progress(:system), do: :ignore

  def show_progress(%Brando.User{id: id}),
    do: show_progress(id)

  def show_progress(id), do: Brando.endpoint().broadcast!("user:#{id}", "progress:show", %{})

  @doc """
  Hides the progress window on user's client
  """
  def hide_progress(:system), do: :ignore

  def hide_progress(%Brando.User{id: id}),
    do: hide_progress(id)

  def hide_progress(id),
    do: Brando.endpoint().broadcast!("user:#{id}", "progress:hide", %{})
end
