describe('Auth', () => {
  it('redirects to login page', () => {
    cy.visit('/admin/dashboard')
    cy.location('pathname').should('eq', '/admin/login')
  })

  it('has a sound login page', () => {
    cy.visit('/admin/login')
    cy.get('[data-testid="email"]').should('exist')
    cy.get('[data-testid="password"]').should('exist')
  })

  it('fails login for non-existing user', () => {
    cy.visit('/admin/login')
    cy.get('[data-testid="email"] input')
      .type('fake@email.com')
      .should('have.value', 'fake@email.com')

    cy.get('[data-testid="password"] input')
      .type('password')
      .should('have.value', 'password')

    cy.get('[data-testid="login-button"]').click()
    cy.get('.vex-content').contains('Feil brukernavn eller passord')
  })

  it('fails logging in with empty values', () => {
    cy.visit('/admin/login')
    cy.get('[data-testid="login-button"]').click()
    cy.get('.vex-content').contains('Feil brukernavn eller passord')
  })

  it('succeeds logging in as a first-time user', () => {
    cy.factorydb('user', {
      name: 'Lou Reed',
      avatar: null,
      email: 'lou@reed.com'
    })

    cy.visit('/admin/login')
    cy.get('[data-testid="email"] input')
      .type('lou@reed.com')
      .should('have.value', 'lou@reed.com')

    cy.get('[data-testid="password"] input')
      .type('admin')
      .should('have.value', 'admin')

    cy.get('[data-testid="login-button"]').click()

    cy.location('pathname').should('eq', '/admin/users/new-password')
    cy.contains('New password')

    cy.get('[data-testid="password"] input')
      .type('adminadmin')
      .should('have.value', 'adminadmin')

    cy.get('[data-testid="password-confirm"] input')
      .type('adminadmin')
      .should('have.value', 'adminadmin')

    cy.get('[data-testid="submit"]').click()

    cy.location('pathname').should('eq', '/admin/')

    cy.contains('Admin area')
    cy.contains('Lou Reed')
    cy.contains('superuser')
  })

  it('can log out', () => {
    cy.factorydb('user', { avatar: null, email: 'lou@reed.com', role: 'superuser' })
    cy.login('lou@reed.com', 'admin')
    cy.get('[data-testid="current-user"]').click()
    cy.get('[data-testid="logout"]').click()
    cy.location('pathname').should('eq', '/admin/login')
  })
})

describe('Pages', () => {
  beforeEach(() => {
    cy.loginUser()
  })

  it('can edit page', () => {
    cy.get('@currentUser').then(response => {
      cy.defaultlanguage().then(language => {
        cy.factorydb('page', { title: 'Page title', uri: 'page-title', language })
        cy.factorydb('module', {})

        cy.visit('/admin/pages')
        cy.contains('Pages and sections')

        cy.contains('Page title')
        cy.contains('page-title')

        cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testid="circle-dropdown-button"]')
          .click()
        cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testid="circle-dropdown-content"]')
          .contains('Edit page')
          .click()

        cy.location('pathname').should('match', /admin\/pages\/edit\/(\d+)/)
        cy.contains('Edit page')

        cy.get('#page_uri_').type('-edit')
        cy.get('#page_title_').type(' edit')

        cy.get('[data-testid="submit"]').click()

        cy.contains('Please correct fields with errors')

        cy.get('.vex-dialog-button-primary').click()

        cy.get('.villain-editor-plus-inactive > a').click()
        cy.get('.villain-editor-plus-available-module').last().click()
        cy.get('.villain-header-input').clear().click().type('This is a heading')

        cy.get('[data-testid="submit"]').click()

        cy.location('pathname').should('eq', '/admin/pages')
        cy.contains('Page updated')
        cy.contains('Page title edit')
        cy.contains('page-title-edit')
      })
    })
  })

  it('can list pages', () => {
    cy.get('@currentUser').then(response => {
      cy.factorydb('page', { title: 'Page title', uri: 'page-title' })
      cy.visit('/admin/pages')
      cy.contains('Pages and sections')

      cy.contains('Page title')
      cy.contains('page-title')
    })
  })

  it('can delete page', () => {
    cy.defaultlanguage().then(language => {
      cy.factorydb('page', { title: 'Page title', uri: 'page-title', language })
    })

    cy.get('@currentUser').then(response => {
      cy.visit('/admin/pages')
      cy.contains('Pages and sections')

      cy.contains('Page title')
      cy.contains('page-title')

      cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testid="circle-dropdown-button"]')
        .click()
      cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testid="circle-dropdown-content"]')
        .contains('Delete page')
        .click()
      cy.contains('Are you sure you want to delete this page?')

      cy.contains('OK').click()
      cy.contains('page-title').should('not.exist')
    })
  })

  it('can recreate page', () => {
    cy.defaultlanguage().then(language => {
      cy.factorydb('page', { title: 'Page title', uri: 'page-title', language })
    })
    cy.get('@currentUser').then(response => {
      cy.visit('/admin/pages')
      cy.contains('Pages and sections')

      cy.contains('Page title')
      cy.contains('page-title')

      cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testid="circle-dropdown-button"]').click()
      cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testid="circle-dropdown-button"]')
        .next()
        .contains('Rerender page')
        .click()

      cy.contains('Page rerendered')
    })
  })

  it('can duplicate page', () => {
    cy.defaultlanguage().then(language => {
      cy.factorydb('page', { title: 'Page title', uri: 'page-title', language, data: [{ 'type': 'text', 'data': { 'text': 'test', 'type': 'paragraph' } }] })
    })

    cy.get('@currentUser').then(response => {
      cy.visit('/admin/pages')
      cy.contains('Pages and sections')

      cy.contains('Page title')
      cy.contains('page-title')

      cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testid="circle-dropdown-button"]').click()
      cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testid="circle-dropdown-button"]')
        .next()
        .contains('Duplicate page')
        .click()

      cy.contains('Page duplicated')
      cy.contains('Page title_dupl')
      cy.contains('page-title_dupl')
    })
  })

  it('can create page', () => {
    cy.factorydb('module', {})
    cy.get('@currentUser').then(response => {
      cy.visit('/admin/pages')

      cy.get('.dropdown > .button').click()
      cy.contains('New page').click()

      cy.get('#page_uri_').type('my-uri')
      cy.get('#page_title_').type('My title')

      cy.get('.villain-editor-plus-inactive > a').click()
      cy.get('.villain-editor-plus-available-module').last().click()
      cy.get('.villain-header-input').clear().click().type('This is a heading')

      cy.get('[data-testid="meta-button"]').click()
      cy.get('#page_metaTitle_').type('A META title')
      cy.get('#page_metaDescription_').type('A META description')
      cy.get('[data-testid="meta-drawer"] .rev-button').click()
      cy.get('[data-testid="submit"]').click()

      cy.contains('Page created')
      cy.location('pathname').should('eq', '/admin/pages')
      cy.contains('my-uri')
      cy.contains('My title')
    })
  })

  it('can schedule future publishing', () => {
    cy.get('@currentUser').then(response => {
      cy.defaultlanguage().then(language => {
        cy.factorydb('page', { title: 'Page title', uri: 'page-title', language })
        cy.factorydb('module', {})

        cy.visit('/admin/pages/new')
      })
    })

    let today = new Date()
    today.setHours(today.getHours() + 1)

    cy.get('#page_title_').type('A scheduled post')
    cy.get('#page_uri_').type('a-scheduled-post')
    cy.get('.villain-editor-plus-inactive > a').click()
    cy.get('.villain-editor-plus-available-module').last().click()
    cy.get(':nth-child(1) > [data-testid=schedule-button]').click()
    cy.get('.form-control').type(`${today.toISOString()}{enter}`)
    cy.get('[data-testid=schedule-drawer] .rev-button').click()
    cy.get('.vex-dialog-message').should('contain', 'must be `pending`')
    cy.get('.vex-dialog-button-primary').click()
    cy.get('[data-testid=schedule-button]').then(($btn) => {
      // store the button's text
      const txt = $btn.text().replace('Scheduled at', '').trim()

      cy.get('[data-testid=submit]').click()
      cy.location('pathname').should('eq', '/admin/pages')
      cy.contains('Pages and sections')
      cy.contains('A scheduled post')
      cy.get('[data-testid="status-pending"]')
        .eq(0).invoke('show')
        .trigger('mouseenter')
        .wait(1000)
        .should('have.class', 'v-tooltip-open')
        .trigger('mouseleave')
      cy.get('.tooltip-inner').should('contain', `Publish at ${txt}`)
    })
  })

  it('can schedule past publishAt', () => {
    cy.get('@currentUser').then(response => {
      cy.defaultlanguage().then(language => {
        cy.factorydb('page', { title: 'Page title', uri: 'page-title', language })
        cy.factorydb('module', {})

        cy.visit('/admin/pages/new')
      })
    })

    let today = new Date()
    today.setHours(today.getHours() - 3)

    cy.get('[data-testid=status-published]').click()
    cy.get('#page_title_').type('A published post')
    cy.get('#page_uri_').type('a-published-post')
    cy.get('.villain-editor-plus-inactive > a').click()
    cy.get('.villain-editor-plus-available-module').last().click()
    cy.get(':nth-child(1) > [data-testid=schedule-button]').click()
    cy.get('.form-control').type(`${today.toISOString()}{enter}`)
    cy.get('[data-testid=schedule-drawer] .rev-button').click()
    cy.get('[data-testid=schedule-button]').then(($btn) => {
      cy.get('[data-testid=submit]').click()
      cy.location('pathname').should('eq', '/admin/pages')
      cy.contains('A published post')
      cy.get('[data-testid="status-published"]')
    })
  })
})

describe('Fragments', () => {
  beforeEach(() => {
    cy.loginUser()
  })

  it('can delete fragment', () => {
    cy.get('@currentUser').then(response => {
      cy.defaultlanguage().then(language => {
        cy.factorydb('page', { uri: 'about', creator_id: response.body.id, creator: null, language, sequence: 99 }).then(resp => {
          cy.factorydb('fragment', { language, title: 'A fine fragment', parent_key: 'about', page_id: resp.body.id, key: 'my-pf-key', creator_id: response.body.id, creator: null }).then(r => {
            cy.visit('/admin/pages')
            cy.contains('Page Title')
            cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testid="children-button"]').click()
            cy.contains('about/my-pf-key')
            cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testidx="0"] [data-testid="circle-dropdown-button"]')
              .click()
            cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testidx="0"] [data-testid="circle-dropdown-content"]')
              .contains('Delete section')
              .click()
            cy.get('.vex-dialog-button-primary').click()
            cy.contains('Section deleted')
          })
        })
      })
    })
  })

  it('can recreate fragment', () => {
    cy.get('@currentUser').then(response => {
      cy.defaultlanguage().then(language => {
        cy.factorydb('page', { uri: 'about', creator_id: response.body.id, creator: null, language, sequence: 99 }).then(resp => {
          cy.factorydb('fragment', { language, title: 'A fine fragment', parent_key: 'about', page_id: resp.body.id, key: 'my-pf-key', creator_id: response.body.id, creator: null }).then(r => {
            cy.visit('/admin/pages')
            cy.contains('Page Title')
            cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testid="children-button"]').click()
            cy.contains('about/my-pf-key')
            cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testidx="0"] [data-testid="circle-dropdown-button"]')
              .click()
            cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testidx="0"] [data-testid="circle-dropdown-content"]')
              .contains('Rerender section')
              .click()
            cy.contains('Section rerendered')
          })
        })
      })
    })
  })

  it('can duplicate fragment', () => {
    cy.get('@currentUser').then(response => {
      cy.defaultlanguage().then(language => {
        cy.factorydb('page', { uri: 'about', creator_id: response.body.id, creator: null, language, sequence: 99 }).then(resp => {
          cy.factorydb('fragment', { language, title: 'A fine fragment', parent_key: 'about', page_id: resp.body.id, key: 'my-pf-key', creator_id: response.body.id, creator: null, data: [] }).then(r => {
            cy.visit('/admin/pages')
            cy.contains('Page Title')
            cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testid="children-button"]').click()
            cy.contains('about/my-pf-key')
            cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testidx="0"] [data-testid="circle-dropdown-button"]')
              .click()
            cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testidx="0"] [data-testid="circle-dropdown-content"]')
              .contains('Duplicate section')
              .click()
            cy.contains('Section duplicated')
            cy.contains('my-pf-key_dupl')
          })
        })
      })
    })
  })

  it('can create fragment', () => {
    cy.factorydb('module', {})
    cy.get('@currentUser').then(response => {
      cy.defaultlanguage().then(language => {
        cy.factorydb('page', { uri: 'about', creator_id: response.body.id, creator: null, language, sequence: 99 }).then(resp => {
          cy.factorydb('fragment', { language, title: 'A fine fragment', parent_key: 'about', page_id: resp.body.id, key: 'my-pf-key', creator_id: response.body.id, creator: null, data: [] }).then(r => {
            cy.visit('/admin/pages')
            cy.contains('Page Title')
            cy.get('[data-testid="contentlist-row"][data-test-level="1"][data-testidx="1"] > .main-content [data-testid="circle-dropdown-button"]')
              .click()
            cy.get('[data-testid="contentlist-row"][data-test-level="1"][data-testidx="1"] > .main-content [data-testid="circle-dropdown-content"]')
              .contains('New section')
              .click()
            cy.contains('New section')

            cy.get('#page_title_').type('Section title')
            cy.get('#page_parentKey_').type('parent-key')
            cy.get('#page_key_').type('my-key')

            cy.get('.villain-editor-plus-inactive > a').click()
            cy.get('.villain-editor-plus-available-module').last().click()
            cy.get('.villain-header-input').clear().click().type('This is a heading')
            cy.get('[data-testid="submit"]').click()

            cy.contains('Section created')
            cy.location('pathname').should('eq', '/admin/pages')

            cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testid="children-button"]').click()
            cy.contains('parent-key/my-key')
          })
        })
      })
    })
  })

  it('can edit fragment', () => {
    cy.factorydb('module', {})
    cy.get('@currentUser').then(response => {
      cy.defaultlanguage().then(language => {
        cy.factorydb('page', { uri: 'about', creator_id: response.body.id, creator: null, language, sequence: 99 }).then(resp => {
          cy.factorydb('fragment', { language, title: 'A fine fragment', parent_key: 'about', page_id: resp.body.id, key: 'my-pf-key', creator_id: response.body.id, creator: null, data: [] }).then(r => {
            cy.visit('/admin/pages')
            cy.contains('Page Title')
            cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testid="children-button"]').click()
            cy.contains('about/my-pf-key')
            cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testidx="0"] [data-testid="circle-dropdown-button"]')
              .click()
            cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testidx="0"] [data-testid="circle-dropdown-content"]')
              .contains('Edit section')
              .click()
            cy.contains('Edit section')

            cy.get('#page_title_').type(' edit')
            cy.get('#page_key_').type('-edit')

            cy.get('.villain-editor-plus-inactive > a').click()
            cy.get('.villain-editor-plus-available-module').last().click()
            cy.get('.villain-header-input').clear().click().type('This is an edited heading')
            cy.get('[data-testid="submit"]').click()

            cy.location('pathname').should('eq', '/admin/pages')
            cy.contains('Section updated')

            cy.get('[data-testid="contentlist-row"][data-testidx="1"] [data-testid="children-button"]').click()
            cy.contains('A fine fragment edit')
            cy.contains('about/my-pf-key-edit')
          })
        })
      })
    })
  })
})

describe('Users', () => {
  beforeEach(() => {
    cy.loginUser()
  })

  it('can visit profile from dropdown', () => {
    cy.get('@currentUser').then(response => {
      cy.visit('/admin')
      cy.get('[data-testid="current-user"]').click()
      cy.contains('Edit profile').click()
      cy.location('pathname').should('eq', '/admin/profile')
    })
  })

  it('can edit profile', () => {
    cy.get('@currentUser').then(response => {
      cy.visit('/admin/profile')
      cy.get('#user_name_').clear().type('Louis Reed III')
      cy.get('#user_email_').clear().type('louis.reed@gmail.com')
      cy.get('#user_password_').clear().type('password')
      cy.get('#user_passwordConfirm_').clear().type('password')

      cy.get('#user_avatar_').attachFile(
        'avatar.jpg',
        { subjectType: 'drag-n-drop' }
      )

      cy.wait(1000)

      cy.get('[data-testid="submit"]').click()

      cy.contains('Creating image size')
      cy.contains('Profile updated', { timeout: 40000 })

      cy.visit('/admin/users')
      cy.contains('Louis Reed III')
    })
  })

  it('can list users', () => {
    cy.get('@currentUser').then(response => {
      cy.factorydb('user', { avatar: null, name: 'Iggy Pop', email: 'iggy@pop.com' })
      cy.factorydb('user', { avatar: null, name: 'David Bowie', email: 'david@bowie.com' })
      cy.visit('/admin/users')
      cy.contains('Iggy Pop')
      cy.contains('David Bowie')
    })
  })

  it('can deactivate users', () => {
    cy.get('@currentUser').then(response => {
      cy.factorydb('user', { avatar: null, name: 'Iggy Pop', email: 'iggy@pop.com', role: 'admin' })
      cy.factorydb('user', { avatar: null, name: 'David Bowie', email: 'david@bowie.com' })
      cy.visit('/admin/users')
      cy.contains('Iggy Pop')
      cy.contains('David Bowie')

      cy.get('[data-testidx="0"] > .main-content [data-testid=circle-dropdown-button]').click()
      cy.get('[data-testidx="0"] > .main-content [data-testid=circle-dropdown-content] > li > button').click()
      cy.contains('Superuser cannot be deactivated')
      cy.get('.vex-dialog-button-primary').click()

      cy.get('[data-testidx="2"] > .main-content > .col-1 > .wrapper > [data-testid=circle-dropdown-button]').click()
      cy.get('[data-testidx="2"] > .main-content > .col-1 > .wrapper > [data-testid=circle-dropdown-content] > li > button').click()

      cy.contains('User deactivated')
    })
  })

  it('can add user', () => {
    cy.get('@currentUser').then(response => {
      cy.factorydb('user', { avatar: null, name: 'Iggy Pop', email: 'iggy@pop.com', role: 'admin' })
      cy.visit('/admin/users/new')
      cy.contains('New user')

      cy.get(':nth-child(1) > :nth-child(1) > .radios-wrapper > :nth-child(1) > .form-check-label > .form-check-input').check()
      cy.get('#user_name_').type('Ron Asheton')
      cy.get('#user_email_').type('ron@stooges.com')
      cy.get('#user_password_').type('password')
      cy.get('#user_passwordConfirm_').type('password')

      cy.get('[data-testid="submit"').click()

      cy.contains('User created')

      cy.location('pathname').should('eq', '/admin/users')
      cy.contains('Ron Asheton')
    })
  })
})
