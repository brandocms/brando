defmodule Brando.PageFragmentForm do
  @moduledoc """
  A form for the PageFragment model. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form
  alias Brando.PageFragment

  @doc false
  def get_language_choices() do
    Brando.config(:languages)
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
  @spec status_selected?(String.t, atom) :: boolean
  def status_selected?(form_value, model_value) do
    # translate value from atom to corresponding int as string
    {:ok, status_int} = Brando.Type.Status.dump(model_value)
    form_value == to_string(status_int)
  end

  form "page_fragment", [model: PageFragment, helper: :admin_page_fragment_path,
                         class: "grid-form"] do
    field :key, :text
    fieldset do
      field :language, :select,
        [default: "nb",
        choices: &__MODULE__.get_language_choices/0]
    end
    field :data, :textarea, [required: false]
    submit :save, [class: "btn btn-success"]
  end
end
