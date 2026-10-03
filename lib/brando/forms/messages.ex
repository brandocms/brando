defmodule Brando.Forms.Messages do
  @moduledoc """
  The wording visitors read around every form on the site — the submit
  button, what is said once a form is sent or could not be, and the errors
  next to a field — in each of the site's languages.

  There is one set per site, edited under Forms → Messages. A language left
  empty uses Brando's own wording, which is English where Brando has no
  translation. A form's own submit label and success message, when it has
  them, come before these.
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Forms",
    schema: "Messages",
    singular: "messages",
    plural: "messages",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext

  trait :timestamped

  identifier false
  persist_identifier false

  @keys ~w(submit_label success_message failure_message rate_limited spam_check required unticked none_chosen
           invalid_email invalid_number invalid_date invalid_choice too_long)a

  attributes do
    attribute :submit_label, :i18n_string
    attribute :success_message, :i18n_string
    attribute :failure_message, :i18n_string
    attribute :rate_limited, :i18n_string
    attribute :spam_check, :i18n_string
    attribute :required, :i18n_string
    attribute :unticked, :i18n_string
    attribute :none_chosen, :i18n_string
    attribute :invalid_email, :i18n_string
    attribute :invalid_number, :i18n_string
    attribute :invalid_date, :i18n_string
    attribute :invalid_choice, :i18n_string
    attribute :too_long, :i18n_string
  end

  translations do
    context :naming do
      translate :singular, t("form messages")
      translate :plural, t("form messages")
    end
  end

  forms do
    form do
      redirect_on_save &__MODULE__.redirect/3

      tab t("Messages") do
        fieldset do
          size :half
          label t("Sending")
          input :submit_label, :i18n_text, label: t("Submit button"), languages: :content

          input :success_message, :i18n_textarea,
            label: t("Sent"),
            instructions: t("Shown in place of a form once it has been sent."),
            languages: :content

          input :failure_message, :i18n_textarea,
            label: t("Not sent"),
            instructions: t("Shown when a form could not be sent, and no field says why."),
            languages: :content

          input :rate_limited, :i18n_text,
            label: t("Too many submissions"),
            instructions: t("Shown when a visitor sends too many forms in a short time."),
            languages: :content

          input :spam_check, :i18n_text,
            label: t("Spam check failed"),
            instructions: t("Shown when the Turnstile check does not let a submission through."),
            languages: :content
        end

        fieldset do
          size :half
          label t("Field errors")
          input :required, :i18n_text, label: t("A required field is empty"), languages: :content
          input :unticked, :i18n_text, label: t("A required box is not ticked"), languages: :content
          input :none_chosen, :i18n_text, label: t("No choice is ticked"), languages: :content
          input :invalid_email, :i18n_text, label: t("Not an email address"), languages: :content
          input :invalid_number, :i18n_text, label: t("Not a number"), languages: :content
          input :invalid_date, :i18n_text, label: t("Not a date"), languages: :content
          input :invalid_choice, :i18n_text, label: t("Not one of the choices"), languages: :content
          input :too_long, :i18n_text, label: t("Too long"), languages: :content
        end
      end
    end
  end

  @doc false
  def redirect(_socket, _entry, _mutation_type), do: "/admin/forms"

  @doc "The keys of the messages."
  def keys, do: @keys

  @doc """
  Brando's own wording of the message `key` in `language`: translated where
  Brando has a translation, English otherwise.
  """
  @spec built_in(atom(), String.t() | atom() | nil) :: String.t()
  def built_in(key, language) when key in @keys do
    Gettext.with_locale(Brando.Gettext, to_string(language || "en"), fn -> default(key) end)
  end

  @doc """
  A new set, worded in Brando's own translations for the `languages` it has
  them for. The other languages are left empty, so the editor can see they
  are still to be written.
  """
  def prefilled(languages) do
    translated = Enum.filter(languages, &(&1 in ["en" | Gettext.known_locales(Brando.Gettext)]))

    Map.new(@keys, fn key -> {key, Map.new(translated, &{&1, built_in(key, &1)})} end)
  end

  defp default(:submit_label), do: gettext("Send")
  defp default(:success_message), do: gettext("Thank you. Your message has been sent.")
  defp default(:failure_message), do: gettext("Your message could not be sent. Check the form and try again.")
  defp default(:rate_limited), do: gettext("Too many submissions. Wait a few minutes and try again.")
  defp default(:spam_check), do: gettext("The spam check failed. Reload the page and try again.")
  defp default(:required), do: gettext("Fill in this field.")
  defp default(:unticked), do: gettext("Tick this box to continue.")
  defp default(:none_chosen), do: gettext("Choose at least one.")
  defp default(:invalid_email), do: gettext("Enter a valid email address.")
  defp default(:invalid_number), do: gettext("Enter a number.")
  defp default(:invalid_date), do: gettext("Enter a date.")
  defp default(:invalid_choice), do: gettext("Choose one of the options.")
  defp default(:too_long), do: gettext("This is too long.")
end
