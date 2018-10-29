defmodule Brando.Plug.Uploads do
  @moduledoc """
  Plug that checks the conn struct for Plug.Uploads matching the `module`.

  ## Usage:

      import Brando.Plug.Uploads
      plug :check_for_uploads, {"user", Brando.User}
           when action in [:create, :profile_update, :update]
  """
  # DEPRECATED
  # TODO: REMOVE BEFORE 1.0
  @spec check_for_uploads(Plug.Conn.t(), {String.t(), module}) :: Plug.Conn.t()
  def check_for_uploads(_, {required_key, _}) when is_binary(required_key) do
    raise RuntimeError,
      message: """
      Brando.Plug.Uploads.check_for_uploads is deprecated.

      Add `validate_upload/2` to your changeset function instead.

          def changeset(schema, params) do
            schema
            |> cast(...)
            |> validate_upload({:image, :field_name}, user) # or {:file, :field_name}
          end
      """
  end
end
