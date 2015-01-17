defmodule Brando.Users.Model.User do
  use Ecto.Model
  use Brando.Mugshots.Fields.ImageField
  import Ecto.Query, only: [from: 2]
  alias Brando.Util

  before_insert __MODULE__, :add_timestamps
  def add_timestamps(user) do
    now = Ecto.DateTime.utc
    user
    |> put_change(:inserted_at, now)
    |> put_change(:updated_at, now)
  end

  before_update __MODULE__, :bump_update
  def bump_update(user) do
    now = Ecto.DateTime.utc
    put_change(user, :updated_at, now)
  end

  schema "users" do
    field :username, :string
    field :email, :string
    field :full_name, :string
    field :password, :string
    field :avatar, :string
    field :editor, :boolean
    field :administrator, :boolean
    field :last_login, :datetime
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  has_image_field :avatar,
    [allowed_mimetypes: ["image/jpeg", "image/png"],
     default_size: :medium,
     upload_path: Path.join("images", "default"),
     random_filename: true,
     size_limit: 10240000,
     sizes: [
       small:  [size: "300", quality: 100],
       medium: [size: "500", quality: 100],
       large:  [size: "700", quality: 100],
       xlarge: [size: "900", quality: 100],
       thumb:  [size: "150x150^ -gravity center -extent 150x150", quality: 100, crop: true]
    ]
  ]

  @doc """
  Casts and validates `params` against `user` to create a valid
  changeset when action is :create.
  """
  def changeset(user, :create, params) do
    params
    |> transform_checkbox_vals(~w(editor administrator))
    |> cast(user, ~w(username full_name email password), ~w(editor administrator))
    |> update_change(:email, &String.downcase/1)
    |> validate_format(:email, ~r/@/)
    |> validate_unique(:email, on: Brando.get_repo())
    |> validate_format(:username, ~r/^[a-z0-9_\-\.!~\*'\(\)]+$/)
    |> validate_length(:password, min: 6, too_short: "Passord må være > 6 tegn")
  end

  @doc """
  Casts and validates `params` against `user` to create a valid
  changeset when action is :update.
  """
  def changeset(user, :update, params) do
    params
    |> transform_checkbox_vals(~w(editor administrator))
    |> cast(user, [], ~w(username full_name email password editor administrator))
    |> update_change(:email, &String.downcase/1)
    |> validate_format(:email, ~r/@/)
    |> validate_unique(:email, on: Brando.get_repo())
    |> validate_format(:username, ~r/^[a-z0-9_\-\.!~\*'\(\)]+$/)
    |> validate_length(:password, min: 6, too_short: "Passord må være > 6 tegn")
  end

  def create(params) do
    user_changeset = changeset(%__MODULE__{}, :create, params)
    case user_changeset.valid? do
      true ->
        user_changeset = put_change(user_changeset, :password, gen_password(user_changeset.changes[:password]))
        {:ok, Brando.get_repo().insert(user_changeset)}
      false ->
        {:error, user_changeset.errors}
    end
  end

  def update(user, params) do
    user_changeset = changeset(user, :update, params)
    case user_changeset.valid? do
      true ->
        if Dict.has_key?(user_changeset.changes, :password) do
          user_changeset = put_change(user_changeset, :password, gen_password(user_changeset.changes[:password]))
        end
        {:ok, Brando.get_repo().update(user_changeset)}
      false ->
        {:error, user_changeset.errors}
    end
  end

  @doc """
  Checks `form_fields` for Plug.Upload fields and passes them on to
  `handle_upload` to check if we have a handler for the field.

  Also updates the affected fields in the database if `handle_upload`
  returns {:ok, file_url}
  """
  def check_for_uploads(user, form_fields) do
    form_fields = Enum.filter(form_fields, fn (form_field) ->
      case form_field do
        {_, %Plug.Upload{}} -> true
        {_, _} -> false
      end
    end)

    dict = Enum.reduce(form_fields, [], fn {field_name, plug}, dict ->
      cfg = get_image_cfg(String.to_atom(field_name))
      case handle_upload(plug, cfg) do
        {:ok, file_url} ->
          apply(__MODULE__, :update_field, [user, Keyword.new([{String.to_atom(field_name), file_url}])])
          [file: {String.to_atom(field_name), file_url}] ++ dict
        {:error, error} ->
          [error: {String.to_atom(field_name), error}] ++ dict
      end
    end)
    case dict do
      [] -> :nouploads
      dict -> {:ok, dict}
    end
  end

  @doc """
  Updates a field on `model`.
  `coll` should be [field_name: value]

  ## Example:

      {:ok, model} = update_field(model, [field_name: "value"])

  """
  def update_field(model, coll) do
    changeset = change(model, coll)
    {:ok, Brando.get_repo.update(changeset)}
  end

  @doc """
  Checkbox values from forms come with value => "on". This transforms
  them into bool values if params[key] is in keys.

  # Example:

      transform_checkbox_vals(params, ~w(administrator, editor))

  """
  def transform_checkbox_vals(params, keys) do
    Enum.into(Enum.map(params, fn({k, v}) ->
      case k in keys and v == "on" do
        true  -> {k, true}
        false -> {k, v}
      end
    end), %{})
  end

  @doc """
  Get user from DB by `username`
  """
  def get(username: username) do
    from(u in __MODULE__,
         where: fragment("lower(?) == lower(?)", u.username, ^username),
         limit: 1)
    |> Brando.get_repo.all
    |> List.first
  end

  @doc """
  Get user from DB by `email`
  """
  def get(email: email) do
    from(u in __MODULE__,
         where: fragment("? == lower(?)", u.email, ^email),
         limit: 1)
    |> Brando.get_repo.all
    |> List.first
  end

  @doc """
  Get user from DB by `id`
  """
  def get(id: id) do
    from(u in __MODULE__,
         where: u.id == ^id,
         limit: 1)
    |> Brando.get_repo.all
    |> List.first
  end

  @doc """
  Delete `user` from database. Also deletes any connected image fields,
  including all generated sizes.
  """
  def delete(user) do
    Brando.get_repo.delete(user)
    delete_connected_images(user, @imagefields)
  end

  @doc """
  Get all users. Ordered by `id`
  """
  def all do
    q = from u in __MODULE__,
        order_by: u.id
    Brando.get_repo.all(q)
  end

  def set_last_login(user) do
    user = %{user | last_login: Ecto.DateTime.local}
    |> Brando.get_repo.update
    user
  end

  def auth?(nil, _password), do: false

  def auth?(user, password) do
    stored_hash = user.password
    password    = String.to_char_list(password)
    {:ok, hash} = :bcrypt.hashpw(password, stored_hash)
    hash        = :erlang.list_to_binary(hash)

    Util.secure_compare(hash, stored_hash)
  end

  defp gen_password(password) do
    password    = String.to_char_list(password)
    work_factor = 12
    {:ok, salt} = :bcrypt.gen_salt(work_factor)
    {:ok, hash} = :bcrypt.hashpw(password, salt)
    :erlang.list_to_binary(hash)
  end

  def is_admin?(user) do
    user.administrator
  end

  def is_editor?(user) do
    user.editor
  end
end
