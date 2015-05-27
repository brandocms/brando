defmodule Brando.PageFragmentForm do
  @moduledoc """
  A form for the PageFragment model. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form

  @doc false
  def get_language_choices do
    [[value: "no", text: "Norsk"],
     [value: "en", text: "English"]]
  end

  @doc false
  def get_status_choices do
    [[value: "0", text: "Kladd"],
     [value: "1", text: "Publisert"],
     [value: "2", text: "Venter"],
     [value: "3", text: "Slettet"]]
  end

  @doc false
  def get_now do
    Ecto.DateTime.to_string(Ecto.DateTime.local)
  end

  @doc """
  Check is status' choice is selected.
  Translates the `model_value` from an atom to an int as string
  through `Brando.Type.Status.dump/1`.
  Returns boolean.
  """
  @spec is_status_selected?(String.t, atom) :: boolean
  def is_status_selected?(form_value, model_value) do
    # translate value from atom to corresponding int as string
    {:ok, status_int} = Brando.Type.Status.dump(model_value)
    form_value == to_string(status_int)
  end

  form "page_fragment", [helper: :admin_page_fragment_path, class: "grid-form"] do
    field :key, :text,
        [required: true,
         label: "Identifikasjonsnøkkel",
         placeholder: "Identifikasjonsnøkkel"]
    fieldset do
      field :language, :select,
        [required: true,
        label: "Språk",
        default: "no",
        choices: &__MODULE__.get_language_choices/0]
    end
    field :data, :textarea,
      [label: "Innhold"]
    submit "Lagre",
      [class: "btn btn-success"]
  end
end