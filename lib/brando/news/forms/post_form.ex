defmodule Brando.News.PostForm do
  @moduledoc """
  A form for the Post model. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form

  def get_language_choices do
    [[value: "no", text: "Norsk"],
     [value: "en", text: "English"]]
  end

  def get_status_choices do
    [[value: "0", text: "Kladd"],
     [value: "1", text: "Publisert"],
     [value: "2", text: "Venter"],
     [value: "3", text: "Slettet"]]
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

  form "post", [helper: :admin_post_path, class: "grid-form"] do
    fieldset [row_span: 4] do
      field :language, :select,
        [required: true,
        label: "Språk",
        default: "no",
        choices: &__MODULE__.get_language_choices/0]
    end
    fieldset [row_span: 1] do
      field :status, :radio,
        [required: true,
        label: "Status",
        default: "2",
        choices: &__MODULE__.get_status_choices/0,
        is_selected: &__MODULE__.is_status_selected?/2]
    end
    fieldset [row_span: 1] do
      field :featured, :checkbox,
        [label: "Vektet post",
        default: false,
        help_text: "Posten vektes uavhengig av opprettelses- og publiseringsdato"]
    end
    field :header, :text,
      [required: true,
       label: "Overskrift",
       placeholder: "Overskrift"]
    field :lead, :textarea,
      [label: "Ingress"]
    field :data, :textarea,
      [label: "Innhold"]
    submit "Lagre",
      [class: "btn btn-success"]

  end
end