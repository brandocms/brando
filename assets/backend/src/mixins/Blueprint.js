import gql from 'graphql-tag'

export default function ({ blueprint }) {
  return {
    inject: [
      'adminChannel'
    ],

    data () {
      return {
        blueprint: null
      }
    },

    // created () {
    //   this.getBlueprint()
    // },

    // methods: {
    //   getBlueprint (blueprint) {
    //     this.adminChannel.channel
    //       .push('blueprint:get', { blueprint })
    //       .receive('ok', blueprint => this.blueprint = blueprint)
    //   }
    // }

    apollo: {
      blueprint: {
        query: gql`
          query Blueprint ($source: String!) {
            blueprint (source: $source) {
              application
              domain
              schema

              modules {
                schema
                context
                blueprint
              }
            }
          }
        `,
        variables: {
          source: blueprint
        }
      }
    }
  }
}