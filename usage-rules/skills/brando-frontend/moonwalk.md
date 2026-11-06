# Moonwalk

Jupiter's Moonwalk reveals elements as they scroll into view. The site starts
it in `js/index.js` with the config in `js/config/MOONWALK.js`; it begins about
100 ms (`initialDelay`) after `APPLICATION:REVEALED`. `js/critical.js` puts
`moonwalk` on `<html>` before first paint, and `critical.css` and
`@europa base` hide every walk, section and run under `html.moonwalk` until
Moonwalk reveals them.

## The rule

**A `[data-moonwalk]` is revealed only inside a `[data-moonwalk-section]`.**
Moonwalk observes walks per section, so a walk outside any section is never
revealed and stays invisible.

- `@europa base` shows a section again once Moonwalk marks it ready:
  `[data-moonwalk-section][data-moonwalk-section-ready]`. Nothing shows a
  `[data-moonwalk-run]` again; its `callback` must.
- At init Moonwalk strips the attribute from a walk nested in a walk, and from
  a section nested in a section. Put sections side by side.
- A `data-moonwalk-run` and a `data-moonwalk-section` on the same element log
  a console warning. Use one per element.

## CSS walks

The template's walks are CSS-only: `walks.default` has `transition: null`.
Moonwalk then only marks each walk as it enters, staggered by `interval`, and
CSS in `app.css` does the motion:

- in an unnamed section, a walk gets the `moonwalked` class and the
  `data-moonwalked` attribute;
- in a named section (below), its children get only `data-moonwalked`, so
  style those with `[data-moonwalked]`.

The template styles only `[data-moonwalk=""]` and `[data-moonwalk="panner"]`.
A named walk such as `data-moonwalk="rise"` needs both:

1. a `walks.rise` entry in `MOONWALK.js` with its own `interval` and
   `duration`. Named walks inherit nothing from `default`, and an unknown name
   throws when the element scrolls in, which also skips the other walks
   entering with it;
2. CSS for its start and end states under `html.moonwalk`, as for
   `[data-moonwalk=""]` in `app.css`:

```css
html.moonwalk {
  [data-moonwalk="rise"] {
    opacity: 0;
    transform: translateY(24px);

    &.moonwalked {
      opacity: 1;
      transform: none;
      transition: opacity 0.6s ease-out, transform 0.6s ease-out;
    }
  }
}
```

A walk whose `transition` is `{ from, to }` is animated by JS instead and gets
`data-moonwalked` (no class) when it finishes. `critical.css` holds it at
opacity 0, so its `to` sets `opacity: 1` or the walk sets `alphaTween: true`.
Easing goes in `transition.to.ease`.

## Markup

- `data-moonwalk-children` (on an element inside a section): each direct
  child becomes a walk, `data-moonwalk="<value>"`; an empty value is the
  default walk. Use it on lists and grids.
- `data-moonwalk-section="name"`: a named section. All its targets reveal in
  one stagger when the section enters, using `walks.name`. Targets are its
  direct children, or the elements matching that walk's `sectionTargets`
  selector. `data-moonwalk-order="1"`, `"2"`… on targets sets their order;
  ordered targets go first, so start at 1. Walk names on elements inside a
  named section are ignored.
- `data-moonwalk-stage="name"` (on a section): the section itself animates
  from `walks.name.transition.from` to `.to` as it enters. That walk needs a
  real `transition`; `null` throws.
- `data-moonwalk-run="name"`: runs `runs.name` from `MOONWALK.js` when the
  element enters. A run needs no section, and an unknown name only warns.

```js
runs: {
  counter: {
    threshold: 0.5,              // the run's own; the global one is not used
    rootMargin: '0px',           // default: the global one; the last run on the page always gets '0px'
    repeated: false,             // true keeps observing after it has run
    initialize: el => {},        // when Moonwalk is created
    onReady: el => {},           // when Moonwalk starts, before observing
    callback: (el, repeated, { direction }) => { el.style.opacity = 1 },
    onExit: (el, exited, { direction }) => {},  // only after a callback ran
  },
},
```

`repeated` passed to `callback` is true from the second time the element
enters. Without `onExit` and `repeated`, the run fires once.

## Pictures

The `moonwalk` option of `<.picture>` (`Brando.HTML.Images`), which the
picture block's setting also sets, puts `data-moonwalk` on the `<figure>`, so the figure is the
walk and must sit inside a section. A walk containing images waits for them
to load before it reveals.

## Cases that reveal everything

- **Anchors**: loading a page with `#anchor` marks every walk before the
  target, the target and its ancestors as revealed at once, and the sections
  before it as ready. A hash that is not a valid CSS selector (`#1-intro`)
  throws; give anchors ids that start with a letter.
- **No JS**: without JS, `html` keeps `no-js` and never gets `moonwalk`, so
  Moonwalk hides nothing. Palette containers (`[b-section]`) are the
  exception: `critical.css` hides them until Jupiter runs.
- **Reduced motion**: only with `respectReducedMotion: true` on the
  `Application` (off in the template). Jupiter then removes the walk and
  section attributes and adds `prefers-reduced-motion` to `<html>`, which
  `@europa base` uses to show every walk.

## Content added after init

Moonwalk has no MutationObserver: markup inserted later needs its own
`new Moonwalk(app, config, container)` followed by `ready()`.
