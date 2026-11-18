defmodule Brando.Content.Definition.Error do
  @moduledoc """
  An invalid or incomplete portable definition, with its source location.

  A message is one line per problem, each naming where it is: the file
  relative to the application (or to the definition directory, or the ZIP),
  the definition when there is no file, the var or ref, the field, what the
  field takes and what it got:

      priv/modules/01-tekst/tekst.exs: var "label": placeholder must be a string (got a map)
  """
  defexception [:message, :file]

  alias Ecto.Changeset

  @max_value 40

  @doc "Raises `message`; within `in_file/2`, the file is put before it."
  @spec raise!(String.t()) :: no_return()
  def raise!(message), do: raise(__MODULE__, message: message)

  @doc "Raises `message` after `path`, what it is about: `path: message`."
  @spec raise!(term(), String.t()) :: no_return()
  def raise!(path, message), do: raise(__MODULE__, message: "#{path}: #{message}")

  @doc """
  Raises the errors of an invalid changeset, one line each
  (`changeset_lines/2`), after `subject`: `module "uid"`, or nil within a
  file.
  """
  @spec changeset!(Changeset.t(), String.t() | nil) :: no_return()
  def changeset!(changeset, subject) do
    raise(__MODULE__, message: Enum.join(changeset_lines(changeset, subject), "\n"))
  end

  @doc """
  Runs `fun`, putting `file` before each line of a definition error it
  raises, unless the error already names a file.
  """
  @spec in_file(String.t() | nil, (-> result)) :: result when result: term()
  def in_file(nil, fun), do: fun.()

  def in_file(file, fun) do
    fun.()
  rescue
    error in __MODULE__ ->
      if error.file,
        do: reraise(error, __STACKTRACE__),
        else: reraise(%{error | file: file, message: prefix(error.message, file)}, __STACKTRACE__)
  end

  defp prefix(message, file), do: message |> String.split("\n") |> Enum.map_join("\n", &"#{file}: #{&1}")

  @doc """
  How errors name a definition file: relative to the application (the
  working directory, or a release's application directory), else to the
  definition directory `root`.
  """
  @spec file_label(Path.t() | nil, Path.t()) :: String.t() | nil
  def file_label(nil, _root), do: nil

  def file_label(file, root) do
    file = Path.expand(file)

    Enum.find_value([File.cwd!(), app_dir()], Path.relative_to(file, Path.expand(root)), fn base ->
      if base && String.starts_with?(file, Path.expand(base) <> "/"), do: Path.relative_to(file, Path.expand(base))
    end)
  end

  defp app_dir do
    Application.app_dir(Brando.otp_app())
  rescue
    _ -> nil
  end

  @doc """
  A readable message for a definition error: a message as it is, and a
  definition whose save failed (`%{uid: uid, error: changeset}`) as one line
  per changeset error, naming the definition.
  """
  @spec describe(term()) :: String.t()
  def describe(message) when is_binary(message), do: message

  def describe(%{uid: uid, error: %Changeset{} = changeset}),
    do: changeset |> changeset_lines(definition_subject(changeset, uid)) |> Enum.join("\n")

  def describe(%{uid: uid, error: error}), do: "#{uid}: #{describe_term(error)}"
  def describe(other), do: describe_term(other)

  defp describe_term(%{__exception__: true} = error), do: Exception.message(error)
  defp describe_term(term), do: inspect(term)

  defp definition_subject(%Changeset{data: %Brando.Content.TableTemplate{}}, uid), do: ~s(table template "#{uid}")
  defp definition_subject(_changeset, uid), do: ~s(module "#{uid}")

  @doc """
  The errors of `changeset` and of every changeset nested in it (embeds,
  associations, polymorphic embeds), one line each: `subject`, the var or
  ref the error is in, the field's path and the problem.
  """
  @spec changeset_lines(Changeset.t(), String.t() | nil) :: [String.t()]
  def changeset_lines(%Changeset{} = changeset, subject \\ nil) do
    {subjects, fields} = descend(nil, nil, nil, changeset, Enum.reject([subject], &is_nil/1), [])

    changeset
    |> walk(subjects, fields)
    |> Enum.map(fn {subjects, fields, problem} ->
      field = fields |> Enum.reject(&(&1 == :ref_data)) |> Enum.join(".")
      Enum.join(subjects ++ [String.trim("#{field} #{problem}")], ": ")
    end)
    |> Enum.uniq()
  end

  defp walk(%Changeset{} = changeset, subjects, fields) do
    own =
      changeset.errors
      |> Enum.reverse()
      |> Enum.map(fn {field, error} ->
        {subjects, fields ++ [to_string(field)], problem(changeset, field, error)}
      end)

    nested =
      changeset.changes
      |> Enum.sort_by(fn {field, _} -> to_string(field) end)
      |> Enum.flat_map(fn {field, value} -> nested(changeset, field, value, subjects, fields) end)

    own ++ nested
  end

  defp nested(parent, field, %Changeset{} = changeset, subjects, fields) do
    {subjects, fields} = descend(parent, field, nil, changeset, subjects, fields)
    walk(changeset, subjects, fields)
  end

  defp nested(parent, field, [_ | _] = values, subjects, fields) do
    values
    |> Enum.reject(&(match?(%Changeset{action: action} when action in [:replace, :delete], &1) or not changeset?(&1)))
    |> Enum.with_index()
    |> Enum.flat_map(fn {changeset, index} ->
      {subjects, fields} = descend(parent, field, index, changeset, subjects, fields)
      walk(changeset, subjects, fields)
    end)
  end

  defp nested(_parent, _field, _value, _subjects, _fields), do: []

  defp changeset?(%Changeset{}), do: true
  defp changeset?(_), do: false

  # A var or ref is named by its key or name; inside a ref, the block's
  # `data.data` is what the definition calls `config` and `default`, so its
  # fields are named from there.
  defp descend(_parent, _field, _index, %Changeset{data: %Brando.Content.Var{}} = changeset, subjects, _fields),
    do: {subjects ++ [~s(var "#{Changeset.get_field(changeset, :key)}")], []}

  defp descend(_parent, _field, _index, %Changeset{data: %Brando.Content.Ref{}} = changeset, subjects, _fields),
    do: {subjects ++ [~s(ref "#{Changeset.get_field(changeset, :name)}")], []}

  defp descend(%Changeset{data: %Brando.Content.Ref{}}, :data, nil, _changeset, subjects, fields),
    do: {subjects, fields ++ [:ref_data]}

  defp descend(_parent, :data, nil, _changeset, subjects, [:ref_data]), do: {subjects, []}

  defp descend(nil, nil, nil, _changeset, subjects, fields), do: {subjects, fields}
  defp descend(_parent, field, nil, _changeset, subjects, fields), do: {subjects, fields ++ [to_string(field)]}

  defp descend(_parent, field, index, _changeset, subjects, fields),
    do: {subjects, fields ++ ["#{field}[#{index}]"]}

  defp problem(changeset, field, {message, opts}) do
    value = value(changeset, field)
    embedded? = embedded?(changeset, field)

    case Keyword.get(opts, :validation) do
      :cast -> "must be #{expected(opts[:type] || field_type(changeset, field))}#{got(value, :type)}"
      :required -> "is required"
      :inclusion -> "must be one of #{values(enum_values(opts))}#{got(value, :value)}"
      :exclusion -> "must not be one of #{values(opts[:enum])}#{got(value, :value)}"
      _ when embedded? -> interpolate(message, opts)
      _ -> interpolate(message, opts) <> got(value, :value)
    end
  end

  # Ecto.Enum's cast lists its values sorted; the schema declares their order
  defp enum_values(opts) do
    case opts[:type] do
      {:parameterized, {Ecto.Enum, %{mappings: mappings}}} -> Keyword.keys(mappings)
      _ -> opts[:enum]
    end
  end

  defp value(changeset, field) do
    params = changeset.params || %{}

    case Map.fetch(params, to_string(field)) do
      {:ok, value} -> value
      :error -> Changeset.get_field(changeset, field)
    end
  end

  defp embedded?(%Changeset{types: types}, field) do
    case Map.get(types || %{}, field) do
      {tag, _} when tag in [:embed, :assoc] -> true
      {:parameterized, {PolymorphicEmbed, _}} -> true
      _ -> false
    end
  end

  defp field_type(%Changeset{types: types}, field), do: Map.get(types || %{}, field)

  defp interpolate(message, opts) when is_binary(message),
    do: Regex.replace(~r/%{(\w+)}/, message, &option(opts, &1, &2))

  defp interpolate(message, _opts), do: inspect(message)

  defp option(opts, whole, key) do
    case Enum.find(opts, fn {name, _} -> to_string(name) == key end) do
      {_, value} when is_binary(value) -> value
      {_, value} -> inspect(value)
      nil -> whole
    end
  end

  defp got(nil, _), do: ""
  defp got(value, :type) when is_map(value) and not is_struct(value), do: " (got a map)"
  defp got(value, :type) when is_list(value), do: " (got a list)"
  defp got(value, _), do: " (got #{describe_value(value)})"

  defp describe_value(value) when is_binary(value) do
    if String.length(value) > @max_value,
      do: String.replace_suffix(inspect(String.slice(value, 0, @max_value)), "\"", "…\""),
      else: inspect(value)
  end

  defp describe_value(value) when is_integer(value), do: "the integer #{value}"
  defp describe_value(value) when is_float(value), do: "the number #{value}"
  defp describe_value(value) when is_boolean(value), do: to_string(value)
  defp describe_value(value) when is_map(value) and not is_struct(value), do: "a map: " <> short(value)
  defp describe_value(value) when is_list(value), do: "a list: " <> short(value)
  defp describe_value(value), do: short(value)

  defp short(value), do: value |> inspect(limit: 5, printable_limit: @max_value) |> truncate()

  defp truncate(text) do
    if String.length(text) > @max_value + 20, do: String.slice(text, 0, @max_value + 19) <> "…", else: text
  end

  defp values(nil), do: "the values allowed"
  defp values(enum), do: Enum.map_join(enum, ", ", &to_string/1)

  @doc "What a field of the Ecto `type` takes, in words: `\"a string\"`."
  @spec expected(term()) :: String.t()
  def expected(type) when type in [:string, :binary], do: "a string"
  def expected(type) when type in [:integer, :id], do: "an integer"
  def expected(type) when type in [:float, :decimal], do: "a number"
  def expected(:boolean), do: "true or false"
  def expected(:map), do: "a map"
  def expected({:map, _}), do: "a map"
  def expected(:date), do: "a date"
  def expected(type) when type in [:time, :time_usec], do: "a time"

  def expected(type) when type in [:naive_datetime, :naive_datetime_usec, :utc_datetime, :utc_datetime_usec],
    do: "a date and time"

  def expected({:array, type}), do: "a list (each #{expected(type)})"
  def expected({:parameterized, {Ecto.Enum, %{mappings: mappings}}}), do: "one of " <> values(Keyword.keys(mappings))
  def expected({:parameterized, {PolymorphicEmbed, _}}), do: "a map"
  def expected({:embed, %{cardinality: :many}}), do: "a list of maps"
  def expected({:embed, _}), do: "a map"
  def expected({:assoc, %{cardinality: :many}}), do: "a list of maps"
  def expected({:assoc, _}), do: "a map"
  def expected(Brando.Type.I18nString), do: "a string or a per-language map"

  def expected(type) when is_atom(type) and not is_nil(type) do
    if Code.ensure_loaded?(type) and function_exported?(type, :values, 0),
      do: "one of " <> values(type.values()),
      else: "a valid #{type |> Elixir.Module.split() |> List.last()}"
  rescue
    ArgumentError -> "a valid #{inspect(type)}"
  end

  def expected(type), do: "a valid #{inspect(type)}"
end
