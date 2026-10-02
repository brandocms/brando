defmodule BrandoAdmin.FormSubmissionsExportController do
  @moduledoc false
  use BrandoAdmin, :controller

  alias Brando.Forms
  alias Brando.Forms.Display

  @doc "The form's submissions as CSV: one column per field, labelled as in the form."
  def export(conn, %{"key" => key} = params) do
    with :ok <- Brando.Authorization.Boundary.authorize(conn.assigns.current_user, :read, Brando.Forms.Form),
         [_ | _] = forms <- Forms.list_forms_by_key(key) do
      language = if params["language"] in Enum.map(forms, &to_string(&1.language)), do: params["language"]
      forms_by_language = Map.new(forms, &{to_string(&1.language), &1})
      submissions = Forms.stream_submissions(key, language)
      columns = columns(forms, submissions)

      header = [gettext_header("Received"), gettext_header("Language")] ++ Enum.map(columns, &elem(&1, 1)) ++ ["URL"]

      rows = Enum.map(submissions, &row(&1, columns, forms_by_language))

      conn
      |> put_resp_header("cache-control", "no-store")
      |> send_download({:binary, csv([header | rows])},
        filename: "#{key}-submissions.csv",
        content_type: "text/csv"
      )
    else
      _ -> conn |> put_resp_content_type("text/plain") |> send_resp(404, "Not found")
    end
  end

  defp row(submission, columns, forms) do
    values = Enum.map(columns, fn {key, _} -> Display.value(forms, submission, key) end)
    [DateTime.to_iso8601(submission.inserted_at), submission.language] ++ values ++ [submission.url]
  end

  # The source form's fields first, then any key only older submissions have.
  defp columns([first | _], submissions) do
    from_form = for field <- first.fields, field.type != :section, do: {field.key, field.label || field.key}
    known = MapSet.new(from_form, &elem(&1, 0))

    extra =
      submissions
      |> Enum.flat_map(&Map.keys(&1.data))
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(known, &1))
      |> Enum.map(&{&1, &1})

    from_form ++ extra
  end

  defp gettext_header(text), do: Gettext.dgettext(Brando.Gettext, "default", text)

  defp csv(rows), do: Enum.map_join(rows, "", fn row -> Enum.map_join(row, ",", &cell/1) <> "\r\n" end)

  # Quoted, and a leading formula character neutralised so a spreadsheet does
  # not run what a visitor typed.
  defp cell(nil), do: ""

  defp cell(value) do
    value = to_string(value)
    value = if String.starts_with?(value, ["=", "+", "-", "@", "\t", "\r"]), do: "'" <> value, else: value
    ~s("#{String.replace(value, ~s("), ~s(""))}")
  end
end
