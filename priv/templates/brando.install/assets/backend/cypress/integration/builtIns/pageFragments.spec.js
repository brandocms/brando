describe('Page fragments', () => {
  beforeEach(() => {
    cy.factorydb('user', { email: 'lou@reed.com', role: 'superuser' })
    cy.login('lou@reed.com', 'admin')
  })

  it('can list page fragments', () => {
    cy.factorydb('page_fragment', { key: 'my-key' })
    cy.visit('/admin/sidefragmenter')
    cy.contains('Sidefragmenter')

    cy.contains('parent')
    cy.contains('my-key')
  })

  it('can edit fragment', () => {
    cy.factorydb('page_fragment', { key: 'my-key' })
    cy.visit('/admin/sidefragmenter')

    cy.contains('my-key')

    cy.get('tr > :nth-child(5) .dropdown').click()
    cy.contains('Endre fragment').click()

    cy.location('pathname').should('match', /admin\/sidefragment\/endre\/(\d+)/)
    cy.contains('Oppdatér fragment')

    cy.get('#page_key_').type('-edit')

    cy.contains('Lagre oppdatert fragment').click()

    cy.contains('data -> can\'t be blank')

    cy.get('.vex-dialog-button-primary').click()

    cy.get('.villain-editor-plus-inactive > a').click()
    cy.get('.villain-editor-plus-available-blocks > :nth-child(1)').click()
    cy.get('p').click().type('This is a paragraph')

    cy.contains('Lagre oppdatert fragment').click()

    cy.location('pathname').should('eq', '/admin/sidefragmenter')
    cy.contains('Fragment oppdatert')
    cy.contains('my-key-edit')
  })

  it('can delete fragment', () => {
    cy.factorydb('page_fragment', { key: 'my-key' })
    cy.visit('/admin/sidefragmenter')
    cy.contains('Sidefragmenter')

    cy.contains('my-key')

    cy.get('tr > :nth-child(5) .dropdown').click()
    cy.contains('Slett fragment').click()
    cy.contains('Er du sikker på at du vil slette dette fragmentet?')

    cy.contains('OK').click()
  })

  it('can recreate fragment', () => {
    cy.factorydb('page_fragment', { key: 'my-key' })
    cy.visit('/admin/sidefragmenter')
    cy.contains('Sidefragmenter')

    cy.contains('my-key')

    cy.get('tr > :nth-child(5) .dropdown').click()
    cy.contains('Reprosessér fragment').click()
    cy.contains('Fragmentet ble gjengitt på nytt')
  })

  it('can duplicate fragment', () => {
    cy.factorydb('page_fragment', { key: 'my-key', data: '[]' })
    cy.visit('/admin/sidefragmenter')
    cy.contains('Sidefragmenter')

    cy.contains('my-key')

    cy.get('tr > :nth-child(5) .dropdown').click()
    cy.contains('Duplisér fragment').click()
    cy.contains('my-key_kopi')
  })

  it('can create page', () => {
    cy.visit('/admin/sidefragmenter')

    cy.contains('Nytt sidefragment').click()

    cy.get('#page_parent_key_').type('parent')
    cy.get('#page_key_').type('my-key')

    cy.get('.villain-editor-plus-inactive > a').click()
    cy.get('.villain-editor-plus-available-blocks > :nth-child(1)').click()
    cy.get('p').click().type('This is a paragraph')

    cy.contains('Lagre fragment').click()

    cy.contains('Fragment opprettet')
    cy.location('pathname').should('eq', '/admin/sidefragmenter')
    cy.contains('parent')
    cy.contains('my-key')
  })
})
