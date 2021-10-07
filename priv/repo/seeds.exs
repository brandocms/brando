%Brando.Sites.Identity{
  type: "organization",
  name: "Organization name",
  alternate_name: "Shortform name",
  email: "mail@domain.tld",
  phone: "+47 00 00 00 00",
  address: "Testveien 1",
  zipcode: "0000",
  city: "Oslo",
  country: "NO",
  language: :en,
  title_prefix: "CompanyName | ",
  title: "Welcome!",
  title_postfix: "",
  logo: nil,
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
  configs: [
    %Brando.ConfigEntry{
      key: "key1",
      value: "value1"
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

%Brando.Sites.SEO{
  fallback_meta_description: "Fallback meta description",
  fallback_meta_title: "Fallback meta title",
  fallback_meta_image: nil,
  base_url: "https://www.domain.tld",
  robots: """
  User-agent: *
  Disallow: /admin/
  """
}
|> Brando.repo().insert!
