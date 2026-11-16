defmodule BrandoIntegration.Repo.Migrations.AddRedirectHostsToEnvironments do
  use Ecto.Migration

  # Mirrors the brando_229 upgrade migration for the test schema.
  @moduledoc """
  An environment (`environments.redirect_hosts`) may have hosts that redirect
  permanently to its domain, such as `www.example.com` to `example.com`.
  Empty for every existing environment.

  A host is bound once in the whole installation: as one environment's
  domain or one redirect host. The unique index on `domain` already holds
  for domains; a trigger holds the rest, under a transaction-scoped advisory
  lock so two concurrent writes cannot both bind the same host. An
  environment with redirect hosts must keep a domain to redirect to.
  """

  def up do
    alter table(:environments, prefix: "public") do
      add :redirect_hosts, {:array, :string}, null: false, default: []
    end

    create constraint(:environments, :environments_redirect_hosts_need_domain,
             check: "domain IS NOT NULL OR cardinality(redirect_hosts) = 0",
             prefix: "public"
           )

    execute """
    CREATE OR REPLACE FUNCTION public.brando_environment_hosts_bound_once() RETURNS trigger
    LANGUAGE plpgsql AS $$
    DECLARE
      clash text;
    BEGIN
      IF TG_OP = 'UPDATE' AND NEW.domain IS NOT DISTINCT FROM OLD.domain
         AND NEW.redirect_hosts IS NOT DISTINCT FROM OLD.redirect_hosts THEN
        RETURN NEW;
      END IF;

      IF NEW.domain IS NULL AND cardinality(NEW.redirect_hosts) = 0 THEN
        RETURN NEW;
      END IF;

      -- One host write at a time in the installation: each check below then
      -- sees every host a write committed before it
      PERFORM pg_advisory_xact_lock(hashtextextended('brando.environments.hosts', 0));

      SELECT r.host INTO clash
      FROM unnest(NEW.redirect_hosts) WITH ORDINALITY AS r(host, position)
      WHERE r.host = NEW.domain
         OR EXISTS (
           SELECT 1 FROM unnest(NEW.redirect_hosts) WITH ORDINALITY AS o(host, position)
           WHERE o.host = r.host AND o.position < r.position
         )
         OR EXISTS (
           SELECT 1 FROM public.environments e
           WHERE e.id <> NEW.id AND (e.domain = r.host OR r.host = ANY(e.redirect_hosts))
         )
      LIMIT 1;

      IF clash IS NOT NULL THEN
        RAISE EXCEPTION 'the host % is already bound', clash
          USING ERRCODE = 'unique_violation', CONSTRAINT = 'environments_redirect_hosts_bound_once';
      END IF;

      IF NEW.domain IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.environments e WHERE e.id <> NEW.id AND NEW.domain = ANY(e.redirect_hosts)
      ) THEN
        RAISE EXCEPTION 'the host % is already bound', NEW.domain
          USING ERRCODE = 'unique_violation', CONSTRAINT = 'environments_domain_bound_once';
      END IF;

      RETURN NEW;
    END;
    $$
    """

    execute """
    CREATE TRIGGER environments_hosts_bound_once
    BEFORE INSERT OR UPDATE OF domain, redirect_hosts ON public.environments
    FOR EACH ROW EXECUTE FUNCTION public.brando_environment_hosts_bound_once()
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS environments_hosts_bound_once ON public.environments"
    execute "DROP FUNCTION IF EXISTS public.brando_environment_hosts_bound_once()"
    drop constraint(:environments, :environments_redirect_hosts_need_domain, prefix: "public")

    alter table(:environments, prefix: "public") do
      remove :redirect_hosts
    end
  end
end
