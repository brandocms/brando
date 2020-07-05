%Brando.Sites.Identity{
  type: "organization",
  name: "Organisasjonens navn",
  alternate_name: "Kortversjon av navnet",
  email: "mail@domain.tld",
  phone: "+47 00 00 00 00",
  address: "Testveien 1",
  zipcode: "0000",
  city: "Oslo",
  country: "NO",
  description: "Beskrivelse av organisasjonen/nettsiden",
  title_prefix: "Firma | ",
  title: "Velkommen!",
  title_postfix: "",
  image: nil,
  logo: nil,
  url: "https://www.domain.tld"
}
|> Brando.repo().insert!
