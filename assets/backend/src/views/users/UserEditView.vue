<template>
  <article v-if="user">
    <ContentHeader>
      <template #title>
        {{ $t("user.title") }}
      </template>
      <template #subtitle>
        {{ $t("user.subtitle") }}
      </template>
    </ContentHeader>
    <UserForm :user="user" :save="save" />
  </article>
</template>

<script>
import gql from "graphql-tag";
import UserForm from "./UserForm";
import GET_USER from "../../gql/users/USER_QUERY.graphql";

export default {
  components: {
    UserForm,
  },

  props: {
    userId: {
      type: [String, Number],
      required: true,
    },
  },

  data() {
    return {};
  },

  methods: {
    async save(setLoader) {
      setLoader(true);

      const userParams = this.$utils.stripParams(this.user, [
        "__typename",
        "passwordConfirm",
        "id",
        "active",
        "lastLogin",
        "deletedAt",
      ]);
      this.$utils.validateImageParams(userParams, ["avatar"]);

      if (userParams.config) {
        delete userParams.config.__typename;
      }

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdateUser($userId: ID!, $userParams: UserParams) {
              updateUser(userId: $userId, userParams: $userParams) {
                id
              }
            }
          `,
          variables: {
            userParams,
            userId: this.userId,
          },
        });

        setLoader(false);
        this.$toast.success({ message: "Bruker oppdatert" });
        this.$router.push({ name: "users" });
      } catch (err) {
        this.$utils.showError(err);
        setLoader(false);
      }
    },
  },

  apollo: {
    user: {
      query: GET_USER,
      fetchPolicy: "no-cache",
      variables() {
        return {
          matches: { id: this.userId },
        };
      },

      skip() {
        return !this.userId;
      },
    },
  },
};
</script>
<i18n>
{
  "en": {
    "user.title": "Users",
    "user.subtitle": "Edit user"
  },
  "no": {
    "user.title": "Brukere",
    "user.subtitle": "Rediger brukerinformasjon"
  }
}
</i18n>
