<template>
  <KForm
    :back="{ name: 'users' }"
    @save="save">
    <section class="row">
      <div class="half">
        <KInputPassword
          v-model="user.password"
          rules="min:6|confirmed:user[passwordConfirm]"
          name="user[password]"
          :label="$t('password')"
          data-testid="password"
          :placeholder="$t('password')" />
        <KInputPassword
          v-model="user.passwordConfirm"
          name="user[passwordConfirm]"
          :label="$t('password-confirm')"
          data-testid="password-confirm"
          :placeholder="$t('password-confirm')" />
      </div>
    </section>
  </KForm>
</template>

<script>
export default {
  props: {
    user: {
      type: Object,
      default: () => {}
    },

    save: {
      type: Function,
      required: true
    }
  }
}
</script>
<i18n>
  {
    "en": {
        "password": "Password",
        "password-confirm": "Confirm password"
    },
    "no": {
        "password": "Passord",
        "password-confirm": "Bekreft passord"
    }
  }
</i18n>
