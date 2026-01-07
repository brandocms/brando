export default class RevealObserver {
  constructor(el) {
    // eslint-disable-next-line compat/compat
    this.observer = new IntersectionObserver(
      (entries, self) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            this.reveal(entry.target)
            self.unobserve(entry.target)
          }
        })
      },
      {
        rootMargin: '10%',
        threshold: 0.0,
      }
    )

    this.observer.observe(el)
  }

  reveal(target) {
    target.setAttribute('data-revealed', '')
  }
}
