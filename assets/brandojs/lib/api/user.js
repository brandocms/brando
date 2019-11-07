import apollo from './apolloClient'
import { handleErr } from './errorHandler.js'
import { pick } from '../utils'

import ME_QUERY from './graphql/users/ME_QUERY.graphql'
import USER_QUERY from './graphql/users/USER_QUERY.graphql'
import USERS_QUERY from './graphql/users/USERS_QUERY.graphql'
import CREATE_MUTATION from './graphql/users/CREATE_MUTATION.graphql'
import UPDATE_MUTATION from './graphql/users/UPDATE_MUTATION.graphql'

const userAPI = {
  /**
   * getMe - get current authed user
   *
   * @return {Object}
   */
  async getMe () {
    try {
      const result = await apollo.client.query({
        query: ME_QUERY,
        fetchPolicy: 'no-cache'
      })
      return result.data.me
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * getUsers - get all users
   *
   * @return {Object}
   */
  async getUsers () {
    try {
      const result = await apollo.client.query({
        query: USERS_QUERY,
        fetchPolicy: 'no-cache'
      })
      return result.data.users
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * getUser - get specific user by id
   *
   * @param {Number} userId
   * @return {Object}
   */
  async getUser (userId) {
    try {
      const result = await apollo.client.query({
        query: USER_QUERY,
        variables: {
          userId: userId
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.user
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * createUser - Mutation for creating user
   *
   * @param {Object} userParams
   * @return {Object}
   */
  async createUser (userParams) {
    try {
      const result = await apollo.client.mutate({
        mutation: CREATE_MUTATION,
        variables: {
          user_params: pick(userParams, 'full_name', 'email', 'password', 'role', 'language', 'username')
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.create_user
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * updateUser - Mutation for updating user
   *
   * @param {Number} userId
   * @param {Object} userParams
   * @return {Object}
   */
  async updateUser (userId, userParams) {
    try {
      const result = await apollo.client.mutate({
        mutation: UPDATE_MUTATION,
        variables: {
          user_id: userId,
          user_params: userParams
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.update_user
    } catch (err) {
      handleErr(err)
    }
  }
}

export {
  userAPI
}
