defmodule BrandoAdmin.Progress do
  @moduledoc """
  Progress sent through user channel
  """

  @spec show(atom | %{:id => any, optional(any) => any}) :: :ok | {:error, any}
  def show(:system), do: nil

  def show(%Brando.Users.User{id: id}) do
    Brando.endpoint().broadcast!("user:#{id}", "progress:show", %{})
  end

  def hide(:system), do: nil

  def hide(%Brando.Users.User{id: id}) do
    Brando.endpoint().broadcast!("user:#{id}", "progress:hide", %{})
  end

  def update(:system, _, _), do: nil

  def update(%Brando.Users.User{id: id}, status, content) do
    require Logger
    Logger.error(inspect(content, pretty: true))

    Brando.endpoint().broadcast!("user:#{id}", "progress:update", %{
      status: status,
      content: content
    })
  end

  def update_delayed(:system, _, _), do: nil

  def update_delayed(%Brando.Users.User{id: id}, status, content) do
    Task.start(fn ->
      :timer.sleep(500)

      Brando.endpoint().broadcast!("user:#{id}", "progress:update", %{
        status: status,
        content: content
      })
    end)
  end
end
