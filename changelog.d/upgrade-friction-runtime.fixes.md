- **A Blueprint's own `srcset` replaces the default one**. An image or gallery
  config's `srcset` was merged into the site's `default_config.srcset`: a
  legacy flat srcset (`%{"crop_md" => "600w"}`) failed compilation as mixing
  keyed lists with size entries, and a keyed one declaring only `cropped:`
  inherited the default's `default:` list and failed on sizes it does not
  have. A declared `srcset` now replaces the default whole, as `sizes` does.

- **Search, the command palette, the dashboard and the schedule skip types
  with no admin editor**. They kept every Blueprint with persisted identifiers, since every
  Blueprint generates `__admin_route__/2`, so a match on one whose application
  has no form route (`admin_farm_form_path/3 is undefined`) crashed the Search
  LiveView, and the dashboard's recent and scheduled entries could do the same.
  `Brando.Blueprint.admin_editor?/1` now checks that the router defines the
  form route. `mix brando.migrate55` says such Blueprints should set
  `persist_identifier false`.
