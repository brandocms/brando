defmodule Brando.Repo.Migrations.Brando222HashPreviewKeys do
  use Ecto.Migration

  @moduledoc """
  A shared preview's key is kept as its SHA-256 in hex
  (`Brando.Sites.Preview.hash_key/1`), so that someone who reads the
  database cannot open the links. Hashes the keys stored before, which
  keeps their links working. A key that already is a hash is left as it is.

  Down does nothing: a hash cannot be turned back into its key, and the
  links of the previews hashed here stop working on the version before.
  """

  def up do
    execute """
    UPDATE public.sites_previews
    SET preview_key = encode(sha256(convert_to(preview_key, 'UTF8')), 'hex')
    WHERE preview_key !~ '^[0-9a-f]{64}$'
    """
  end

  def down, do: :ok
end
