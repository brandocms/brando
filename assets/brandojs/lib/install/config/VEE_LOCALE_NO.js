const messages = {
  required: () => `Feltet er påkrevet`,
  email: () => `Feltet må være en gyldig epost-adresse`,
  confirmed: () => `Passordene matcher ikke`,
  min: (f, len) => `Må ha minst ${len} tegn`,
  url: () => `Må være en gyldig URL`
}

export default {
  name: 'no',
  messages,
  attributes: {}
}
