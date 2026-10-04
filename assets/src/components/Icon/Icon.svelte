<script>
  // The client-side twin of `Brando.HTML.Icon.icon/1`: a span masked by the
  // Lucide stylesheet the admin layout links. `name` must be a current Lucide
  // name; the server resolves stored names.
  let { name, class: className = '' } = $props()
</script>

<span data-icon class="lucide-{name} {className}" aria-hidden="true"></span>
