describe('Pages', () => {
  beforeEach(() => {
    cy.loginUser()
  })

  it('can delete fragment', () => {
    cy.get('@currentUser').then(response => {
      cy.factorydb('page', { key: 'my-key', creator_id: response.body.id, creator: null }).then(resp => {
        cy.factorydb('page_fragment', { parent_key: 'my-key', page_id: resp.body.id, key: 'my-pf-key', creator_id: response.body.id, creator: null })
        cy.visit('/admin/sider')
        cy.contains('my-key')
        cy.get('tr > :nth-child(4) .badge').click()
        cy.contains('my-pf-key')
        cy.get('.page-subrow > :nth-child(7) > .dropdown').click()
        cy.contains('Slett fragment').click()
        cy.contains('Er du sikker på at du vil slette dette fragmentet?')
        cy.contains('OK').click()
        cy.contains('Fragmentet ble slettet')
      })
    })
  })

  it('can recreate fragment', () => {
    cy.get('@currentUser').then(response => {
      cy.factorydb('page', { key: 'my-key', creator_id: response.body.id, creator: null }).then(resp => {
        cy.factorydb('page_fragment', { parent_key: 'my-key', page_id: resp.body.id, key: 'my-pf-key', creator_id: response.body.id, creator: null })
        cy.visit('/admin/sider')
        cy.contains('my-key')
        cy.get('tr > :nth-child(4) .badge').click()
        cy.contains('my-pf-key')
        cy.get('.page-subrow > :nth-child(7) > .dropdown').click()
        cy.contains('Reprosessér fragment').click()
        cy.contains('Fragmentet ble gjengitt på nytt')
      })
    })
  })

  it('can duplicate fragment', () => {
    cy.get('@currentUser').then(response => {
      cy.factorydb('page', { key: 'my-key', creator_id: response.body.id, creator: null }).then(resp => {
        cy.factorydb('page_fragment', { parent_key: 'my-key', data: [], page_id: resp.body.id, key: 'my-pf-key', creator_id: response.body.id, creator: null })
        cy.visit('/admin/sider')
        cy.contains('my-key')
        cy.get('tr > :nth-child(4) .badge').click()
        cy.contains('my-pf-key')
        cy.get('.page-subrow > :nth-child(7) > .dropdown').click()
        cy.contains('Duplisér fragment').click()
        cy.contains('my-pf-key_kopi')
      })
    })
  })

  it('can create fragment', () => {
    cy.get('@currentUser').then(response => {
      cy.factorydb('page', { key: 'my-key', creator_id: response.body.id, creator: null }).then(resp => {
        cy.visit('/admin/sider')
        cy.contains('my-key')
        cy.get('tr > :nth-child(7) .dropdown').click()
        cy.contains('Opprett fragment').click()

        cy.location('pathname').should('match', /admin\/sidefragment\/ny\/(\d+)/)
        cy.contains('Opprett fragment')

        cy.get('#page_parent_key_').type('parent')
        cy.get('#page_key_').type('my-key')

        cy.get('.villain-editor-plus-inactive > a').click()
        cy.get('.villain-editor-plus-available-blocks > :nth-child(1)').click()
        cy.get('.ql-editor > p').click().type('This is a paragraph')
        cy.contains('Lagre fragment').click()

        cy.contains('Fragment opprettet')
        cy.location('pathname').should('eq', '/admin/sider')
        cy.get('tr > :nth-child(4) .badge').click()
        cy.contains('parent')
        cy.contains('my-key')
      })
    })
  })

  it('can edit fragment', () => {
    cy.get('@currentUser').then(response => {
      cy.factorydb('page', { key: 'my-key', creator_id: response.body.id, creator: null }).then(resp => {
        cy.factorydb('page_fragment', { parent_key: 'my-key', page_id: resp.body.id, key: 'my-pf-key', creator_id: response.body.id, creator: null })
        cy.visit('/admin/sider')
        cy.contains('my-key')
        cy.get('tr > :nth-child(4) .badge').click()
        cy.contains('my-pf-key')
        cy.get('.page-subrow > :nth-child(7) > .dropdown').click()
        cy.contains('Endre fragment').click()
        cy.location('pathname').should('match', /admin\/sidefragment\/endre\/(\d+)/)
        cy.contains('Oppdatér fragment')

        cy.get('#page_key_').type('-edit')

        cy.get('.villain-editor-plus-inactive > a').click()
        cy.get('.villain-editor-plus-available-blocks > :nth-child(1)').click()
        cy.get('.ql-editor > p').click().type('This is a paragraph')

        cy.contains('Lagre oppdatert fragment').click()

        cy.location('pathname').should('eq', '/admin/sider')
        cy.contains('Fragment oppdatert')
        cy.get('tr > :nth-child(4) .badge').click()
        cy.contains('my-pf-key-edit')
      })
    })
  })

  it('can list pages', () => {
    cy.factorydb('page', { title: 'Page title', slug: 'page-title' })
    cy.visit('/admin/sider')
    cy.contains('Administrér sideinnhold og fragmenter')

    cy.contains('Page title')
    cy.contains('a-key')
  })

  it('can edit page', () => {
    cy.factorydb('page', { title: 'Page title', slug: 'page-title' })
    cy.visit('/admin/sider')
    cy.contains('Administrér sideinnhold og fragmenter')

    cy.contains('Page title')
    cy.contains('a-key')

    cy.get('tr > :nth-child(7) .dropdown').click()
    cy.contains('Endre side').click()

    cy.location('pathname').should('match', /admin\/side\/endre\/(\d+)/)
    cy.contains('Endre side')

    cy.get('#page_key_').type('-edit')
    cy.get('#page_title_').type(' edit')

    cy.contains('Lagre oppdatert side').click()

    cy.contains('data -> can\'t be blank')

    cy.get('.vex-dialog-button-primary').click()

    cy.get('.villain-editor-plus-inactive > a').click()
    cy.get('.villain-editor-plus-available-blocks > :nth-child(1)').click()
    cy.get('p').click().type('This is a paragraph')

    cy.contains('Lagre oppdatert side').click()

    cy.location('pathname').should('eq', '/admin/sider')
    cy.contains('Side oppdatert')
    cy.contains('Page title edit')
    cy.contains('a-key-edit')
  })

  it('can delete page', () => {
    cy.factorydb('page', { title: 'Page title', slug: 'page-title' })
    cy.visit('/admin/sider')
    cy.contains('Administrér sideinnhold og fragmenter')

    cy.contains('Page title')
    cy.contains('a-key')

    cy.get('tr > :nth-child(7) .dropdown').click()
    cy.contains('Slett side').click()
    cy.contains('Er du sikker på at du vil slette denne siden?')

    cy.contains('OK').click()
  })

  it('can recreate page', () => {
    cy.factorydb('page', { title: 'Page title', slug: 'page-title' })
    cy.visit('/admin/sider')
    cy.contains('Administrér sideinnhold og fragmenter')

    cy.contains('Page title')
    cy.contains('a-key')

    cy.get('tr > :nth-child(7) .dropdown').click()
    cy.contains('Reprosessér side').click()
    cy.contains('Siden ble gjengitt på nytt')
  })

  it('can duplicate page', () => {
    cy.factorydb('page', { title: 'Page title', slug: 'page-title', data: [] })
    cy.visit('/admin/sider')
    cy.contains('Administrér sideinnhold og fragmenter')

    cy.contains('Page title')
    cy.contains('a-key')

    cy.get('tr > :nth-child(7) .dropdown').click()
    cy.contains('Duplisér side').click()
    cy.contains('Page title (kopi)')
    cy.contains('a-key_kopi')
  })

  it('can create page', () => {
    cy.visit('/admin/sider')

    cy.contains('Ny side').click()

    cy.get('#page_key_').type('my-key')
    cy.get('#page_title_').type('My title')
    cy.get('#page_meta_description_').type('Meta description')
    cy.get('#page_css_classes_').type('css class')

    cy.get('.villain-editor-plus-inactive > a').click()
    cy.get('.villain-editor-plus-available-blocks > :nth-child(1)').click()
    cy.get('p').click().type('This is a paragraph')

    cy.contains('Lagre side').click()

    cy.contains('Side opprettet')
    cy.location('pathname').should('eq', '/admin/sider')
    cy.contains('my-key')
    cy.contains('My title')
  })
})
