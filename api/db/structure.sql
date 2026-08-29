SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_runs (
    id bigint NOT NULL,
    firm_id bigint NOT NULL,
    client_id bigint NOT NULL,
    triggered_by_id bigint,
    period_start date NOT NULL,
    period_end date NOT NULL,
    state character varying DEFAULT 'queued'::character varying NOT NULL,
    snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    documents_count integer DEFAULT 0 NOT NULL,
    findings_count integer DEFAULT 0 NOT NULL,
    evaluation_errors jsonb DEFAULT '[]'::jsonb NOT NULL,
    started_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_runs_id_seq OWNED BY public.audit_runs.id;


--
-- Name: clients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clients (
    id bigint NOT NULL,
    firm_id bigint NOT NULL,
    cnpj character varying(14) NOT NULL,
    legal_name character varying NOT NULL,
    trade_name character varying,
    uf character varying(2) NOT NULL,
    city_code character varying(7),
    ie character varying,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: clients_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.clients_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: clients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.clients_id_seq OWNED BY public.clients.id;


--
-- Name: document_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_items (
    id bigint NOT NULL,
    document_id bigint NOT NULL,
    client_id bigint NOT NULL,
    number integer NOT NULL,
    product_code character varying,
    ncm character varying(8),
    cest character varying(7),
    cfop character varying(4),
    icms_situation_code character varying,
    pis_cst character varying(2),
    cofins_cst character varying(2),
    ipi_cst character varying(2),
    ibs_cbs_cst character varying(3),
    ibs_cbs_class_code character varying(6),
    net_amount numeric(15,2),
    icms_base_amount numeric(15,2),
    icms_amount numeric(15,2),
    icms_st_amount numeric(15,2),
    data jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: document_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.document_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: document_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.document_items_id_seq OWNED BY public.document_items.id;


--
-- Name: documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documents (
    id bigint NOT NULL,
    firm_id bigint NOT NULL,
    client_id bigint NOT NULL,
    upload_batch_id bigint,
    kind character varying NOT NULL,
    model character varying(2),
    access_key character varying(44),
    xml_hash character varying(64) NOT NULL,
    xml_ref character varying NOT NULL,
    layout_version character varying,
    schema_version integer DEFAULT 1 NOT NULL,
    role character varying,
    reference_date date,
    period character varying(7),
    issued_at timestamp(6) without time zone,
    series character varying,
    number integer,
    issuer_cnpj character varying(14),
    recipient_cnpj character varying(14),
    direction character varying,
    operation_nature character varying,
    status_state character varying,
    total_amount numeric(15,2),
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    catalog_versions jsonb DEFAULT '{}'::jsonb NOT NULL,
    target_access_key character varying(44),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: documents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.documents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: documents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.documents_id_seq OWNED BY public.documents.id;


--
-- Name: findings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.findings (
    id bigint NOT NULL,
    audit_run_id bigint NOT NULL,
    client_id bigint NOT NULL,
    rule_id bigint NOT NULL,
    rule_code character varying NOT NULL,
    rule_source character varying DEFAULT 'platform'::character varying NOT NULL,
    document_id bigint,
    item_number integer,
    fiscal_record_id bigint,
    scope character varying NOT NULL,
    severity character varying NOT NULL,
    shadow boolean DEFAULT false NOT NULL,
    message text NOT NULL,
    evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
    xml_path character varying,
    group_key character varying,
    dedupe_key character varying NOT NULL,
    state character varying DEFAULT 'open'::character varying NOT NULL,
    state_note text,
    state_changed_by_id bigint,
    state_changed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: findings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.findings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: findings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.findings_id_seq OWNED BY public.findings.id;


--
-- Name: firms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.firms (
    id bigint NOT NULL,
    name character varying NOT NULL,
    cnpj character varying(14),
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: firms_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.firms_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: firms_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.firms_id_seq OWNED BY public.firms.id;


--
-- Name: fiscal_files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fiscal_files (
    id bigint NOT NULL,
    firm_id bigint NOT NULL,
    client_id bigint NOT NULL,
    upload_batch_id bigint,
    kind character varying NOT NULL,
    layout_version character varying,
    period_start date,
    period_end date,
    purpose character varying,
    file_hash character varying(64) NOT NULL,
    storage_ref character varying NOT NULL,
    state character varying DEFAULT 'pending'::character varying NOT NULL,
    records_count integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: fiscal_files_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fiscal_files_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fiscal_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fiscal_files_id_seq OWNED BY public.fiscal_files.id;


--
-- Name: fiscal_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fiscal_records (
    id bigint NOT NULL,
    fiscal_file_id bigint NOT NULL,
    line_number integer NOT NULL,
    block character varying(1),
    record_type character varying(4) NOT NULL,
    parent_id bigint,
    document_access_key character varying(44),
    document_id bigint,
    item_number integer,
    fields jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: fiscal_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fiscal_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fiscal_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fiscal_records_id_seq OWNED BY public.fiscal_records.id;


--
-- Name: reference_row_overrides; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reference_row_overrides (
    id bigint NOT NULL,
    reference_table_id bigint NOT NULL,
    source_type character varying NOT NULL,
    source_id bigint NOT NULL,
    key character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    effective_from date NOT NULL,
    effective_until date,
    legal_basis character varying,
    justification text NOT NULL,
    created_by_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: reference_row_overrides_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reference_row_overrides_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reference_row_overrides_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reference_row_overrides_id_seq OWNED BY public.reference_row_overrides.id;


--
-- Name: reference_rows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reference_rows (
    id bigint NOT NULL,
    reference_version_id bigint NOT NULL,
    key character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    effective_from date,
    effective_until date,
    legal_basis character varying
);


--
-- Name: reference_rows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reference_rows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reference_rows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reference_rows_id_seq OWNED BY public.reference_rows.id;


--
-- Name: reference_tables; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reference_tables (
    id bigint NOT NULL,
    code character varying NOT NULL,
    name character varying NOT NULL,
    key_arity integer DEFAULT 1 NOT NULL,
    key_names jsonb DEFAULT '[]'::jsonb NOT NULL,
    row_schema jsonb DEFAULT '{}'::jsonb NOT NULL,
    source_class character varying DEFAULT 'C'::character varying NOT NULL,
    source_url character varying,
    next_review_on date,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: reference_tables_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reference_tables_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reference_tables_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reference_tables_id_seq OWNED BY public.reference_tables.id;


--
-- Name: reference_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reference_versions (
    id bigint NOT NULL,
    reference_table_id bigint NOT NULL,
    version integer NOT NULL,
    effective_from date NOT NULL,
    effective_until date,
    state character varying DEFAULT 'draft'::character varying NOT NULL,
    source_url character varying,
    source_document_ref character varying,
    notes text,
    imported_by_id bigint,
    published_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: reference_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reference_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reference_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reference_versions_id_seq OWNED BY public.reference_versions.id;


--
-- Name: rule_overrides; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rule_overrides (
    id bigint NOT NULL,
    rule_code character varying NOT NULL,
    source_type character varying NOT NULL,
    source_id bigint NOT NULL,
    action character varying NOT NULL,
    patch jsonb DEFAULT '{}'::jsonb NOT NULL,
    effective_from date NOT NULL,
    effective_until date,
    justification text NOT NULL,
    created_by_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: rule_overrides_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rule_overrides_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rule_overrides_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rule_overrides_id_seq OWNED BY public.rule_overrides.id;


--
-- Name: rule_test_cases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rule_test_cases (
    id bigint NOT NULL,
    rule_id bigint NOT NULL,
    name character varying NOT NULL,
    reference_date date NOT NULL,
    scenario jsonb DEFAULT '{}'::jsonb NOT NULL,
    input jsonb DEFAULT '{}'::jsonb NOT NULL,
    catalog jsonb DEFAULT '{}'::jsonb NOT NULL,
    expect jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_result character varying,
    last_run_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: rule_test_cases_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rule_test_cases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rule_test_cases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rule_test_cases_id_seq OWNED BY public.rule_test_cases.id;


--
-- Name: rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rules (
    id bigint NOT NULL,
    code character varying NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    dsl_version integer DEFAULT 1 NOT NULL,
    title character varying NOT NULL,
    scope character varying NOT NULL,
    effective_from date NOT NULL,
    effective_until date,
    body jsonb DEFAULT '{}'::jsonb NOT NULL,
    severity character varying DEFAULT 'error'::character varying NOT NULL,
    state character varying DEFAULT 'draft'::character varying NOT NULL,
    source_type character varying DEFAULT 'platform'::character varying NOT NULL,
    source_id bigint,
    tags character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    created_by_id bigint,
    published_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: rules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rules_id_seq OWNED BY public.rules.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: tax_scenarios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tax_scenarios (
    id bigint NOT NULL,
    client_id bigint NOT NULL,
    effective_from date NOT NULL,
    effective_until date,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    field_origins jsonb DEFAULT '{}'::jsonb NOT NULL,
    state character varying DEFAULT 'draft'::character varying NOT NULL,
    created_by_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tax_scenarios_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tax_scenarios_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tax_scenarios_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tax_scenarios_id_seq OWNED BY public.tax_scenarios.id;


--
-- Name: upload_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.upload_batches (
    id bigint NOT NULL,
    firm_id bigint NOT NULL,
    client_id bigint NOT NULL,
    user_id bigint,
    state character varying DEFAULT 'pending'::character varying NOT NULL,
    original_filename character varying,
    storage_ref character varying,
    files_total integer DEFAULT 0 NOT NULL,
    files_parsed integer DEFAULT 0 NOT NULL,
    files_failed integer DEFAULT 0 NOT NULL,
    errors_log jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: upload_batches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.upload_batches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: upload_batches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.upload_batches_id_seq OWNED BY public.upload_batches.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    firm_id bigint NOT NULL,
    email character varying NOT NULL,
    name character varying NOT NULL,
    password_digest character varying NOT NULL,
    role character varying DEFAULT 'accountant'::character varying NOT NULL,
    last_sign_in_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: audit_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_runs ALTER COLUMN id SET DEFAULT nextval('public.audit_runs_id_seq'::regclass);


--
-- Name: clients id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients ALTER COLUMN id SET DEFAULT nextval('public.clients_id_seq'::regclass);


--
-- Name: document_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_items ALTER COLUMN id SET DEFAULT nextval('public.document_items_id_seq'::regclass);


--
-- Name: documents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents ALTER COLUMN id SET DEFAULT nextval('public.documents_id_seq'::regclass);


--
-- Name: findings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.findings ALTER COLUMN id SET DEFAULT nextval('public.findings_id_seq'::regclass);


--
-- Name: firms id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.firms ALTER COLUMN id SET DEFAULT nextval('public.firms_id_seq'::regclass);


--
-- Name: fiscal_files id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_files ALTER COLUMN id SET DEFAULT nextval('public.fiscal_files_id_seq'::regclass);


--
-- Name: fiscal_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_records ALTER COLUMN id SET DEFAULT nextval('public.fiscal_records_id_seq'::regclass);


--
-- Name: reference_row_overrides id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reference_row_overrides ALTER COLUMN id SET DEFAULT nextval('public.reference_row_overrides_id_seq'::regclass);


--
-- Name: reference_rows id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reference_rows ALTER COLUMN id SET DEFAULT nextval('public.reference_rows_id_seq'::regclass);


--
-- Name: reference_tables id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reference_tables ALTER COLUMN id SET DEFAULT nextval('public.reference_tables_id_seq'::regclass);


--
-- Name: reference_versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reference_versions ALTER COLUMN id SET DEFAULT nextval('public.reference_versions_id_seq'::regclass);


--
-- Name: rule_overrides id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rule_overrides ALTER COLUMN id SET DEFAULT nextval('public.rule_overrides_id_seq'::regclass);


--
-- Name: rule_test_cases id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rule_test_cases ALTER COLUMN id SET DEFAULT nextval('public.rule_test_cases_id_seq'::regclass);


--
-- Name: rules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rules ALTER COLUMN id SET DEFAULT nextval('public.rules_id_seq'::regclass);


--
-- Name: tax_scenarios id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_scenarios ALTER COLUMN id SET DEFAULT nextval('public.tax_scenarios_id_seq'::regclass);


--
-- Name: upload_batches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.upload_batches ALTER COLUMN id SET DEFAULT nextval('public.upload_batches_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_runs audit_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_runs
    ADD CONSTRAINT audit_runs_pkey PRIMARY KEY (id);


--
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);


--
-- Name: document_items document_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_items
    ADD CONSTRAINT document_items_pkey PRIMARY KEY (id);


--
-- Name: documents documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (id);


--
-- Name: findings findings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.findings
    ADD CONSTRAINT findings_pkey PRIMARY KEY (id);


--
-- Name: firms firms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.firms
    ADD CONSTRAINT firms_pkey PRIMARY KEY (id);


--
-- Name: fiscal_files fiscal_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_files
    ADD CONSTRAINT fiscal_files_pkey PRIMARY KEY (id);


--
-- Name: fiscal_records fiscal_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_records
    ADD CONSTRAINT fiscal_records_pkey PRIMARY KEY (id);


--
-- Name: reference_row_overrides reference_row_overrides_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reference_row_overrides
    ADD CONSTRAINT reference_row_overrides_pkey PRIMARY KEY (id);


--
-- Name: reference_rows reference_rows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reference_rows
    ADD CONSTRAINT reference_rows_pkey PRIMARY KEY (id);


--
-- Name: reference_tables reference_tables_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reference_tables
    ADD CONSTRAINT reference_tables_pkey PRIMARY KEY (id);


--
-- Name: reference_versions reference_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reference_versions
    ADD CONSTRAINT reference_versions_pkey PRIMARY KEY (id);


--
-- Name: rule_overrides rule_overrides_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rule_overrides
    ADD CONSTRAINT rule_overrides_pkey PRIMARY KEY (id);


--
-- Name: rule_test_cases rule_test_cases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rule_test_cases
    ADD CONSTRAINT rule_test_cases_pkey PRIMARY KEY (id);


--
-- Name: rules rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rules
    ADD CONSTRAINT rules_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: tax_scenarios tax_scenarios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_scenarios
    ADD CONSTRAINT tax_scenarios_pkey PRIMARY KEY (id);


--
-- Name: upload_batches upload_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.upload_batches
    ADD CONSTRAINT upload_batches_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_on_client_id_issuer_cnpj_series_number_8043bff1d2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_client_id_issuer_cnpj_series_number_8043bff1d2 ON public.documents USING btree (client_id, issuer_cnpj, series, number);


--
-- Name: idx_on_reference_table_id_effective_from_c4fad7c86b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_reference_table_id_effective_from_c4fad7c86b ON public.reference_versions USING btree (reference_table_id, effective_from);


--
-- Name: idx_on_rule_code_source_type_source_id_078181d667; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_rule_code_source_type_source_id_078181d667 ON public.rule_overrides USING btree (rule_code, source_type, source_id);


--
-- Name: idx_ref_row_overrides_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ref_row_overrides_lookup ON public.reference_row_overrides USING btree (reference_table_id, source_type, source_id, key);


--
-- Name: index_audit_runs_on_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_runs_on_client_id ON public.audit_runs USING btree (client_id);


--
-- Name: index_audit_runs_on_client_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_runs_on_client_id_and_created_at ON public.audit_runs USING btree (client_id, created_at);


--
-- Name: index_audit_runs_on_firm_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_runs_on_firm_id ON public.audit_runs USING btree (firm_id);


--
-- Name: index_audit_runs_on_triggered_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_runs_on_triggered_by_id ON public.audit_runs USING btree (triggered_by_id);


--
-- Name: index_clients_on_firm_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_clients_on_firm_id ON public.clients USING btree (firm_id);


--
-- Name: index_clients_on_firm_id_and_cnpj; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_clients_on_firm_id_and_cnpj ON public.clients USING btree (firm_id, cnpj);


--
-- Name: index_document_items_on_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_document_items_on_client_id ON public.document_items USING btree (client_id);


--
-- Name: index_document_items_on_client_id_and_cfop; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_document_items_on_client_id_and_cfop ON public.document_items USING btree (client_id, cfop);


--
-- Name: index_document_items_on_client_id_and_ncm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_document_items_on_client_id_and_ncm ON public.document_items USING btree (client_id, ncm);


--
-- Name: index_document_items_on_document_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_document_items_on_document_id ON public.document_items USING btree (document_id);


--
-- Name: index_document_items_on_document_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_document_items_on_document_id_and_number ON public.document_items USING btree (document_id, number);


--
-- Name: index_documents_on_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_client_id ON public.documents USING btree (client_id);


--
-- Name: index_documents_on_client_id_and_access_key_and_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_documents_on_client_id_and_access_key_and_kind ON public.documents USING btree (client_id, access_key, kind) WHERE (access_key IS NOT NULL);


--
-- Name: index_documents_on_client_id_and_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_client_id_and_period ON public.documents USING btree (client_id, period);


--
-- Name: index_documents_on_client_id_and_reference_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_client_id_and_reference_date ON public.documents USING btree (client_id, reference_date);


--
-- Name: index_documents_on_client_id_and_xml_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_documents_on_client_id_and_xml_hash ON public.documents USING btree (client_id, xml_hash);


--
-- Name: index_documents_on_firm_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_firm_id ON public.documents USING btree (firm_id);


--
-- Name: index_documents_on_target_access_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_target_access_key ON public.documents USING btree (target_access_key);


--
-- Name: index_documents_on_upload_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_upload_batch_id ON public.documents USING btree (upload_batch_id);


--
-- Name: index_findings_on_audit_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_findings_on_audit_run_id ON public.findings USING btree (audit_run_id);


--
-- Name: index_findings_on_audit_run_id_and_dedupe_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_findings_on_audit_run_id_and_dedupe_key ON public.findings USING btree (audit_run_id, dedupe_key);


--
-- Name: index_findings_on_audit_run_id_and_rule_code_and_group_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_findings_on_audit_run_id_and_rule_code_and_group_key ON public.findings USING btree (audit_run_id, rule_code, group_key);


--
-- Name: index_findings_on_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_findings_on_client_id ON public.findings USING btree (client_id);


--
-- Name: index_findings_on_client_id_and_dedupe_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_findings_on_client_id_and_dedupe_key ON public.findings USING btree (client_id, dedupe_key);


--
-- Name: index_findings_on_document_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_findings_on_document_id ON public.findings USING btree (document_id);


--
-- Name: index_findings_on_document_id_and_item_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_findings_on_document_id_and_item_number ON public.findings USING btree (document_id, item_number);


--
-- Name: index_findings_on_fiscal_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_findings_on_fiscal_record_id ON public.findings USING btree (fiscal_record_id);


--
-- Name: index_findings_on_rule_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_findings_on_rule_id ON public.findings USING btree (rule_id);


--
-- Name: index_findings_on_state_changed_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_findings_on_state_changed_by_id ON public.findings USING btree (state_changed_by_id);


--
-- Name: index_fiscal_files_on_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fiscal_files_on_client_id ON public.fiscal_files USING btree (client_id);


--
-- Name: index_fiscal_files_on_client_id_and_file_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_fiscal_files_on_client_id_and_file_hash ON public.fiscal_files USING btree (client_id, file_hash);


--
-- Name: index_fiscal_files_on_firm_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fiscal_files_on_firm_id ON public.fiscal_files USING btree (firm_id);


--
-- Name: index_fiscal_files_on_upload_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fiscal_files_on_upload_batch_id ON public.fiscal_files USING btree (upload_batch_id);


--
-- Name: index_fiscal_records_on_document_access_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fiscal_records_on_document_access_key ON public.fiscal_records USING btree (document_access_key);


--
-- Name: index_fiscal_records_on_document_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fiscal_records_on_document_id ON public.fiscal_records USING btree (document_id);


--
-- Name: index_fiscal_records_on_fiscal_file_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fiscal_records_on_fiscal_file_id ON public.fiscal_records USING btree (fiscal_file_id);


--
-- Name: index_fiscal_records_on_fiscal_file_id_and_record_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fiscal_records_on_fiscal_file_id_and_record_type ON public.fiscal_records USING btree (fiscal_file_id, record_type);


--
-- Name: index_reference_row_overrides_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reference_row_overrides_on_created_by_id ON public.reference_row_overrides USING btree (created_by_id);


--
-- Name: index_reference_row_overrides_on_reference_table_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reference_row_overrides_on_reference_table_id ON public.reference_row_overrides USING btree (reference_table_id);


--
-- Name: index_reference_rows_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reference_rows_on_key ON public.reference_rows USING gin (key);


--
-- Name: index_reference_rows_on_reference_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reference_rows_on_reference_version_id ON public.reference_rows USING btree (reference_version_id);


--
-- Name: index_reference_rows_on_reference_version_id_and_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reference_rows_on_reference_version_id_and_key ON public.reference_rows USING btree (reference_version_id, key);


--
-- Name: index_reference_tables_on_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_reference_tables_on_code ON public.reference_tables USING btree (code);


--
-- Name: index_reference_versions_on_imported_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reference_versions_on_imported_by_id ON public.reference_versions USING btree (imported_by_id);


--
-- Name: index_reference_versions_on_reference_table_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reference_versions_on_reference_table_id ON public.reference_versions USING btree (reference_table_id);


--
-- Name: index_reference_versions_on_reference_table_id_and_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_reference_versions_on_reference_table_id_and_version ON public.reference_versions USING btree (reference_table_id, version);


--
-- Name: index_rule_overrides_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rule_overrides_on_created_by_id ON public.rule_overrides USING btree (created_by_id);


--
-- Name: index_rule_test_cases_on_rule_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rule_test_cases_on_rule_id ON public.rule_test_cases USING btree (rule_id);


--
-- Name: index_rules_on_code_and_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_rules_on_code_and_version ON public.rules USING btree (code, version);


--
-- Name: index_rules_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rules_on_created_by_id ON public.rules USING btree (created_by_id);


--
-- Name: index_rules_on_state_and_effective_from; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rules_on_state_and_effective_from ON public.rules USING btree (state, effective_from);


--
-- Name: index_rules_on_tags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rules_on_tags ON public.rules USING gin (tags);


--
-- Name: index_tax_scenarios_on_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tax_scenarios_on_client_id ON public.tax_scenarios USING btree (client_id);


--
-- Name: index_tax_scenarios_on_client_id_and_effective_from; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tax_scenarios_on_client_id_and_effective_from ON public.tax_scenarios USING btree (client_id, effective_from);


--
-- Name: index_tax_scenarios_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tax_scenarios_on_created_by_id ON public.tax_scenarios USING btree (created_by_id);


--
-- Name: index_upload_batches_on_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_upload_batches_on_client_id ON public.upload_batches USING btree (client_id);


--
-- Name: index_upload_batches_on_firm_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_upload_batches_on_firm_id ON public.upload_batches USING btree (firm_id);


--
-- Name: index_upload_batches_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_upload_batches_on_user_id ON public.upload_batches USING btree (user_id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_firm_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_firm_id ON public.users USING btree (firm_id);


--
-- Name: reference_rows fk_rails_0265acdb17; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reference_rows
    ADD CONSTRAINT fk_rails_0265acdb17 FOREIGN KEY (reference_version_id) REFERENCES public.reference_versions(id);


--
-- Name: findings fk_rails_097806fb9f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.findings
    ADD CONSTRAINT fk_rails_097806fb9f FOREIGN KEY (state_changed_by_id) REFERENCES public.users(id);


--
-- Name: audit_runs fk_rails_0e3acb90a4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_runs
    ADD CONSTRAINT fk_rails_0e3acb90a4 FOREIGN KEY (triggered_by_id) REFERENCES public.users(id);


--
-- Name: reference_versions fk_rails_140ddcf304; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reference_versions
    ADD CONSTRAINT fk_rails_140ddcf304 FOREIGN KEY (reference_table_id) REFERENCES public.reference_tables(id);


--
-- Name: reference_row_overrides fk_rails_140e90c645; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reference_row_overrides
    ADD CONSTRAINT fk_rails_140e90c645 FOREIGN KEY (reference_table_id) REFERENCES public.reference_tables(id);


--
-- Name: findings fk_rails_1a20d0aacc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.findings
    ADD CONSTRAINT fk_rails_1a20d0aacc FOREIGN KEY (audit_run_id) REFERENCES public.audit_runs(id);


--
-- Name: tax_scenarios fk_rails_1d21d0c2f5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_scenarios
    ADD CONSTRAINT fk_rails_1d21d0c2f5 FOREIGN KEY (client_id) REFERENCES public.clients(id);


--
-- Name: document_items fk_rails_25c6116f60; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_items
    ADD CONSTRAINT fk_rails_25c6116f60 FOREIGN KEY (document_id) REFERENCES public.documents(id);


--
-- Name: document_items fk_rails_25d47f8feb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_items
    ADD CONSTRAINT fk_rails_25d47f8feb FOREIGN KEY (client_id) REFERENCES public.clients(id);


--
-- Name: fiscal_files fk_rails_26e5efeb30; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_files
    ADD CONSTRAINT fk_rails_26e5efeb30 FOREIGN KEY (client_id) REFERENCES public.clients(id);


--
-- Name: documents fk_rails_2faf9571d0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT fk_rails_2faf9571d0 FOREIGN KEY (client_id) REFERENCES public.clients(id);


--
-- Name: audit_runs fk_rails_3a26808e74; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_runs
    ADD CONSTRAINT fk_rails_3a26808e74 FOREIGN KEY (firm_id) REFERENCES public.firms(id);


--
-- Name: audit_runs fk_rails_60b040dbde; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_runs
    ADD CONSTRAINT fk_rails_60b040dbde FOREIGN KEY (client_id) REFERENCES public.clients(id);


--
-- Name: rule_test_cases fk_rails_6d6a3d1e0b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rule_test_cases
    ADD CONSTRAINT fk_rails_6d6a3d1e0b FOREIGN KEY (rule_id) REFERENCES public.rules(id);


--
-- Name: upload_batches fk_rails_7001540c7a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.upload_batches
    ADD CONSTRAINT fk_rails_7001540c7a FOREIGN KEY (firm_id) REFERENCES public.firms(id);


--
-- Name: fiscal_files fk_rails_78df392b03; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_files
    ADD CONSTRAINT fk_rails_78df392b03 FOREIGN KEY (upload_batch_id) REFERENCES public.upload_batches(id);


--
-- Name: rules fk_rails_813295603b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rules
    ADD CONSTRAINT fk_rails_813295603b FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: upload_batches fk_rails_8484b6b71c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.upload_batches
    ADD CONSTRAINT fk_rails_8484b6b71c FOREIGN KEY (client_id) REFERENCES public.clients(id);


--
-- Name: documents fk_rails_8d4923cd3f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT fk_rails_8d4923cd3f FOREIGN KEY (upload_batch_id) REFERENCES public.upload_batches(id);


--
-- Name: findings fk_rails_9c6f63c93b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.findings
    ADD CONSTRAINT fk_rails_9c6f63c93b FOREIGN KEY (rule_id) REFERENCES public.rules(id);


--
-- Name: documents fk_rails_b24638c37f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT fk_rails_b24638c37f FOREIGN KEY (firm_id) REFERENCES public.firms(id);


--
-- Name: reference_row_overrides fk_rails_b5ccc3c96d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reference_row_overrides
    ADD CONSTRAINT fk_rails_b5ccc3c96d FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: findings fk_rails_b92881a2b1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.findings
    ADD CONSTRAINT fk_rails_b92881a2b1 FOREIGN KEY (document_id) REFERENCES public.documents(id);


--
-- Name: fiscal_files fk_rails_bd149c2296; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_files
    ADD CONSTRAINT fk_rails_bd149c2296 FOREIGN KEY (firm_id) REFERENCES public.firms(id);


--
-- Name: upload_batches fk_rails_bfb2c1c2f7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.upload_batches
    ADD CONSTRAINT fk_rails_bfb2c1c2f7 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: reference_versions fk_rails_c1eeb865d4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reference_versions
    ADD CONSTRAINT fk_rails_c1eeb865d4 FOREIGN KEY (imported_by_id) REFERENCES public.users(id);


--
-- Name: rule_overrides fk_rails_ce6c46ef1d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rule_overrides
    ADD CONSTRAINT fk_rails_ce6c46ef1d FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: fiscal_records fk_rails_d38feb010b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_records
    ADD CONSTRAINT fk_rails_d38feb010b FOREIGN KEY (document_id) REFERENCES public.documents(id);


--
-- Name: clients fk_rails_d523389f10; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT fk_rails_d523389f10 FOREIGN KEY (firm_id) REFERENCES public.firms(id);


--
-- Name: fiscal_records fk_rails_d63918ef58; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_records
    ADD CONSTRAINT fk_rails_d63918ef58 FOREIGN KEY (fiscal_file_id) REFERENCES public.fiscal_files(id);


--
-- Name: findings fk_rails_efe0ad3698; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.findings
    ADD CONSTRAINT fk_rails_efe0ad3698 FOREIGN KEY (fiscal_record_id) REFERENCES public.fiscal_records(id);


--
-- Name: users fk_rails_f3b0620a22; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_rails_f3b0620a22 FOREIGN KEY (firm_id) REFERENCES public.firms(id);


--
-- Name: tax_scenarios fk_rails_f5be2248c4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_scenarios
    ADD CONSTRAINT fk_rails_f5be2248c4 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: findings fk_rails_f8ac0b4cfc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.findings
    ADD CONSTRAINT fk_rails_f8ac0b4cfc FOREIGN KEY (client_id) REFERENCES public.clients(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260829000001');

