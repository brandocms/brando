/**
 * Brando.WorkStatus — a background work's status on the screen that started
 * it (BrandoAdmin.Components.Work). While it is on the page the work has no
 * toast: the toast goes when the status arrives, which may be after the
 * work's first report, and comes back when the status leaves.
 */
export default (app) => ({
  mounted() {
    app.toast?.refreshWork()
  },

  destroyed() {
    // Once the element has left the page
    setTimeout(() => app.toast?.refreshWork(), 0)
  },
})
