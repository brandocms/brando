defmodule BrandoAdmin.Progress do
  @moduledoc """
  Progress sent through user channel
  """

  @spec show(atom | integer) :: :ok | {:error, any}
  def show(:system), do: nil

  def show(user_id) do
    Brando.endpoint().broadcast!("user:#{user_id}", "progress:show", %{})
  end

  def hide(:system), do: nil

  def hide(user_id) do
    Brando.endpoint().broadcast!("user:#{user_id}", "progress:hide", %{})
  end

  def update(:system, _, _), do: nil

  def update(user_id, status, content) do
    Brando.endpoint().broadcast!("user:#{user_id}", "progress:update", %{
      status: status,
      content: content
    })
  end

  def update_delayed(:system, _, _), do: nil

  def update_delayed(user_id, status, content) do
    Task.start(fn ->
      :timer.sleep(500)

      Brando.endpoint().broadcast!("user:#{user_id}", "progress:update", %{
        status: status,
        content: content
      })
    end)
  end
end
