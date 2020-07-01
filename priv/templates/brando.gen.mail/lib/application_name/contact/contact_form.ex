defmodule <%= application_module %>.Contact.ContactForm do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :name
    field :email
    field :phone
    field :message
  end

  @attrs [
    :name,
    :email,
    :phone,
    :message
  ]

  def changeset(message, attrs) do
    message
    |> cast(attrs, @attrs)
    |> validate_required(@attrs)
  end
end
