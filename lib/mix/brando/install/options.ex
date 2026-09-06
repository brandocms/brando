defmodule Mix.Brando.Install.Options do
  @moduledoc false

  @doc "Resolves installer tenancy without prompting or changing project configuration."
  def tenancy(options, existing \\ %{mode: :none, site_key: nil}) do
    case {Keyword.fetch(options, :tenancy_mode), Keyword.fetch(options, :site_key)} do
      {:error, :error} -> validate(existing.mode, existing.site_key)
      {:error, {:ok, _}} -> {:error, "--site-key can only be used with --tenancy-mode single"}
      {{:ok, mode}, site_key} -> explicit_tenancy(mode, site_key)
    end
  end

  defp explicit_tenancy(mode, site_key) do
    key =
      case site_key do
        {:ok, key} -> key
        :error -> nil
      end

    case mode do
      "none" -> validate(:none, key)
      "single" -> validate(:single, key)
      "multi" -> validate(:multi, key)
      _ -> {:error, "Invalid --tenancy-mode #{inspect(mode)}; expected none, single, or multi"}
    end
  end

  defp validate(:single, nil), do: {:error, "--site-key is required with --tenancy-mode single"}

  defp validate(:single, key) do
    if Brando.Tenant.valid_key?(key) do
      {:ok, %{mode: :single, site_key: key}}
    else
      {:error, "--site-key must be a lowercase, URL-safe key such as my-site"}
    end
  end

  defp validate(mode, nil) when mode in [:none, :multi], do: {:ok, %{mode: mode, site_key: nil}}

  defp validate(mode, _key) when mode in [:none, :multi] do
    {:error, "--site-key can only be used with --tenancy-mode single"}
  end

  defp validate(mode, _key) do
    {:error, "Invalid existing tenancy mode #{inspect(mode)}; expected none, single, or multi"}
  end
end
