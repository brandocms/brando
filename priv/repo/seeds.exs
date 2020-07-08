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
  url: "https://www.domain.tld",
  links: [
    %Brando.Link{
      name: "Instagram",
      url: "https://instagram.com/test"
    },
    %Brando.Link{
      name: "Facebook",
      url: "https://facebook.com/test"
    }
  ],
  metas: [
    %Brando.Meta{
      key: "key1",
      value: "value1"
    },
    %Brando.Meta{
      key: "key2",
      value: "value2"
    }
  ]
}
|> Brando.repo().insert!
