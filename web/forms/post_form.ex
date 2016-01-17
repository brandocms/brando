defmodule Brando.PostForm do
  @moduledoc """
  A form for the Post model. See the `Brando.Form` module for more
  documentation
  """

  use Brando.Form
  alias Brando.Post
  import Brando.Gettext

  @doc false
  def get_language_choices() do
    Brando.config(:languages)
  end

  @doc false
  def get_status_choices() do
   [[value: "0", text: gettext("Draft")],
    [value: "1", text: gettext("Published")],
    [value: "2", text: gettext("Pending")],
    [value: "3", text: gettext("Deleted")]]
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
        [default: "nb",
         choices: &__MODULE__.get_language_choices/0]
    end
    fieldset do
      field :status, :radio,
        [default: "2",
         choices: &__MODULE__.get_status_choices/0,
         is_selected: &__MODULE__.status_selected?/2]
    end
    fieldset do
      field :featured, :checkbox,
        [default: false,
         help_text: gettext("The post is prioritized, taking precedence over pub. date")]
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
