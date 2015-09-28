defmodule Brando.PostForm do
  @moduledoc """
  A form for the Post model. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form
  alias Brando.Post

  @doc false
  def get_language_choices(_) do
    Brando.config(:languages)
  end

  @doc false
  def get_status_choices(language) do
    Keyword.get(Brando.config(:status_choices), String.to_atom(language))
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

  form "post", [model: Post, helper: :admin_post_path, class: "grid-form"] do
    fieldset do
      field :language, :select,
        [default: "no",
        choices: &__MODULE__.get_language_choices/1]
    end
    fieldset do
      field :status, :radio,
        [default: "2",
        choices: &__MODULE__.get_status_choices/1,
        is_selected: &__MODULE__.status_selected?/2]
    end
    fieldset do
      field :featured, :checkbox, [default: false]
    end
    fieldset do
      field :header, :text
      field :slug, :text, [slug_from: :header]
    end
    field :lead, :textarea, [required: false]
    field :data, :textarea, [required: false]
    field :publish_at, :text, [default: &Brando.Utils.get_now/0]
    field :tags, :text, [tags: true, required: false]
    submit :save, [class: "btn btn-success"]
  end
end
