/**
 * Generated test for <%= Recase.SentenceCase.convert(snake_domain) %>
 */
describe('<%= Recase.SentenceCase.convert(snake_domain) %>', () => {
  beforeEach(() => {
    cy.loginUser()
  })

  it('can list <%= Recase.SentenceCase.convert(plural) |> String.downcase() %>', () => {
    cy.get('@currentUser').then(response => {
      cy.factorydb('<%= singular %>', {})
      cy.factorydb('<%= singular %>', {})
      cy.factorydb('<%= singular %>', {})
      cy.visit('/admin/<%= plural %>')
      cy.location('pathname').should('eq', '/admin/<%= plural %>')
      cy.contains('Ny <%= vue_singular %>')
    })
  })

  it('can create <%= Recase.SentenceCase.convert(plural) |> String.downcase() %>', () => {
    cy.get('@currentUser').then(response => {
      cy.visit('/admin/<%= plural %>')
      cy.contains('Ny <%= singular %>').click()
      cy.location('pathname').should('eq', '/admin/<%= singular %>/ny')
      <%= for {_, cypress_field} <- cypress_fields do %>
      <%= Enum.join(cypress_field, "\n      ") %><% end %>

      cy.contains('Lagre').click()
      cy.location('pathname').should('eq', '/admin/<%= plural %>')
      cy.contains('Objekt opprettet')
      cy.contains('Kunstnersamtale')
      cy.contains('Ny <%= vue_singular %>')
    })
  })

  it('can edit <%= Recase.SentenceCase.convert(plural) |> String.downcase() %>', () => {
    cy.get('@currentUser').then(response => {
      cy.factorydb('<%= singular %>', { name: 'Happening' })
      cy.visit('/admin/<%= plural %>')
      cy.contains('Happening')
      cy.get('tr > :nth-child(4) .dropdown').click()
      cy.contains('Endre').click()

      cy.location('pathname').should('match', /admin\/<%= singular %>\/endre\/(\d+)/)
      cy.contains('Endre')
      <%= for { _, cypress_field } <- cypress_fields do %>
      <%= Enum.join(cypress_field, "\n      ") %><% end %>

      cy.contains('Lagre').click()
      cy.location('pathname').should('eq', '/admin/<%= plural %>')
      cy.contains('Objekt endret')
      cy.contains('Happening Edit')
    })
  })

  it('can delete <%= Recase.SentenceCase.convert(plural) |> String.downcase() %>', () => {
    cy.get('@currentUser').then(response => {
      cy.factorydb('<%= singular %>', {})
      cy.visit('/admin/<%= plural %>')
      cy.get('tr > :nth-child(4) .dropdown').click()
      cy.contains('Slett').click()
      cy.contains('Er du sikker på at du vil slette dette objektet?')
      cy.contains('OK').click()
      cy.contains('Objektet ble slettet')
    })
  })
})

