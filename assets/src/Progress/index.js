import { gsap, Dom } from '@brandocms/jupiter'

export default class Progress {
  constructor (app) {
    this.app = app
    this.userId = Dom.find('meta[name="user_id"]').getAttribute('content')
    this.$progressWrapper = Dom.find('.progress-wrapper')
    this.$progress = Dom.find(this.$progressWrapper, '.progress')

    gsap.set(this.$progressWrapper, { yPercent: -100 })
    
    this.setupListener()
  }

  setupListener () {    
    window.addEventListener(`phx:hook:b:progress:${this.userId}`, ({ detail: { action, data }}) => {
      console.log('b:progress:${this.userId}', action, data)
      switch (action) {
        case 'show':
          console.log('show!')
          gsap.to(this.$progressWrapper, { yPercent: 0, ease: 'circ.out', duration: 0.35 })
          break
        case 'hide':
          gsap.to(this.$progressWrapper, { yPercent: -100, ease: 'circ.out', duration: 0.35 })
          break
        case 'update':
          console.log('update', data)
          const updateProgress = document.createRange().createContextualFragment(`
          <div class="progress-item" data-progress-key="${data.key}">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M18.364 5.636L16.95 7.05A7 7 0 1 0 19 12h2a9 9 0 1 1-2.636-6.364z"/></svg>
            <div class="filename">
              ${data.filename}
            </div>
            <div class="description">
              ${data.status}
            </div>
            <div class="percent">
              ${data.percent}%
            </div>
          </div>          
          `)
          this.$progress.append(updateProgress)
          break
      }
    })
  }
}