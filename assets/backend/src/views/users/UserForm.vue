<template>
  <KForm :back="{ name: 'users' }" @save="save">
    <section class="row">
      <div class="sized">
        <KInput
          v-model="user.name"
          :label="$t('user.name')"
          :help-text="$t('user.name.help')"
          rules="required"
          placeholder="Navn Navnesen"
          name="user[name]"
        />

        <KInputEmail
          v-model="user.email"
          :label="$t('user.email')"
          :help-text="$t('user.email.help')"
          rules="required|email"
          placeholder="min@epost.no"
          name="user[email]"
        />

        <div class="row">
          <KInputRadios
            v-if="!myRoleIsLower"
            v-model="user.role"
            rules="required"
            :label="$t('user.role')"
            :options="[
              { name: $t('role.super'), value: 'superuser' },
              { name: $t('role.admin'), value: 'admin' },
              { name: $t('role.editor'), value: 'editor' },
              { name: $t('role.user'), value: 'user' },
            ]"
            name="user[role]"
          />

          <KInputRadios
            v-model="user.language"
            rules="required"
            :options="[
              { name: 'English', value: 'en' },
              { name: 'Norsk', value: 'no' },
            ]"
            name="user[language]"
            :label="$t('user.language')"
          />
        </div>

        <KInputPassword
          v-model="user.password"
          :label="$t('user.password')"
          :placeholder="$t('user.password')"
          rules="min:6|confirmed:user[passwordConfirm]"
          name="user[password]"
        />
        <KInputPassword
          v-model="user.passwordConfirm"
          :label="$t('user.passwordConfirm')"
          :placeholder="$t('user.passwordConfirm')"
          name="user[passwordConfirm]"
        />
      </div>
      <div class="half">
        <KInputImage
          v-model="user.avatar"
          preview-key="xlarge"
          :label="$t('user.avatar')"
          :help-text="$t('user.avatar.help')"
          name="user[avatar]"
        />

        <KInputToggle
          v-model="user.config.resetPasswordOnFirstLogin"
          name="user[config][resetPassword]"
          :label="$t('user.mustResetPassword')"
        />

        <KInputToggle
          v-model="user.config.showMutationNotifications"
          name="user[config][showMutationNotifications]"
          :label="$t('user.showMutationNotifications')"
        />
      </div>
    </section>
  </KForm>
</template>

<script>
export default {
  inject: ['GLOBALS'],
  props: {
    user: {
      type: Object,
      default: () => {},
    },

    save: {
      type: Function,
      required: true,
    },
  },

  computed: {
    myRoleIsLower () {
      if (this.GLOBALS.me.role === 'superuser') {
        return
      }

      if (this.GLOBALS.me.role === 'admin') {
        if (this.user.role === 'superuser') {
          return true
        }
        if (this.user.role === 'admin') {
          return true
        }
        return false
      }

      return true
    }
  }
};
</script>
<i18n>
{
  "en": {
    "user.language": "Language",
    "user.password": "Password",
    "user.passwordConfirm": "Confirm password",
    "user.avatar": "Avatar",
    "user.avatar.help": "Click to set focal point.",
    "user.email": "Email",
    "user.email.help": "used for login and notifications",
    "user.name": "Name",
    "user.name.help": "name also used as entry author",
    "user.role": "Role",
    "user.showMutationNotifications": "Show notifications for create/update/delete actions",
    "profile.title": "Your User Profile",
    "profile.helpText": "Administrate user info",
    "user.mustResetPassword": "User must reset password on first login",
    "role.super": "Super",
    "role.admin": "Admin",
    "role.editor": "Editor",
    "role.user": "User"
  },
  "no": {
    "user.language": "Språk",
    "user.password": "Passord",
    "user.passwordConfirm": "Bekreft passord",
    "user.avatar": "Profilbilde",
    "user.avatar.help": "Klikk på bildet for å sette fokuspunkt.",
    "user.email": "Epost",
    "user.email.help": "brukes til innlogging og notifikasjoner",
    "user.name": "Navn",
    "user.name.help": "navnet brukes også som artikkelforfatter",
    "user.role": "Rolle",
    "user.showMutationNotifications": "Vis notifikasjoner for oppretting/oppdatering/sletting av objekter",
    "user.mustResetPassword": "Bruker må sette nytt passord ved første innlogging",
    "user.title": "Din brukerprofil",
    "user.helpText": "Administrasjon av brukerinfo",
    "role.super": "Super",
    "role.admin": "Admin",
    "role.editor": "Redaktør",
    "role.user": "Bruker"
  }
}
</i18n>
