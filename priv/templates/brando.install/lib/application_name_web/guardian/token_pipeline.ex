defmodule <%= application_module %>Web.Guardian.TokenPipeline do
  @moduledoc """
  Guardian token pipeline
  """
  use Guardian.Plug.Pipeline,
    otp_app: :<%= application_name %>,
    module: <%= application_module %>Web.Guardian,
    error_handler: Brando.Guardian.GQLErrorHandler

  plug Guardian.Plug.VerifyHeader, realm: "Bearer"
  plug Guardian.Plug.LoadResource, allow_blank: true
end
