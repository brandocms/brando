defmodule Brando.Forms.Recipient do
  @moduledoc """
  Someone a `Brando.Forms.Form`'s submissions are emailed to. With `bcc`, the
  address is a blind copy, hidden from the other recipients.

  Recipients belong to the source of a synchronized form: every language
  emails the same people. `uid` matches a row across languages.
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Forms",
    schema: "Recipient",
    singular: "recipient",
    plural: "recipients",
    gettext_module: Brando.Gettext

  data_layer :embedded

  trait :ensure_uid

  identifier false
  persist_identifier false

  attributes do
    attribute :uid, :string
    attribute :name, :string
    attribute :email, :string, required: true, constraints: [format: ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/]
    attribute :bcc, :boolean, default: false
  end
end
