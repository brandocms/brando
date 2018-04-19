defmodule <%= application_module %>WebWeb.Guardian do
  @moduledoc """
  Interface for Guardian auth
  """

  use Guardian, otp_app: :<%= application_name %>
  alias Brando.User

  def subject_for_token(user = %User{}, _claims) do
    {:ok, "User:#{user.id}"}
  end

  def subject_for_token(_, _) do
    {:error, "Unknown resource type"}
  end

  def resource_from_claims(%{"sub" => "User:" <> id} = _claims), do: {:ok, Brando.repo.get(User, id)}

  def resource_from_claims(_claims) do
    {:error, "Unknown resource type"}
  end
end
