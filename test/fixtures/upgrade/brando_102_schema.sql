-- Brando's own tables as a pre-blocks 0.53.0-dev site had them, with
-- brando_102 as its newest Brando migration and content still Villain JSON in
-- `pages.data` and `pages_fragments.data`. Schema only, from a production
-- site's database (pg_dump --schema-only --no-owner --no-privileges --no-comments, then
-- Oban's version comment put back), with the
-- site's own tables left out. Used by
-- test/brando/migrations/upgrade_from_villain_test.exs.


CREATE TYPE public.oban_job_state AS ENUM (
    'available',
    'scheduled',
    'executing',
    'retryable',
    'completed',
    'discarded',
    'cancelled'
);

CREATE FUNCTION public.oban_jobs_notify() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  channel text;
  notice json;
BEGIN
  IF NEW.state = 'available' THEN
    channel = 'public.oban_insert';
    notice = json_build_object('queue', NEW.queue, 'state', NEW.state);

    PERFORM pg_notify(channel, notice::text);
  END IF;

  RETURN NULL;
END;
$$;

SET default_tablespace = '';

SET default_table_access_method = heap;

CREATE TABLE public.content_identifiers (
    id bigint NOT NULL,
    entry_id integer,
    schema character varying(255),
    title character varying(255),
    status integer,
    language character varying(255),
    cover character varying(255),
    updated_at timestamp(0) without time zone
);

CREATE SEQUENCE public.content_identifiers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.content_identifiers_id_seq OWNED BY public.content_identifiers.id;

CREATE TABLE public.content_modules (
    id bigint NOT NULL,
    name character varying(255),
    namespace character varying(255),
    help_text text,
    class character varying(255),
    code text,
    refs jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    sequence integer DEFAULT 0,
    deleted_at timestamp(0) without time zone,
    vars jsonb,
    svg text,
    entry_template jsonb,
    wrapper boolean DEFAULT false,
    datasource boolean DEFAULT false,
    datasource_module character varying(255),
    datasource_type character varying(255),
    datasource_query character varying(255)
);

CREATE TABLE public.content_palettes (
    id bigint NOT NULL,
    name text,
    key text,
    namespace text,
    sequence integer,
    global boolean DEFAULT false,
    instructions text,
    colors jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    deleted_at timestamp(0) without time zone,
    creator_id bigint,
    status integer DEFAULT 1
);

CREATE SEQUENCE public.content_palettes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.content_palettes_id_seq OWNED BY public.content_palettes.id;

CREATE TABLE public.content_templates (
    id bigint NOT NULL,
    name text,
    namespace text,
    data jsonb,
    html text,
    instructions text,
    sequence integer,
    deleted_at timestamp(0) without time zone,
    creator_id bigint,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);

CREATE SEQUENCE public.content_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.content_templates_id_seq OWNED BY public.content_templates.id;

CREATE TABLE public.files (
    id bigint NOT NULL,
    title text,
    mime_type text,
    filesize integer,
    filename text,
    config_target text,
    cdn boolean,
    deleted_at timestamp(0) without time zone,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    creator_id bigint
);

CREATE SEQUENCE public.files_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.files_id_seq OWNED BY public.files.id;

CREATE TABLE public.images (
    id bigint NOT NULL,
    creator_id bigint,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    deleted_at timestamp(0) without time zone,
    config_target text DEFAULT 'default'::text,
    title text,
    credits text,
    alt text,
    formats character varying(255)[],
    path text,
    width integer,
    height integer,
    sizes jsonb,
    cdn boolean DEFAULT false,
    dominant_color text,
    focal jsonb,
    status character varying(255) DEFAULT 'processed'::character varying
);

CREATE TABLE public.images_galleries (
    id bigint NOT NULL,
    config_target text,
    deleted_at timestamp(0) without time zone,
    creator_id bigint,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);

CREATE SEQUENCE public.images_galleries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.images_galleries_id_seq OWNED BY public.images_galleries.id;

CREATE TABLE public.images_gallery_images (
    id bigint NOT NULL,
    sequence integer,
    gallery_id bigint,
    image_id bigint,
    creator_id bigint,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);

CREATE SEQUENCE public.images_gallery_images_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.images_gallery_images_id_seq OWNED BY public.images_gallery_images.id;

CREATE SEQUENCE public.images_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.images_id_seq OWNED BY public.images.id;

CREATE TABLE public.navigation_menus (
    id bigint NOT NULL,
    status integer,
    title text,
    key text,
    language text,
    template text,
    creator_id bigint,
    sequence integer DEFAULT 0,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    items jsonb
);

CREATE SEQUENCE public.navigation_menus_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.navigation_menus_id_seq OWNED BY public.navigation_menus.id;

CREATE TABLE public.oban_beats (
    node text NOT NULL,
    queue text NOT NULL,
    nonce text NOT NULL,
    "limit" integer NOT NULL,
    paused boolean DEFAULT false NOT NULL,
    running bigint[] DEFAULT ARRAY[]::integer[] NOT NULL,
    inserted_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    started_at timestamp without time zone NOT NULL
);

CREATE TABLE public.oban_jobs (
    id bigint NOT NULL,
    state public.oban_job_state DEFAULT 'available'::public.oban_job_state NOT NULL,
    queue text DEFAULT 'default'::text NOT NULL,
    worker text NOT NULL,
    args jsonb DEFAULT '{}'::jsonb NOT NULL,
    errors jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    attempt integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 20 NOT NULL,
    inserted_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    scheduled_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    attempted_at timestamp without time zone,
    completed_at timestamp without time zone,
    attempted_by text[],
    discarded_at timestamp without time zone,
    priority integer DEFAULT 0 NOT NULL,
    tags character varying(255)[] DEFAULT ARRAY[]::character varying[],
    meta jsonb DEFAULT '{}'::jsonb,
    cancelled_at timestamp without time zone,
    CONSTRAINT attempt_range CHECK (((attempt >= 0) AND (attempt <= max_attempts))),
    CONSTRAINT positive_max_attempts CHECK ((max_attempts > 0)),
    CONSTRAINT priority_range CHECK (((priority >= 0) AND (priority <= 3))),
    CONSTRAINT queue_length CHECK (((char_length(queue) > 0) AND (char_length(queue) < 128))),
    CONSTRAINT worker_length CHECK (((char_length(worker) > 0) AND (char_length(worker) < 128)))
);

-- Oban's migrations read their version from this comment
COMMENT ON TABLE public.oban_jobs IS '11';

CREATE SEQUENCE public.oban_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.oban_jobs_id_seq OWNED BY public.oban_jobs.id;

CREATE UNLOGGED TABLE public.oban_peers (
    name text NOT NULL,
    node text NOT NULL,
    started_at timestamp without time zone NOT NULL,
    expires_at timestamp without time zone NOT NULL
);

CREATE TABLE public.pages_fragments (
    id bigint NOT NULL,
    parent_key text,
    key text,
    language text,
    data jsonb,
    html text,
    creator_id bigint,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    page_id bigint,
    wrapper text,
    deleted_at timestamp(0) without time zone,
    sequence integer DEFAULT 0,
    title text,
    publish_at timestamp(0) without time zone,
    status integer DEFAULT 1
);

CREATE SEQUENCE public.pagefragments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.pagefragments_id_seq OWNED BY public.pages_fragments.id;

CREATE TABLE public.pages (
    id bigint NOT NULL,
    uri text NOT NULL,
    language text NOT NULL,
    title text NOT NULL,
    data jsonb,
    html text,
    status integer,
    parent_id bigint,
    creator_id bigint,
    css_classes text,
    meta_description text,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    deleted_at timestamp(0) without time zone,
    sequence integer DEFAULT 0,
    template text DEFAULT 'default.html'::text,
    publish_at timestamp(0) without time zone,
    is_homepage boolean DEFAULT false,
    meta_title text,
    vars jsonb,
    meta_image_id bigint,
    has_url boolean DEFAULT true
);

CREATE TABLE public.pages_alternates (
    id bigint NOT NULL,
    entry_id bigint,
    linked_entry_id bigint,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);

CREATE SEQUENCE public.pages_alternates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.pages_alternates_id_seq OWNED BY public.pages_alternates.id;

CREATE SEQUENCE public.pages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.pages_id_seq OWNED BY public.pages.id;

CREATE TABLE public.revisions (
    active boolean DEFAULT false,
    entry_id integer NOT NULL,
    entry_type character varying(255) NOT NULL,
    encoded_entry bytea NOT NULL,
    creator_id bigint,
    metadata jsonb NOT NULL,
    revision integer NOT NULL,
    protected boolean DEFAULT false,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    description text
);

CREATE TABLE public.sites_global_sets (
    id bigint NOT NULL,
    key character varying(255),
    label text,
    globals jsonb,
    language text DEFAULT 'en'::text,
    creator_id bigint,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);

CREATE SEQUENCE public.sites_global_categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.sites_global_categories_id_seq OWNED BY public.sites_global_sets.id;

CREATE TABLE public.sites_identities (
    id bigint NOT NULL,
    name character varying(255),
    alternate_name character varying(255),
    email character varying(255),
    phone character varying(255),
    address character varying(255),
    zipcode character varying(255),
    city character varying(255),
    country character varying(255),
    description text,
    title_prefix character varying(255),
    title text,
    title_postfix character varying(255),
    url character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    metas jsonb,
    links jsonb,
    configs jsonb,
    type character varying(255) DEFAULT 'organization'::character varying,
    address2 character varying(255),
    address3 character varying(255),
    language text DEFAULT 'en'::text,
    logo_id bigint
);

CREATE SEQUENCE public.sites_organizations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.sites_organizations_id_seq OWNED BY public.sites_identities.id;

CREATE TABLE public.sites_previews (
    id bigint NOT NULL,
    preview_key character varying(255) NOT NULL,
    expires_at timestamp(0) without time zone NOT NULL,
    html bytea,
    creator_id bigint,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);

CREATE SEQUENCE public.sites_previews_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.sites_previews_id_seq OWNED BY public.sites_previews.id;

CREATE TABLE public.sites_seos (
    id bigint NOT NULL,
    fallback_meta_description text,
    fallback_meta_title text,
    base_url text,
    robots text,
    redirects jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    language text DEFAULT 'en'::text,
    fallback_meta_image_id bigint
);

CREATE SEQUENCE public.sites_seo_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.sites_seo_id_seq OWNED BY public.sites_seos.id;

CREATE SEQUENCE public.templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.templates_id_seq OWNED BY public.content_modules.id;

CREATE TABLE public.users (
    id bigint NOT NULL,
    name text,
    email text,
    password text,
    language text DEFAULT 'nb'::text,
    active boolean DEFAULT true,
    last_login timestamp(0) without time zone,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    deleted_at timestamp(0) without time zone,
    config jsonb DEFAULT '{}'::jsonb,
    role text,
    avatar_id bigint
);

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;

CREATE TABLE public.users_tokens (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    token bytea NOT NULL,
    context character varying(255) NOT NULL,
    sent_to character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL
);

CREATE SEQUENCE public.users_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.users_tokens_id_seq OWNED BY public.users_tokens.id;

CREATE TABLE public.videos (
    id bigint NOT NULL,
    url text,
    source text,
    filename text,
    remote_id text,
    width integer,
    height integer,
    thumbnail_url text,
    autoplay boolean,
    preload boolean,
    loop boolean,
    controls boolean,
    cdn boolean,
    config_target text,
    creator_id bigint,
    cover_image_id bigint,
    deleted_at timestamp(0) without time zone,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);

CREATE SEQUENCE public.videos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.videos_id_seq OWNED BY public.videos.id;

ALTER TABLE ONLY public.content_identifiers ALTER COLUMN id SET DEFAULT nextval('public.content_identifiers_id_seq'::regclass);

ALTER TABLE ONLY public.content_modules ALTER COLUMN id SET DEFAULT nextval('public.templates_id_seq'::regclass);

ALTER TABLE ONLY public.content_palettes ALTER COLUMN id SET DEFAULT nextval('public.content_palettes_id_seq'::regclass);

ALTER TABLE ONLY public.content_templates ALTER COLUMN id SET DEFAULT nextval('public.content_templates_id_seq'::regclass);

ALTER TABLE ONLY public.files ALTER COLUMN id SET DEFAULT nextval('public.files_id_seq'::regclass);

ALTER TABLE ONLY public.images ALTER COLUMN id SET DEFAULT nextval('public.images_id_seq'::regclass);

ALTER TABLE ONLY public.images_galleries ALTER COLUMN id SET DEFAULT nextval('public.images_galleries_id_seq'::regclass);

ALTER TABLE ONLY public.images_gallery_images ALTER COLUMN id SET DEFAULT nextval('public.images_gallery_images_id_seq'::regclass);

ALTER TABLE ONLY public.navigation_menus ALTER COLUMN id SET DEFAULT nextval('public.navigation_menus_id_seq'::regclass);

ALTER TABLE ONLY public.oban_jobs ALTER COLUMN id SET DEFAULT nextval('public.oban_jobs_id_seq'::regclass);

ALTER TABLE ONLY public.pages ALTER COLUMN id SET DEFAULT nextval('public.pages_id_seq'::regclass);

ALTER TABLE ONLY public.pages_alternates ALTER COLUMN id SET DEFAULT nextval('public.pages_alternates_id_seq'::regclass);

ALTER TABLE ONLY public.pages_fragments ALTER COLUMN id SET DEFAULT nextval('public.pagefragments_id_seq'::regclass);

ALTER TABLE ONLY public.sites_global_sets ALTER COLUMN id SET DEFAULT nextval('public.sites_global_categories_id_seq'::regclass);

ALTER TABLE ONLY public.sites_identities ALTER COLUMN id SET DEFAULT nextval('public.sites_organizations_id_seq'::regclass);

ALTER TABLE ONLY public.sites_previews ALTER COLUMN id SET DEFAULT nextval('public.sites_previews_id_seq'::regclass);

ALTER TABLE ONLY public.sites_seos ALTER COLUMN id SET DEFAULT nextval('public.sites_seo_id_seq'::regclass);

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);

ALTER TABLE ONLY public.users_tokens ALTER COLUMN id SET DEFAULT nextval('public.users_tokens_id_seq'::regclass);

ALTER TABLE ONLY public.videos ALTER COLUMN id SET DEFAULT nextval('public.videos_id_seq'::regclass);

ALTER TABLE ONLY public.content_identifiers
    ADD CONSTRAINT content_identifiers_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.content_palettes
    ADD CONSTRAINT content_palettes_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.content_templates
    ADD CONSTRAINT content_templates_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.files
    ADD CONSTRAINT files_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.images_galleries
    ADD CONSTRAINT images_galleries_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.images_gallery_images
    ADD CONSTRAINT images_gallery_images_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.images
    ADD CONSTRAINT images_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.navigation_menus
    ADD CONSTRAINT navigation_menus_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.oban_jobs
    ADD CONSTRAINT oban_jobs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.oban_peers
    ADD CONSTRAINT oban_peers_pkey PRIMARY KEY (name);

ALTER TABLE ONLY public.pages_fragments
    ADD CONSTRAINT pagefragments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.pages_alternates
    ADD CONSTRAINT pages_alternates_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.pages
    ADD CONSTRAINT pages_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.sites_global_sets
    ADD CONSTRAINT sites_global_categories_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.sites_identities
    ADD CONSTRAINT sites_organizations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.sites_previews
    ADD CONSTRAINT sites_previews_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.sites_seos
    ADD CONSTRAINT sites_seo_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.content_modules
    ADD CONSTRAINT templates_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.users_tokens
    ADD CONSTRAINT users_tokens_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.videos
    ADD CONSTRAINT videos_pkey PRIMARY KEY (id);

CREATE UNIQUE INDEX content_identifiers_entry_id_schema_index ON public.content_identifiers USING btree (entry_id, schema);

CREATE INDEX navigation_menus_key_index ON public.navigation_menus USING btree (key);

CREATE INDEX navigation_menus_language_index ON public.navigation_menus USING btree (language);

CREATE INDEX navigation_menus_status_index ON public.navigation_menus USING btree (status);

CREATE INDEX oban_beats_inserted_at_index ON public.oban_beats USING btree (inserted_at);

CREATE INDEX oban_jobs_args_index ON public.oban_jobs USING gin (args);

CREATE INDEX oban_jobs_meta_index ON public.oban_jobs USING gin (meta);

CREATE INDEX oban_jobs_queue_state_priority_scheduled_at_id_index ON public.oban_jobs USING btree (queue, state, priority, scheduled_at, id);

CREATE INDEX pagefragments_key_index ON public.pages_fragments USING btree (key);

CREATE INDEX pagefragments_language_index ON public.pages_fragments USING btree (language);

CREATE INDEX pagefragments_parent_key_index ON public.pages_fragments USING btree (parent_key);

CREATE UNIQUE INDEX pages_alternates_entry_id_linked_entry_id_index ON public.pages_alternates USING btree (entry_id, linked_entry_id);

CREATE INDEX pages_fragments_publish_at_index ON public.pages_fragments USING btree (publish_at);

CREATE INDEX pages_language_index ON public.pages USING btree (language);

CREATE INDEX pages_pages_publish_at_index ON public.pages USING btree (publish_at);

CREATE INDEX pages_pages_uri_index ON public.pages USING btree (uri);

CREATE UNIQUE INDEX pages_pages_uri_language_index ON public.pages USING btree (uri, language);

CREATE INDEX pages_parent_id_index ON public.pages USING btree (parent_id);

CREATE INDEX pages_status_index ON public.pages USING btree (status);

CREATE UNIQUE INDEX revisions_entry_type_entry_id_revision_index ON public.revisions USING btree (entry_type, entry_id, revision);

CREATE UNIQUE INDEX sites_identities_language_index ON public.sites_identities USING btree (language);

CREATE INDEX sites_previews_preview_key_index ON public.sites_previews USING btree (preview_key);

CREATE UNIQUE INDEX sites_seos_language_index ON public.sites_seos USING btree (language);

CREATE INDEX templates_namespace_index ON public.content_modules USING btree (namespace);

CREATE UNIQUE INDEX users_email_index ON public.users USING btree (email);

CREATE UNIQUE INDEX users_tokens_context_token_index ON public.users_tokens USING btree (context, token);

CREATE INDEX users_tokens_user_id_index ON public.users_tokens USING btree (user_id);

CREATE TRIGGER oban_notify AFTER INSERT ON public.oban_jobs FOR EACH ROW EXECUTE FUNCTION public.oban_jobs_notify();

ALTER TABLE ONLY public.content_palettes
    ADD CONSTRAINT content_palettes_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id);

ALTER TABLE ONLY public.content_templates
    ADD CONSTRAINT content_templates_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id);

ALTER TABLE ONLY public.files
    ADD CONSTRAINT files_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id);

ALTER TABLE ONLY public.images
    ADD CONSTRAINT images_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id);

ALTER TABLE ONLY public.images_galleries
    ADD CONSTRAINT images_galleries_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id);

ALTER TABLE ONLY public.images_gallery_images
    ADD CONSTRAINT images_gallery_images_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id);

ALTER TABLE ONLY public.images_gallery_images
    ADD CONSTRAINT images_gallery_images_gallery_id_fkey FOREIGN KEY (gallery_id) REFERENCES public.images_galleries(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.images_gallery_images
    ADD CONSTRAINT images_gallery_images_image_id_fkey FOREIGN KEY (image_id) REFERENCES public.images(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.navigation_menus
    ADD CONSTRAINT navigation_menus_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id);

ALTER TABLE ONLY public.pages_fragments
    ADD CONSTRAINT pagefragments_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id);

ALTER TABLE ONLY public.pages_fragments
    ADD CONSTRAINT pagefragments_page_id_fkey FOREIGN KEY (page_id) REFERENCES public.pages(id);

ALTER TABLE ONLY public.pages_alternates
    ADD CONSTRAINT pages_alternates_entry_id_fkey FOREIGN KEY (entry_id) REFERENCES public.pages(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.pages_alternates
    ADD CONSTRAINT pages_alternates_linked_entry_id_fkey FOREIGN KEY (linked_entry_id) REFERENCES public.pages(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.pages
    ADD CONSTRAINT pages_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id);

ALTER TABLE ONLY public.pages
    ADD CONSTRAINT pages_meta_image_id_fkey FOREIGN KEY (meta_image_id) REFERENCES public.images(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.pages
    ADD CONSTRAINT pages_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.pages(id);

ALTER TABLE ONLY public.revisions
    ADD CONSTRAINT revisions_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.sites_global_sets
    ADD CONSTRAINT sites_global_sets_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id);

ALTER TABLE ONLY public.sites_identities
    ADD CONSTRAINT sites_identities_logo_id_fkey FOREIGN KEY (logo_id) REFERENCES public.images(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.sites_previews
    ADD CONSTRAINT sites_previews_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.sites_seos
    ADD CONSTRAINT sites_seos_fallback_meta_image_id_fkey FOREIGN KEY (fallback_meta_image_id) REFERENCES public.images(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_avatar_id_fkey FOREIGN KEY (avatar_id) REFERENCES public.images(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.users_tokens
    ADD CONSTRAINT users_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.videos
    ADD CONSTRAINT videos_cover_image_id_fkey FOREIGN KEY (cover_image_id) REFERENCES public.images(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.videos
    ADD CONSTRAINT videos_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id);

