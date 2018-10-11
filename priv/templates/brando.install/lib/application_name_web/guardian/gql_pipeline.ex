defmodule <%= application_module %>Web.Guardian.GQLPipeline do
  @moduledoc """
  Guardian pipeline
  """
  use Guardian.Plug.Pipeline,
    otp_app: :<%= application_name %>,
    module: <%= application_module %>Web.Guardian,
    error_handler: Brando.Guardian.GQLErrorHandler

  plug Guardian.Plug.VerifyHeader, realm: "Bearer"
  plug Guardian.Plug.EnsureAuthenticated
  plug Guardian.Plug.LoadResource, ensure: true
end
