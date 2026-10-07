defmodule Brando.JSONLD.Schema.JobPosting do
  @moduledoc """
  A job opening, for Google's job search experience.

  Google requires `title`, `description` (HTML is allowed), `datePosted`,
  `hiringOrganization` and `jobLocation`, or for a remote job
  `jobLocationType: "TELECOMMUTE"` with `applicantLocationRequirements`.
  `validThrough`, `employmentType` and `baseSalary` are recommended.

      json_ld_schema JSONLD.Schema.JobPosting do
        field :title, :string, & &1.title
        field :description, :string, & &1.description
        field :datePosted, :date, & &1.publish_at
        field :validThrough, :datetime, & &1.deadline
        field :employmentType, :string, fn _ -> "FULL_TIME" end
        field :hiringOrganization, :identity
        field :jobLocation, JSONLD.Schema.Place, & &1.office
        field :baseSalary, JSONLD.Schema.MonetaryAmount, &%{currency: "NOK", min: &1.salary_from, max: &1.salary_to, unit: "YEAR"}
        field :url, :current_url
      end

  A remote job sets the location type and where applicants may live:

      field :jobLocationType, :string, fn _ -> "TELECOMMUTE" end
      field :applicantLocationRequirements, JSONLD.Schema.Thing, fn _ -> %{type: "Country", name: "NO"} end

  `employmentType` is one or a list of `FULL_TIME`, `PART_TIME`,
  `CONTRACTOR`, `TEMPORARY`, `INTERN`, `VOLUNTEER`, `PER_DIEM` or `OTHER`.

  https://developers.google.com/search/docs/appearance/structured-data/job-posting
  """

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "JobPosting",
            "@id": nil,
            title: nil,
            description: nil,
            datePosted: nil,
            validThrough: nil,
            employmentType: nil,
            hiringOrganization: nil,
            jobLocation: nil,
            jobLocationType: nil,
            applicantLocationRequirements: nil,
            baseSalary: nil,
            directApply: nil,
            identifier: nil,
            url: nil

  @employment_types ~w(FULL_TIME PART_TIME CONTRACTOR TEMPORARY INTERN VOLUNTEER PER_DIEM OTHER)

  @doc "The employment types Google reads."
  @spec employment_types() :: [String.t()]
  def employment_types, do: @employment_types
end
