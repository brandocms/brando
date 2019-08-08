describe('Pages', () => {
  beforeEach(() => {
    cy.factorydb('user', { email: 'lou@reed.com', role: 'superuser' })
    cy.login('lou@reed.com', 'admin')
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

    cy.get('tr > :nth-child(6) .dropdown').click()
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

    cy.get('tr > :nth-child(6) .dropdown').click()
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

    cy.get('tr > :nth-child(6) .dropdown').click()
    cy.contains('Reprosessér side').click()
    cy.contains('Siden ble gjengitt på nytt')
  })

  it('can duplicate page', () => {
    cy.factorydb('page', { title: 'Page title', slug: 'page-title', data: '[]' })
    cy.visit('/admin/sider')
    cy.contains('Administrér sideinnhold og fragmenter')

    cy.contains('Page title')
    cy.contains('a-key')

    cy.get('tr > :nth-child(6) .dropdown').click()
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
