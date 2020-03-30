See `UPGRADE.md` for instructions on upgrading between versions.

## 0.45.0

* Add `meta_image` field to `Brando.Page`
* Add `Brando.Datasource`
* Smarter Dockerfile layer caching
* Add globals to identity configuratin
* Add variables to Villain templates
* Improve default backend eslint configuration
* Add creator switch to generator
* Copy static files in development
* New JS backend — BrandoJS
* Add `Brando.Datasource`. Allows you to access preset backend queries from Villain.
* Simplify Villain default parser. Now you can `use Brando.Villain.Parser`
for sensible defaults, and override when neccessary.


## 0.44.0

* Drag and drop sequence pages.
* Ensure all jpg files are written as `.jpg`
* Move to local backend JS for tighter integration.
* Generator now generates a more complete `staging` config
* Generator separates out the form for backend schemas
* GraphQL rewrite to use Dataloader internally, also when using `brando.gen.html`
* Rename `Brando.Field.ImageField` -> `Brando.Field.Image.Schema`
* Rename `Brando.Field.FileField` -> `Brando.Field.File.Schema`


## 0.43.0

* Add `Brando.HTML.init_js()`
* Change potentially long identity fields to `:text`.
* Adds custom meta from `identity` setup to page


## 0.42.0

* Moved js deps to `@univers-agency` package scope.
* `Brando.User` is now `Brando.Users.User` for consistency.
* In `session_controller.ex`, ensure user has not been soft deleted in `create/3`
* Soft deletion fields have been added.
* Switch out the `:hmr` logic for `css` and `js`
* Run startup checks
* More advanced META and JSONLD handling.
* Added SHARP image processing. Choose this for the fastest/highest quality
* Removed all `import Brando.Images.Optimize` and `optimize/2` in changeset functions.


## 0.41.0

* Tables have been renamed.
* Fragments now belong to pages.


## 0.40.0

* Copy the brando.upgrade mix task from brando src.
* Switch all your image fields to `:jsonb` types in migrations from `:text`.


## 0.39.0

* Clean up time! Lots of deprecations and changes. See UPGRADE.md


## 0.38.0

* Update for Ecto 3, Phoenix 1.4
* More configuration choices in backend/config
* Add opts to body_tag
* Add config genserver
* More flexible cookie_law
* Add rerendering of page fragments
* Larger default image sizes
* Rewritten backend JS
* Rewritten generators
* Rewritten image handling


## 0.37.0

- Guardian was updated. Router changes. See UPGRADE.md
- `render_fragment` has been renamed to `fetch_fragment`.
- `brando_pages` has been incorporated into `brando` core.

## pre 0.37.0
