defmodule Brando.UserProfileForm do
  @moduledoc """
  A form for the current user's profile. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form

  form "user", [helper: :admin_user_path, class: "grid-form"] do
    fieldset "Brukerinfo" do
      field :full_name, :text,
        [required: true,
         label: "Fullt navn",
         placeholder: "Fullt navn"]
      field :username, :text,
        [required: true,
         label: "Brukernavn",
         placeholder: "Brukernavn"]
    end

    field :email, :email,
      [required: true,
       label: "E-post",
       placeholder: "E-post"]
    field :password, :password,
      [required: true,
       label: "Passord",
       placeholder: "Passord"]

    field :avatar, :file,
      [label: "Bilde"]
    submit "Lagre",
      [class: "btn btn-success"]
  end
end