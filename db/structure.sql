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
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


--
-- Name: audit_logs_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_logs_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'audit_logs é somente inserção';
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    blob_id uuid NOT NULL,
    record_id uuid NOT NULL
);


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    variation_digest character varying NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    blob_id uuid NOT NULL
);


--
-- Name: activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activities (
    subject_type character varying,
    area character varying NOT NULL,
    action character varying NOT NULL,
    description character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid,
    user_id uuid,
    subject_id uuid
);


--
-- Name: apps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.apps (
    name character varying NOT NULL,
    description text,
    environment character varying DEFAULT 'production'::character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    url character varying,
    tech_stack character varying,
    repository_url character varying,
    hosting_type character varying,
    vault_reference character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    contract_id uuid,
    user_id uuid,
    project_id uuid,
    hosting_id uuid
);


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
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    action character varying NOT NULL,
    area character varying NOT NULL,
    auditable_type character varying,
    auditable_label character varying,
    changeset jsonb DEFAULT '{}'::jsonb NOT NULL,
    ip_address character varying,
    created_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    auditable_id uuid
);


--
-- Name: companies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.companies (
    legal_name character varying NOT NULL,
    trade_name character varying NOT NULL,
    cnpj character varying NOT NULL,
    status character varying DEFAULT 'prospect'::character varying NOT NULL,
    phone character varying,
    email character varying,
    website character varying,
    street character varying,
    city character varying,
    state character varying(2),
    zip_code character varying,
    notes text,
    customer_since date,
    external_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contacts (
    name character varying NOT NULL,
    "position" character varying,
    phone character varying,
    whatsapp character varying,
    email character varying,
    "primary" boolean DEFAULT false NOT NULL,
    notes text,
    external_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    whatsapp_digits character varying GENERATED ALWAYS AS (NULLIF(regexp_replace((whatsapp)::text, '\D'::text, ''::text, 'g'::text), ''::text)) STORED,
    phone_digits character varying GENERATED ALWAYS AS (NULLIF(regexp_replace((phone)::text, '\D'::text, ''::text, 'g'::text), ''::text)) STORED
);


--
-- Name: contract_numbers; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contract_numbers
    START WITH 100
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contracts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contracts (
    number integer DEFAULT nextval('public.contract_numbers'::regclass) NOT NULL,
    title character varying NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    renewal character varying DEFAULT 'manual'::character varying NOT NULL,
    value_cents integer DEFAULT 0 NOT NULL,
    periodicity character varying DEFAULT 'monthly'::character varying NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL
);


--
-- Name: customer_services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_services (
    price_cents integer NOT NULL,
    recurrence character varying DEFAULT 'monthly'::character varying NOT NULL,
    mrr_cents integer DEFAULT 0 NOT NULL,
    start_date date NOT NULL,
    due_day integer,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    ended_on date,
    description character varying,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    service_id uuid NOT NULL,
    contract_id uuid,
    company_id uuid NOT NULL
);


--
-- Name: databases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.databases (
    technology character varying NOT NULL,
    version character varying,
    environment character varying DEFAULT 'production'::character varying NOT NULL,
    provider character varying,
    backup_policy character varying,
    vault_reference character varying,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    app_id uuid NOT NULL
);


--
-- Name: documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documents (
    title character varying NOT NULL,
    kind character varying NOT NULL,
    documentable_type character varying,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid,
    uploaded_by_id uuid NOT NULL,
    documentable_id uuid
);


--
-- Name: domains; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domains (
    name character varying NOT NULL,
    registrar character varying NOT NULL,
    registered_on date,
    expires_on date NOT NULL,
    auto_renew boolean DEFAULT false NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    renewal_cost_cents integer DEFAULT 0 NOT NULL,
    paid_by character varying DEFAULT 'client'::character varying NOT NULL,
    dns_provider character varying,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL
);


--
-- Name: exchange_rates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exchange_rates (
    currency character varying NOT NULL,
    quoted_on date NOT NULL,
    rate numeric(12,6) NOT NULL,
    source character varying DEFAULT 'ptax'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: external_services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.external_services (
    name character varying NOT NULL,
    plan character varying,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    cost_cents integer DEFAULT 0 NOT NULL,
    periodicity character varying DEFAULT 'monthly'::character varying NOT NULL,
    paid_by character varying DEFAULT 'devbatista'::character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    vault_reference character varying,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    app_id uuid,
    company_id uuid NOT NULL,
    supplier_id uuid NOT NULL
);


--
-- Name: integrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integrations (
    platform character varying NOT NULL,
    variant character varying,
    environment character varying DEFAULT 'production'::character varying NOT NULL,
    status character varying DEFAULT 'configuring'::character varying NOT NULL,
    purpose character varying NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    app_id uuid NOT NULL
);


--
-- Name: interactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.interactions (
    subject_type character varying NOT NULL,
    kind character varying NOT NULL,
    occurred_on date NOT NULL,
    notes text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    whatsapp_conversation_id uuid
);


--
-- Name: invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoices (
    number character varying,
    competence date NOT NULL,
    amount_cents integer NOT NULL,
    issued_on date,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    description character varying,
    url character varying,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL
);


--
-- Name: leads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leads (
    name character varying NOT NULL,
    company_name character varying,
    phone character varying,
    whatsapp character varying,
    email character varying,
    origin character varying NOT NULL,
    status character varying DEFAULT 'new'::character varying NOT NULL,
    entered_on date NOT NULL,
    notes text,
    next_step character varying,
    next_step_on date,
    lost_reason character varying,
    lost_details text,
    lost_at timestamp(6) without time zone,
    converted_at timestamp(6) without time zone,
    external_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    service_id uuid,
    company_id uuid,
    whatsapp_digits character varying GENERATED ALWAYS AS (NULLIF(regexp_replace((whatsapp)::text, '\D'::text, ''::text, 'g'::text), ''::text)) STORED,
    phone_digits character varying GENERATED ALWAYS AS (NULLIF(regexp_replace((phone)::text, '\D'::text, ''::text, 'g'::text), ''::text)) STORED
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    kind character varying NOT NULL,
    level character varying DEFAULT 'info'::character varying NOT NULL,
    title character varying NOT NULL,
    area character varying NOT NULL,
    path character varying,
    notifiable_type character varying,
    dedup_key character varying,
    read_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    notifiable_id uuid
);


--
-- Name: oauth_access_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_access_grants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    resource_owner_id uuid NOT NULL,
    application_id uuid NOT NULL,
    token character varying NOT NULL,
    expires_in integer NOT NULL,
    redirect_uri text NOT NULL,
    scopes character varying DEFAULT ''::character varying NOT NULL,
    code_challenge character varying,
    code_challenge_method character varying,
    created_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone
);


--
-- Name: oauth_access_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_access_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    resource_owner_id uuid,
    application_id uuid NOT NULL,
    token character varying NOT NULL,
    refresh_token character varying,
    expires_in integer,
    scopes character varying,
    created_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone,
    previous_refresh_token character varying DEFAULT ''::character varying NOT NULL
);


--
-- Name: oauth_applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_applications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    uid character varying NOT NULL,
    secret character varying NOT NULL,
    redirect_uri text NOT NULL,
    scopes character varying DEFAULT ''::character varying NOT NULL,
    confidential boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: opportunities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.opportunities (
    title character varying NOT NULL,
    stage character varying DEFAULT 'meeting'::character varying NOT NULL,
    estimated_value_cents integer DEFAULT 0 NOT NULL,
    probability integer DEFAULT 25 NOT NULL,
    expected_close_on date,
    notes text,
    next_step character varying,
    next_step_on date,
    lost_reason character varying,
    lost_details text,
    closed_on date,
    external_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    service_id uuid,
    lead_id uuid,
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    CONSTRAINT opportunities_probability_range CHECK (((probability >= 0) AND (probability <= 100)))
);


--
-- Name: payables; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payables (
    cost_center character varying,
    description character varying NOT NULL,
    category character varying NOT NULL,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    original_amount_cents integer,
    exchange_rate numeric(12,6),
    amount_cents integer NOT NULL,
    competence date NOT NULL,
    due_on date NOT NULL,
    paid_on date,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    recurring_expense_id uuid,
    external_service_id uuid,
    supplier_id uuid NOT NULL,
    company_id uuid,
    CONSTRAINT payables_amount_positive CHECK ((amount_cents >= 0)),
    CONSTRAINT payables_cost_center_present CHECK (((company_id IS NOT NULL) OR (cost_center IS NOT NULL)))
);


--
-- Name: product_costs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_costs (
    month date NOT NULL,
    amount_cents integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    product_id uuid NOT NULL
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    name character varying NOT NULL,
    url character varying,
    description text,
    status character varying DEFAULT 'idea'::character varying NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.projects (
    name character varying NOT NULL,
    description text,
    status character varying DEFAULT 'planning'::character varying NOT NULL,
    start_date date,
    due_date date NOT NULL,
    closed_on date,
    budget_cents integer DEFAULT 0 NOT NULL,
    progress integer DEFAULT 0 NOT NULL,
    progress_from_tasks boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    contract_id uuid,
    company_id uuid NOT NULL,
    proposal_id uuid,
    user_id uuid NOT NULL,
    CONSTRAINT projects_progress_range CHECK (((progress >= 0) AND (progress <= 100)))
);


--
-- Name: proposal_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proposal_items (
    description character varying,
    recurrence character varying DEFAULT 'monthly'::character varying NOT NULL,
    default_price_cents integer DEFAULT 0 NOT NULL,
    price_cents integer DEFAULT 0 NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    proposal_id uuid NOT NULL,
    service_id uuid NOT NULL
);


--
-- Name: proposals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proposals (
    year integer NOT NULL,
    number integer NOT NULL,
    title character varying NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    description text,
    payment_terms character varying,
    delivery_terms character varying,
    valid_until date NOT NULL,
    notes text,
    total_cents integer DEFAULT 0 NOT NULL,
    sent_at timestamp(6) without time zone,
    viewed_at timestamp(6) without time zone,
    decided_on date,
    rejection_reason character varying,
    rejection_details text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    contact_id uuid,
    lead_id uuid,
    contract_id uuid,
    company_id uuid,
    opportunity_id uuid,
    CONSTRAINT proposals_recipient_present CHECK (((company_id IS NOT NULL) OR (lead_id IS NOT NULL)))
);


--
-- Name: receivables; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receivables (
    description character varying NOT NULL,
    category character varying NOT NULL,
    amount_cents integer NOT NULL,
    competence date NOT NULL,
    due_on date NOT NULL,
    paid_on date,
    paid_amount_cents integer,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    service_id uuid,
    invoice_id uuid,
    customer_service_id uuid,
    contract_id uuid,
    company_id uuid NOT NULL,
    contact_id uuid,
    CONSTRAINT receivables_amount_positive CHECK ((amount_cents >= 0))
);


--
-- Name: recurrence_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recurrence_runs (
    run_on date NOT NULL,
    started_at timestamp(6) without time zone NOT NULL,
    finished_at timestamp(6) without time zone,
    generated_count integer DEFAULT 0 NOT NULL,
    overdue_count integer DEFAULT 0 NOT NULL,
    cancelled_count integer DEFAULT 0 NOT NULL,
    horizon_on date,
    warnings text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid
);


--
-- Name: recurring_expenses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recurring_expenses (
    description character varying NOT NULL,
    category character varying NOT NULL,
    cost_center character varying,
    currency character varying DEFAULT 'BRL'::character varying NOT NULL,
    amount_cents integer NOT NULL,
    periodicity character varying DEFAULT 'monthly'::character varying NOT NULL,
    due_day integer NOT NULL,
    start_on date NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    ended_on date,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    supplier_id uuid NOT NULL,
    external_service_id uuid,
    company_id uuid,
    CONSTRAINT recurring_expenses_cost_center_present CHECK (((company_id IS NOT NULL) OR (cost_center IS NOT NULL)))
);


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    name character varying NOT NULL,
    key character varying NOT NULL,
    permissions jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: servers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.servers (
    name character varying NOT NULL,
    host character varying NOT NULL,
    environment character varying DEFAULT 'production'::character varying NOT NULL,
    os character varying,
    instance_type character varying,
    monthly_cost_cents integer DEFAULT 0 NOT NULL,
    vault_reference character varying,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    supplier_id uuid NOT NULL,
    company_id uuid NOT NULL
);


--
-- Name: services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.services (
    name character varying NOT NULL,
    description text,
    category character varying NOT NULL,
    kind character varying NOT NULL,
    default_price_cents integer DEFAULT 0 NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settings (
    key character varying NOT NULL,
    value jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions (
    subscriber_name character varying NOT NULL,
    email character varying,
    plan character varying NOT NULL,
    monthly_value_cents integer DEFAULT 0 NOT NULL,
    started_on date NOT NULL,
    trial_ends_on date,
    cancelled_on date,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid,
    product_id uuid NOT NULL
);


--
-- Name: suppliers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.suppliers (
    name character varying NOT NULL,
    category character varying NOT NULL,
    contact_name character varying,
    phone character varying,
    email character varying,
    website character varying,
    notes text,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasks (
    title character varying NOT NULL,
    description text,
    status character varying DEFAULT 'backlog'::character varying NOT NULL,
    priority character varying DEFAULT 'normal'::character varying NOT NULL,
    due_on date,
    estimated_minutes integer,
    completed_on date,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id uuid NOT NULL,
    user_id uuid
);


--
-- Name: ticket_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ticket_messages (
    kind character varying DEFAULT 'reply'::character varying NOT NULL,
    channel character varying,
    body text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ticket_id uuid NOT NULL,
    contact_id uuid,
    user_id uuid NOT NULL
);


--
-- Name: ticket_numbers; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ticket_numbers
    START WITH 1000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tickets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tickets (
    number integer DEFAULT nextval('public.ticket_numbers'::regclass) NOT NULL,
    subject character varying NOT NULL,
    description text NOT NULL,
    category character varying NOT NULL,
    priority character varying DEFAULT 'normal'::character varying NOT NULL,
    status character varying DEFAULT 'open'::character varying NOT NULL,
    opened_at timestamp(6) without time zone NOT NULL,
    resolved_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    app_id uuid,
    company_id uuid NOT NULL,
    contact_id uuid
);


--
-- Name: time_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.time_entries (
    worked_on date NOT NULL,
    minutes integer NOT NULL,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    task_id uuid,
    company_id uuid NOT NULL,
    user_id uuid NOT NULL,
    project_id uuid,
    ticket_id uuid,
    CONSTRAINT time_entries_minutes_positive CHECK ((minutes > 0))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    name character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    hourly_cost_cents integer,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp(6) without time zone,
    sign_in_count integer DEFAULT 0 NOT NULL,
    current_sign_in_at timestamp(6) without time zone,
    last_sign_in_at timestamp(6) without time zone,
    current_sign_in_ip character varying,
    last_sign_in_ip character varying,
    failed_attempts integer DEFAULT 0 NOT NULL,
    locked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    email_preferences jsonb DEFAULT '{}'::jsonb NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    role_id uuid NOT NULL
);


--
-- Name: whatsapp_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id character varying,
    waba_id character varying NOT NULL,
    phone_number_id character varying NOT NULL,
    display_phone_number character varying,
    verified_name character varying,
    access_token text,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    coexistence boolean DEFAULT false NOT NULL,
    quality_rating character varying DEFAULT 'unknown'::character varying NOT NULL,
    messaging_limit_tier character varying,
    connected_by_id uuid,
    connected_at timestamp(6) without time zone,
    subscribed_at timestamp(6) without time zone,
    disconnected_at timestamp(6) without time zone,
    disconnect_reason character varying,
    contacts_sync_request_id character varying,
    contacts_synced_at timestamp(6) without time zone,
    history_sync_request_id character varying,
    history_sync_progress integer,
    history_synced_at timestamp(6) without time zone,
    history_sync_error character varying,
    last_webhook_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    token_expires_at timestamp(6) without time zone,
    activation_error character varying,
    registered_at timestamp(6) without time zone,
    templates_sync_requested_at timestamp(6) without time zone,
    templates_synced_at timestamp(6) without time zone,
    templates_sync_error character varying
);


--
-- Name: whatsapp_conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    whatsapp_account_id uuid NOT NULL,
    bsuid character varying,
    parent_bsuid character varying,
    wa_id character varying,
    username character varying,
    profile_name character varying,
    lead_id uuid,
    contact_id uuid,
    last_inbound_at timestamp(6) without time zone,
    last_message_at timestamp(6) without time zone,
    unread_count integer DEFAULT 0 NOT NULL,
    preview character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    saved_name character varying,
    linked_at timestamp(6) without time zone,
    auto_link_blocked_at timestamp(6) without time zone,
    linked_by_id uuid,
    CONSTRAINT whatsapp_conversations_identified CHECK (((bsuid IS NOT NULL) OR (wa_id IS NOT NULL))),
    CONSTRAINT whatsapp_conversations_single_link CHECK (((lead_id IS NULL) OR (contact_id IS NULL)))
);


--
-- Name: whatsapp_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    whatsapp_conversation_id uuid NOT NULL,
    direction character varying NOT NULL,
    kind character varying DEFAULT 'text'::character varying NOT NULL,
    origin character varying NOT NULL,
    body text,
    wa_message_id character varying,
    status character varying NOT NULL,
    error_code character varying,
    error_message text,
    template_name character varying,
    template_language character varying,
    template_params jsonb DEFAULT '[]'::jsonb NOT NULL,
    media_id character varying,
    media_mime_type character varying,
    media_filename character varying,
    reply_to_wa_message_id character varying,
    reaction_to_wa_message_id character varying,
    reaction_emoji character varying,
    user_id uuid,
    from_history boolean DEFAULT false NOT NULL,
    sent_at timestamp(6) without time zone NOT NULL,
    delivered_at timestamp(6) without time zone,
    read_at timestamp(6) without time zone,
    raw_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    edited_at timestamp(6) without time zone,
    revoked_at timestamp(6) without time zone
);


--
-- Name: whatsapp_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    whatsapp_account_id uuid NOT NULL,
    meta_template_id character varying,
    name character varying NOT NULL,
    language character varying NOT NULL,
    category character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    components jsonb DEFAULT '[]'::jsonb NOT NULL,
    variables_count integer DEFAULT 0 NOT NULL,
    rejection_reason character varying,
    last_synced_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: activities activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT activities_pkey PRIMARY KEY (id);


--
-- Name: apps apps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apps
    ADD CONSTRAINT apps_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: contacts contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_pkey PRIMARY KEY (id);


--
-- Name: contracts contracts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_pkey PRIMARY KEY (id);


--
-- Name: customer_services customer_services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_services
    ADD CONSTRAINT customer_services_pkey PRIMARY KEY (id);


--
-- Name: databases databases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.databases
    ADD CONSTRAINT databases_pkey PRIMARY KEY (id);


--
-- Name: documents documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (id);


--
-- Name: domains domains_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domains
    ADD CONSTRAINT domains_pkey PRIMARY KEY (id);


--
-- Name: exchange_rates exchange_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_rates
    ADD CONSTRAINT exchange_rates_pkey PRIMARY KEY (id);


--
-- Name: external_services external_services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.external_services
    ADD CONSTRAINT external_services_pkey PRIMARY KEY (id);


--
-- Name: integrations integrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integrations
    ADD CONSTRAINT integrations_pkey PRIMARY KEY (id);


--
-- Name: interactions interactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.interactions
    ADD CONSTRAINT interactions_pkey PRIMARY KEY (id);


--
-- Name: invoices invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (id);


--
-- Name: leads leads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: oauth_access_grants oauth_access_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_grants
    ADD CONSTRAINT oauth_access_grants_pkey PRIMARY KEY (id);


--
-- Name: oauth_access_tokens oauth_access_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT oauth_access_tokens_pkey PRIMARY KEY (id);


--
-- Name: oauth_applications oauth_applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_applications
    ADD CONSTRAINT oauth_applications_pkey PRIMARY KEY (id);


--
-- Name: opportunities opportunities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT opportunities_pkey PRIMARY KEY (id);


--
-- Name: payables payables_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payables
    ADD CONSTRAINT payables_pkey PRIMARY KEY (id);


--
-- Name: product_costs product_costs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_costs
    ADD CONSTRAINT product_costs_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: proposal_items proposal_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proposal_items
    ADD CONSTRAINT proposal_items_pkey PRIMARY KEY (id);


--
-- Name: proposals proposals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proposals
    ADD CONSTRAINT proposals_pkey PRIMARY KEY (id);


--
-- Name: receivables receivables_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT receivables_pkey PRIMARY KEY (id);


--
-- Name: recurrence_runs recurrence_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurrence_runs
    ADD CONSTRAINT recurrence_runs_pkey PRIMARY KEY (id);


--
-- Name: recurring_expenses recurring_expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_expenses
    ADD CONSTRAINT recurring_expenses_pkey PRIMARY KEY (id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: servers servers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.servers
    ADD CONSTRAINT servers_pkey PRIMARY KEY (id);


--
-- Name: services services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT services_pkey PRIMARY KEY (id);


--
-- Name: settings settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT settings_pkey PRIMARY KEY (id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);


--
-- Name: tasks tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (id);


--
-- Name: ticket_messages ticket_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_messages
    ADD CONSTRAINT ticket_messages_pkey PRIMARY KEY (id);


--
-- Name: tickets tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_pkey PRIMARY KEY (id);


--
-- Name: time_entries time_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT time_entries_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_accounts whatsapp_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_accounts
    ADD CONSTRAINT whatsapp_accounts_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_conversations whatsapp_conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_conversations
    ADD CONSTRAINT whatsapp_conversations_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_messages whatsapp_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_messages
    ADD CONSTRAINT whatsapp_messages_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_templates whatsapp_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_templates
    ADD CONSTRAINT whatsapp_templates_pkey PRIMARY KEY (id);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_activities_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_company_id ON public.activities USING btree (company_id);


--
-- Name: index_activities_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_created_at ON public.activities USING btree (created_at);


--
-- Name: index_activities_on_subject_type_and_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_subject_type_and_subject_id ON public.activities USING btree (subject_type, subject_id);


--
-- Name: index_activities_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_user_id ON public.activities USING btree (user_id);


--
-- Name: index_apps_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_apps_on_company_id ON public.apps USING btree (company_id);


--
-- Name: index_apps_on_contract_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_apps_on_contract_id ON public.apps USING btree (contract_id);


--
-- Name: index_apps_on_hosting_type_and_hosting_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_apps_on_hosting_type_and_hosting_id ON public.apps USING btree (hosting_type, hosting_id);


--
-- Name: index_apps_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_apps_on_project_id ON public.apps USING btree (project_id);


--
-- Name: index_apps_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_apps_on_status ON public.apps USING btree (status);


--
-- Name: index_apps_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_apps_on_user_id ON public.apps USING btree (user_id);


--
-- Name: index_audit_logs_on_area_and_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_area_and_action ON public.audit_logs USING btree (area, action);


--
-- Name: index_audit_logs_on_auditable_type_and_auditable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_auditable_type_and_auditable_id ON public.audit_logs USING btree (auditable_type, auditable_id);


--
-- Name: index_audit_logs_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_created_at ON public.audit_logs USING btree (created_at);


--
-- Name: index_audit_logs_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_user_id ON public.audit_logs USING btree (user_id);


--
-- Name: index_companies_on_cnpj; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_companies_on_cnpj ON public.companies USING btree (cnpj);


--
-- Name: index_companies_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_companies_on_external_id ON public.companies USING btree (external_id) WHERE (external_id IS NOT NULL);


--
-- Name: index_companies_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_companies_on_status ON public.companies USING btree (status);


--
-- Name: index_companies_on_trade_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_companies_on_trade_name ON public.companies USING btree (trade_name);


--
-- Name: index_contacts_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contacts_on_company_id ON public.contacts USING btree (company_id);


--
-- Name: index_contacts_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contacts_on_external_id ON public.contacts USING btree (external_id) WHERE (external_id IS NOT NULL);


--
-- Name: index_contacts_on_phone_digits; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contacts_on_phone_digits ON public.contacts USING btree (phone_digits);


--
-- Name: index_contacts_on_whatsapp_digits; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contacts_on_whatsapp_digits ON public.contacts USING btree (whatsapp_digits);


--
-- Name: index_contacts_one_primary_per_company; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contacts_one_primary_per_company ON public.contacts USING btree (company_id) WHERE "primary";


--
-- Name: index_contracts_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contracts_on_company_id ON public.contracts USING btree (company_id);


--
-- Name: index_contracts_on_end_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contracts_on_end_date ON public.contracts USING btree (end_date);


--
-- Name: index_contracts_on_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contracts_on_number ON public.contracts USING btree (number);


--
-- Name: index_contracts_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contracts_on_status ON public.contracts USING btree (status);


--
-- Name: index_customer_services_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_services_on_company_id ON public.customer_services USING btree (company_id);


--
-- Name: index_customer_services_on_contract_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_services_on_contract_id ON public.customer_services USING btree (contract_id);


--
-- Name: index_customer_services_on_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_services_on_service_id ON public.customer_services USING btree (service_id);


--
-- Name: index_customer_services_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_services_on_status ON public.customer_services USING btree (status);


--
-- Name: index_databases_on_app_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_databases_on_app_id ON public.databases USING btree (app_id);


--
-- Name: index_documents_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_company_id ON public.documents USING btree (company_id);


--
-- Name: index_documents_on_documentable_type_and_documentable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_documentable_type_and_documentable_id ON public.documents USING btree (documentable_type, documentable_id);


--
-- Name: index_documents_on_uploaded_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_uploaded_by_id ON public.documents USING btree (uploaded_by_id);


--
-- Name: index_domains_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_domains_on_company_id ON public.domains USING btree (company_id);


--
-- Name: index_domains_on_expires_on; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_domains_on_expires_on ON public.domains USING btree (expires_on);


--
-- Name: index_domains_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_domains_on_name ON public.domains USING btree (name);


--
-- Name: index_exchange_rates_on_currency_and_quoted_on; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_exchange_rates_on_currency_and_quoted_on ON public.exchange_rates USING btree (currency, quoted_on);


--
-- Name: index_external_services_on_app_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_external_services_on_app_id ON public.external_services USING btree (app_id);


--
-- Name: index_external_services_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_external_services_on_company_id ON public.external_services USING btree (company_id);


--
-- Name: index_external_services_on_supplier_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_external_services_on_supplier_id ON public.external_services USING btree (supplier_id);


--
-- Name: index_integrations_on_app_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_integrations_on_app_id ON public.integrations USING btree (app_id);


--
-- Name: index_interactions_on_subject_type_and_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_interactions_on_subject_type_and_subject_id ON public.interactions USING btree (subject_type, subject_id);


--
-- Name: index_interactions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_interactions_on_user_id ON public.interactions USING btree (user_id);


--
-- Name: index_interactions_whatsapp_daily; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_interactions_whatsapp_daily ON public.interactions USING btree (whatsapp_conversation_id, subject_type, subject_id, occurred_on) WHERE (whatsapp_conversation_id IS NOT NULL);


--
-- Name: index_invoices_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_company_id ON public.invoices USING btree (company_id);


--
-- Name: index_invoices_on_competence; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_competence ON public.invoices USING btree (competence);


--
-- Name: index_invoices_on_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invoices_on_number ON public.invoices USING btree (number) WHERE (number IS NOT NULL);


--
-- Name: index_leads_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_company_id ON public.leads USING btree (company_id);


--
-- Name: index_leads_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_leads_on_external_id ON public.leads USING btree (external_id) WHERE (external_id IS NOT NULL);


--
-- Name: index_leads_on_phone_digits; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_phone_digits ON public.leads USING btree (phone_digits);


--
-- Name: index_leads_on_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_service_id ON public.leads USING btree (service_id);


--
-- Name: index_leads_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_status ON public.leads USING btree (status);


--
-- Name: index_leads_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_user_id ON public.leads USING btree (user_id);


--
-- Name: index_leads_on_whatsapp_digits; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_whatsapp_digits ON public.leads USING btree (whatsapp_digits);


--
-- Name: index_notifications_on_notifiable_type_and_notifiable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_notifiable_type_and_notifiable_id ON public.notifications USING btree (notifiable_type, notifiable_id);


--
-- Name: index_notifications_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_user_id ON public.notifications USING btree (user_id);


--
-- Name: index_notifications_on_user_id_and_dedup_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_notifications_on_user_id_and_dedup_key ON public.notifications USING btree (user_id, dedup_key) WHERE (dedup_key IS NOT NULL);


--
-- Name: index_notifications_on_user_id_and_read_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_user_id_and_read_at ON public.notifications USING btree (user_id, read_at);


--
-- Name: index_oauth_access_grants_on_application_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_grants_on_application_id ON public.oauth_access_grants USING btree (application_id);


--
-- Name: index_oauth_access_grants_on_resource_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_grants_on_resource_owner_id ON public.oauth_access_grants USING btree (resource_owner_id);


--
-- Name: index_oauth_access_grants_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_grants_on_token ON public.oauth_access_grants USING btree (token);


--
-- Name: index_oauth_access_tokens_on_application_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_tokens_on_application_id ON public.oauth_access_tokens USING btree (application_id);


--
-- Name: index_oauth_access_tokens_on_refresh_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_tokens_on_refresh_token ON public.oauth_access_tokens USING btree (refresh_token);


--
-- Name: index_oauth_access_tokens_on_resource_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_tokens_on_resource_owner_id ON public.oauth_access_tokens USING btree (resource_owner_id);


--
-- Name: index_oauth_access_tokens_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_tokens_on_token ON public.oauth_access_tokens USING btree (token);


--
-- Name: index_oauth_applications_on_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_applications_on_uid ON public.oauth_applications USING btree (uid);


--
-- Name: index_opportunities_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_opportunities_on_company_id ON public.opportunities USING btree (company_id);


--
-- Name: index_opportunities_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_opportunities_on_external_id ON public.opportunities USING btree (external_id) WHERE (external_id IS NOT NULL);


--
-- Name: index_opportunities_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_opportunities_on_lead_id ON public.opportunities USING btree (lead_id);


--
-- Name: index_opportunities_on_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_opportunities_on_service_id ON public.opportunities USING btree (service_id);


--
-- Name: index_opportunities_on_stage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_opportunities_on_stage ON public.opportunities USING btree (stage);


--
-- Name: index_opportunities_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_opportunities_on_user_id ON public.opportunities USING btree (user_id);


--
-- Name: index_payables_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payables_on_company_id ON public.payables USING btree (company_id);


--
-- Name: index_payables_on_competence; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payables_on_competence ON public.payables USING btree (competence);


--
-- Name: index_payables_on_due_on; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payables_on_due_on ON public.payables USING btree (due_on);


--
-- Name: index_payables_on_external_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payables_on_external_service_id ON public.payables USING btree (external_service_id);


--
-- Name: index_payables_on_recurring_expense_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payables_on_recurring_expense_id ON public.payables USING btree (recurring_expense_id);


--
-- Name: index_payables_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payables_on_status ON public.payables USING btree (status);


--
-- Name: index_payables_on_supplier_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payables_on_supplier_id ON public.payables USING btree (supplier_id);


--
-- Name: index_payables_once_per_competence; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_payables_once_per_competence ON public.payables USING btree (recurring_expense_id, competence) WHERE (recurring_expense_id IS NOT NULL);


--
-- Name: index_product_costs_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_product_costs_on_product_id ON public.product_costs USING btree (product_id);


--
-- Name: index_product_costs_on_product_id_and_month; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_product_costs_on_product_id_and_month ON public.product_costs USING btree (product_id, month);


--
-- Name: index_products_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_products_on_name ON public.products USING btree (name);


--
-- Name: index_projects_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_company_id ON public.projects USING btree (company_id);


--
-- Name: index_projects_on_contract_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_contract_id ON public.projects USING btree (contract_id);


--
-- Name: index_projects_on_due_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_due_date ON public.projects USING btree (due_date);


--
-- Name: index_projects_on_proposal_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_proposal_id ON public.projects USING btree (proposal_id);


--
-- Name: index_projects_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_status ON public.projects USING btree (status);


--
-- Name: index_projects_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_user_id ON public.projects USING btree (user_id);


--
-- Name: index_proposal_items_on_proposal_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proposal_items_on_proposal_id ON public.proposal_items USING btree (proposal_id);


--
-- Name: index_proposal_items_on_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proposal_items_on_service_id ON public.proposal_items USING btree (service_id);


--
-- Name: index_proposals_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proposals_on_company_id ON public.proposals USING btree (company_id);


--
-- Name: index_proposals_on_contact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proposals_on_contact_id ON public.proposals USING btree (contact_id);


--
-- Name: index_proposals_on_contract_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proposals_on_contract_id ON public.proposals USING btree (contract_id);


--
-- Name: index_proposals_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proposals_on_lead_id ON public.proposals USING btree (lead_id);


--
-- Name: index_proposals_on_opportunity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proposals_on_opportunity_id ON public.proposals USING btree (opportunity_id);


--
-- Name: index_proposals_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proposals_on_status ON public.proposals USING btree (status);


--
-- Name: index_proposals_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proposals_on_user_id ON public.proposals USING btree (user_id);


--
-- Name: index_proposals_on_year_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_proposals_on_year_and_number ON public.proposals USING btree (year, number);


--
-- Name: index_receivables_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_receivables_on_company_id ON public.receivables USING btree (company_id);


--
-- Name: index_receivables_on_competence; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_receivables_on_competence ON public.receivables USING btree (competence);


--
-- Name: index_receivables_on_contact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_receivables_on_contact_id ON public.receivables USING btree (contact_id);


--
-- Name: index_receivables_on_contract_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_receivables_on_contract_id ON public.receivables USING btree (contract_id);


--
-- Name: index_receivables_on_customer_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_receivables_on_customer_service_id ON public.receivables USING btree (customer_service_id);


--
-- Name: index_receivables_on_due_on; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_receivables_on_due_on ON public.receivables USING btree (due_on);


--
-- Name: index_receivables_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_receivables_on_invoice_id ON public.receivables USING btree (invoice_id);


--
-- Name: index_receivables_on_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_receivables_on_service_id ON public.receivables USING btree (service_id);


--
-- Name: index_receivables_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_receivables_on_status ON public.receivables USING btree (status);


--
-- Name: index_receivables_once_per_competence; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_receivables_once_per_competence ON public.receivables USING btree (customer_service_id, competence) WHERE (customer_service_id IS NOT NULL);


--
-- Name: index_recurrence_runs_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recurrence_runs_on_user_id ON public.recurrence_runs USING btree (user_id);


--
-- Name: index_recurring_expenses_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recurring_expenses_on_company_id ON public.recurring_expenses USING btree (company_id);


--
-- Name: index_recurring_expenses_on_external_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recurring_expenses_on_external_service_id ON public.recurring_expenses USING btree (external_service_id);


--
-- Name: index_recurring_expenses_on_supplier_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recurring_expenses_on_supplier_id ON public.recurring_expenses USING btree (supplier_id);


--
-- Name: index_roles_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_roles_on_key ON public.roles USING btree (key);


--
-- Name: index_servers_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_servers_on_company_id ON public.servers USING btree (company_id);


--
-- Name: index_servers_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_servers_on_name ON public.servers USING btree (name);


--
-- Name: index_servers_on_supplier_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_servers_on_supplier_id ON public.servers USING btree (supplier_id);


--
-- Name: index_services_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_services_on_name ON public.services USING btree (name);


--
-- Name: index_settings_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_settings_on_key ON public.settings USING btree (key);


--
-- Name: index_subscriptions_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_company_id ON public.subscriptions USING btree (company_id);


--
-- Name: index_subscriptions_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_product_id ON public.subscriptions USING btree (product_id);


--
-- Name: index_subscriptions_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_status ON public.subscriptions USING btree (status);


--
-- Name: index_suppliers_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_suppliers_on_name ON public.suppliers USING btree (name);


--
-- Name: index_tasks_on_due_on; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_due_on ON public.tasks USING btree (due_on);


--
-- Name: index_tasks_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_project_id ON public.tasks USING btree (project_id);


--
-- Name: index_tasks_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_status ON public.tasks USING btree (status);


--
-- Name: index_tasks_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_user_id ON public.tasks USING btree (user_id);


--
-- Name: index_ticket_messages_on_contact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ticket_messages_on_contact_id ON public.ticket_messages USING btree (contact_id);


--
-- Name: index_ticket_messages_on_ticket_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ticket_messages_on_ticket_id ON public.ticket_messages USING btree (ticket_id);


--
-- Name: index_ticket_messages_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ticket_messages_on_user_id ON public.ticket_messages USING btree (user_id);


--
-- Name: index_tickets_on_app_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tickets_on_app_id ON public.tickets USING btree (app_id);


--
-- Name: index_tickets_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tickets_on_company_id ON public.tickets USING btree (company_id);


--
-- Name: index_tickets_on_contact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tickets_on_contact_id ON public.tickets USING btree (contact_id);


--
-- Name: index_tickets_on_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tickets_on_number ON public.tickets USING btree (number);


--
-- Name: index_tickets_on_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tickets_on_priority ON public.tickets USING btree (priority);


--
-- Name: index_tickets_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tickets_on_status ON public.tickets USING btree (status);


--
-- Name: index_tickets_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tickets_on_user_id ON public.tickets USING btree (user_id);


--
-- Name: index_time_entries_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_entries_on_company_id ON public.time_entries USING btree (company_id);


--
-- Name: index_time_entries_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_entries_on_project_id ON public.time_entries USING btree (project_id);


--
-- Name: index_time_entries_on_task_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_entries_on_task_id ON public.time_entries USING btree (task_id);


--
-- Name: index_time_entries_on_ticket_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_entries_on_ticket_id ON public.time_entries USING btree (ticket_id);


--
-- Name: index_time_entries_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_entries_on_user_id ON public.time_entries USING btree (user_id);


--
-- Name: index_time_entries_on_worked_on; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_entries_on_worked_on ON public.time_entries USING btree (worked_on);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: index_users_on_role_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_role_id ON public.users USING btree (role_id);


--
-- Name: index_whatsapp_accounts_on_connected_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_accounts_on_connected_by_id ON public.whatsapp_accounts USING btree (connected_by_id);


--
-- Name: index_whatsapp_accounts_on_phone_number_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_whatsapp_accounts_on_phone_number_id ON public.whatsapp_accounts USING btree (phone_number_id);


--
-- Name: index_whatsapp_accounts_on_waba_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_accounts_on_waba_id ON public.whatsapp_accounts USING btree (waba_id);


--
-- Name: index_whatsapp_conversations_inbox; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_conversations_inbox ON public.whatsapp_conversations USING btree (whatsapp_account_id, last_message_at DESC, id DESC) WHERE (last_message_at IS NOT NULL);


--
-- Name: index_whatsapp_conversations_on_contact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_conversations_on_contact_id ON public.whatsapp_conversations USING btree (contact_id);


--
-- Name: index_whatsapp_conversations_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_conversations_on_lead_id ON public.whatsapp_conversations USING btree (lead_id);


--
-- Name: index_whatsapp_conversations_on_whatsapp_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_conversations_on_whatsapp_account_id ON public.whatsapp_conversations USING btree (whatsapp_account_id);


--
-- Name: index_whatsapp_conversations_on_whatsapp_account_id_and_bsuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_whatsapp_conversations_on_whatsapp_account_id_and_bsuid ON public.whatsapp_conversations USING btree (whatsapp_account_id, bsuid) WHERE (bsuid IS NOT NULL);


--
-- Name: index_whatsapp_conversations_on_whatsapp_account_id_and_wa_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_whatsapp_conversations_on_whatsapp_account_id_and_wa_id ON public.whatsapp_conversations USING btree (whatsapp_account_id, wa_id) WHERE (wa_id IS NOT NULL);


--
-- Name: index_whatsapp_conversations_unread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_conversations_unread ON public.whatsapp_conversations USING btree (whatsapp_account_id) WHERE ((unread_count > 0) AND (last_message_at IS NOT NULL));


--
-- Name: index_whatsapp_conversations_window; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_conversations_window ON public.whatsapp_conversations USING btree (whatsapp_account_id, last_inbound_at);


--
-- Name: index_whatsapp_messages_on_reaction_to_wa_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_messages_on_reaction_to_wa_message_id ON public.whatsapp_messages USING btree (reaction_to_wa_message_id);


--
-- Name: index_whatsapp_messages_on_reply_to_wa_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_messages_on_reply_to_wa_message_id ON public.whatsapp_messages USING btree (reply_to_wa_message_id);


--
-- Name: index_whatsapp_messages_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_messages_on_user_id ON public.whatsapp_messages USING btree (user_id);


--
-- Name: index_whatsapp_messages_on_wa_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_whatsapp_messages_on_wa_message_id ON public.whatsapp_messages USING btree (wa_message_id) WHERE (wa_message_id IS NOT NULL);


--
-- Name: index_whatsapp_messages_on_whatsapp_conversation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_messages_on_whatsapp_conversation_id ON public.whatsapp_messages USING btree (whatsapp_conversation_id);


--
-- Name: index_whatsapp_messages_timeline; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_messages_timeline ON public.whatsapp_messages USING btree (whatsapp_conversation_id, sent_at, id);


--
-- Name: index_whatsapp_templates_on_account_name_language; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_whatsapp_templates_on_account_name_language ON public.whatsapp_templates USING btree (whatsapp_account_id, name, language) WHERE ((status)::text <> 'deleted'::text);


--
-- Name: index_whatsapp_templates_on_meta_template_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_whatsapp_templates_on_meta_template_id ON public.whatsapp_templates USING btree (meta_template_id) WHERE (meta_template_id IS NOT NULL);


--
-- Name: index_whatsapp_templates_on_whatsapp_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_templates_on_whatsapp_account_id ON public.whatsapp_templates USING btree (whatsapp_account_id);


--
-- Name: audit_logs audit_logs_no_update_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_logs_no_update_delete BEFORE DELETE OR UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.audit_logs_immutable();


--
-- Name: projects fk_rails_003ff37a1f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT fk_rails_003ff37a1f FOREIGN KEY (contract_id) REFERENCES public.contracts(id);


--
-- Name: proposals fk_rails_0224a90884; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proposals
    ADD CONSTRAINT fk_rails_0224a90884 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: tasks fk_rails_02e851e3b7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_02e851e3b7 FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: integrations fk_rails_07594015fc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integrations
    ADD CONSTRAINT fk_rails_07594015fc FOREIGN KEY (app_id) REFERENCES public.apps(id);


--
-- Name: whatsapp_accounts fk_rails_0ca350a050; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_accounts
    ADD CONSTRAINT fk_rails_0ca350a050 FOREIGN KEY (connected_by_id) REFERENCES public.users(id);


--
-- Name: subscriptions fk_rails_0e8fef2fc0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_rails_0e8fef2fc0 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: recurrence_runs fk_rails_1843863e6d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurrence_runs
    ADD CONSTRAINT fk_rails_1843863e6d FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: leads fk_rails_1d08b36969; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT fk_rails_1d08b36969 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: audit_logs fk_rails_1f26bc34ae; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT fk_rails_1f26bc34ae FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: whatsapp_conversations fk_rails_201018306d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_conversations
    ADD CONSTRAINT fk_rails_201018306d FOREIGN KEY (whatsapp_account_id) REFERENCES public.whatsapp_accounts(id);


--
-- Name: apps fk_rails_2701a89c0b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apps
    ADD CONSTRAINT fk_rails_2701a89c0b FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: external_services fk_rails_2827a48830; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.external_services
    ADD CONSTRAINT fk_rails_2827a48830 FOREIGN KEY (app_id) REFERENCES public.apps(id);


--
-- Name: opportunities fk_rails_2903255e8d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT fk_rails_2903255e8d FOREIGN KEY (service_id) REFERENCES public.services(id);


--
-- Name: apps fk_rails_29fc5882e0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apps
    ADD CONSTRAINT fk_rails_29fc5882e0 FOREIGN KEY (contract_id) REFERENCES public.contracts(id);


--
-- Name: receivables fk_rails_327cd0b1c1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT fk_rails_327cd0b1c1 FOREIGN KEY (service_id) REFERENCES public.services(id);


--
-- Name: oauth_access_grants fk_rails_330c32d8d9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_grants
    ADD CONSTRAINT fk_rails_330c32d8d9 FOREIGN KEY (resource_owner_id) REFERENCES public.users(id);


--
-- Name: activities fk_rails_346b6d4b3a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT fk_rails_346b6d4b3a FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: ticket_messages fk_rails_398b98fd8f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_messages
    ADD CONSTRAINT fk_rails_398b98fd8f FOREIGN KEY (ticket_id) REFERENCES public.tickets(id);


--
-- Name: customer_services fk_rails_3b1d3cceca; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_services
    ADD CONSTRAINT fk_rails_3b1d3cceca FOREIGN KEY (service_id) REFERENCES public.services(id);


--
-- Name: external_services fk_rails_3baf5b0829; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.external_services
    ADD CONSTRAINT fk_rails_3baf5b0829 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: recurring_expenses fk_rails_3bde5d372c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_expenses
    ADD CONSTRAINT fk_rails_3bde5d372c FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id);


--
-- Name: interactions fk_rails_3cc25e7f8c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.interactions
    ADD CONSTRAINT fk_rails_3cc25e7f8c FOREIGN KEY (whatsapp_conversation_id) REFERENCES public.whatsapp_conversations(id) ON DELETE SET NULL;


--
-- Name: payables fk_rails_3f4c87199d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payables
    ADD CONSTRAINT fk_rails_3f4c87199d FOREIGN KEY (recurring_expense_id) REFERENCES public.recurring_expenses(id);


--
-- Name: proposals fk_rails_4197667de7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proposals
    ADD CONSTRAINT fk_rails_4197667de7 FOREIGN KEY (contact_id) REFERENCES public.contacts(id);


--
-- Name: contacts fk_rails_42b4583938; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT fk_rails_42b4583938 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: invoices fk_rails_433d4c368d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT fk_rails_433d4c368d FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: whatsapp_conversations fk_rails_43e3c20000; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_conversations
    ADD CONSTRAINT fk_rails_43e3c20000 FOREIGN KEY (linked_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: projects fk_rails_44a549d7b3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT fk_rails_44a549d7b3 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: tasks fk_rails_4d2a9e4d7e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_4d2a9e4d7e FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: servers fk_rails_4d53dc7c43; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.servers
    ADD CONSTRAINT fk_rails_4d53dc7c43 FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id);


--
-- Name: subscriptions fk_rails_52a3b81fce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_rails_52a3b81fce FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: tickets fk_rails_538a036fb9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT fk_rails_538a036fb9 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: whatsapp_templates fk_rails_53e97ad791; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_templates
    ADD CONSTRAINT fk_rails_53e97ad791 FOREIGN KEY (whatsapp_account_id) REFERENCES public.whatsapp_accounts(id);


--
-- Name: time_entries fk_rails_55dd5dcf98; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT fk_rails_55dd5dcf98 FOREIGN KEY (task_id) REFERENCES public.tasks(id);


--
-- Name: receivables fk_rails_5c4527148d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT fk_rails_5c4527148d FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: time_entries fk_rails_60aaef3a15; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT fk_rails_60aaef3a15 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: proposals fk_rails_630ac967de; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proposals
    ADD CONSTRAINT fk_rails_630ac967de FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: users fk_rails_642f17018b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_rails_642f17018b FOREIGN KEY (role_id) REFERENCES public.roles(id);


--
-- Name: contracts fk_rails_676562988a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT fk_rails_676562988a FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: proposals fk_rails_682fc30fda; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proposals
    ADD CONSTRAINT fk_rails_682fc30fda FOREIGN KEY (contract_id) REFERENCES public.contracts(id);


--
-- Name: interactions fk_rails_69c9b45391; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.interactions
    ADD CONSTRAINT fk_rails_69c9b45391 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: whatsapp_conversations fk_rails_6a55ee705b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_conversations
    ADD CONSTRAINT fk_rails_6a55ee705b FOREIGN KEY (contact_id) REFERENCES public.contacts(id);


--
-- Name: ticket_messages fk_rails_6d16e692c1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_messages
    ADD CONSTRAINT fk_rails_6d16e692c1 FOREIGN KEY (contact_id) REFERENCES public.contacts(id);


--
-- Name: opportunities fk_rails_6eedd6d9fe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT fk_rails_6eedd6d9fe FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: payables fk_rails_731b1d001f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payables
    ADD CONSTRAINT fk_rails_731b1d001f FOREIGN KEY (external_service_id) REFERENCES public.external_services(id);


--
-- Name: oauth_access_tokens fk_rails_732cb83ab7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT fk_rails_732cb83ab7 FOREIGN KEY (application_id) REFERENCES public.oauth_applications(id);


--
-- Name: domains fk_rails_76d46ed28d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domains
    ADD CONSTRAINT fk_rails_76d46ed28d FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: opportunities fk_rails_7a1e18e277; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT fk_rails_7a1e18e277 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: payables fk_rails_7d5ae8e8e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payables
    ADD CONSTRAINT fk_rails_7d5ae8e8e1 FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id);


--
-- Name: activities fk_rails_7e11bb717f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT fk_rails_7e11bb717f FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: documents fk_rails_83141d4c8c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT fk_rails_83141d4c8c FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: projects fk_rails_88157d0fea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT fk_rails_88157d0fea FOREIGN KEY (proposal_id) REFERENCES public.proposals(id);


--
-- Name: whatsapp_conversations fk_rails_9151a6c10c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_conversations
    ADD CONSTRAINT fk_rails_9151a6c10c FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: apps fk_rails_995ae3be76; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apps
    ADD CONSTRAINT fk_rails_995ae3be76 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: leads fk_rails_a05a032b61; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT fk_rails_a05a032b61 FOREIGN KEY (service_id) REFERENCES public.services(id);


--
-- Name: opportunities fk_rails_a3ec24b133; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT fk_rails_a3ec24b133 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: proposals fk_rails_a7b91303ea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proposals
    ADD CONSTRAINT fk_rails_a7b91303ea FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: receivables fk_rails_a9b96afbf2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT fk_rails_a9b96afbf2 FOREIGN KEY (customer_service_id) REFERENCES public.customer_services(id);


--
-- Name: servers fk_rails_abd7b47675; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.servers
    ADD CONSTRAINT fk_rails_abd7b47675 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: receivables fk_rails_ac4affce01; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT fk_rails_ac4affce01 FOREIGN KEY (contract_id) REFERENCES public.contracts(id);


--
-- Name: proposal_items fk_rails_aca8d0afd8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proposal_items
    ADD CONSTRAINT fk_rails_aca8d0afd8 FOREIGN KEY (proposal_id) REFERENCES public.proposals(id) ON DELETE CASCADE;


--
-- Name: whatsapp_messages fk_rails_aeb63ace9d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_messages
    ADD CONSTRAINT fk_rails_aeb63ace9d FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: tickets fk_rails_af94b68228; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT fk_rails_af94b68228 FOREIGN KEY (app_id) REFERENCES public.apps(id);


--
-- Name: notifications fk_rails_b080fb4855; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_rails_b080fb4855 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: product_costs fk_rails_b0ba7c2dfb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_costs
    ADD CONSTRAINT fk_rails_b0ba7c2dfb FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: time_entries fk_rails_b471d1824b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT fk_rails_b471d1824b FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: oauth_access_grants fk_rails_b4b53e07b8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_grants
    ADD CONSTRAINT fk_rails_b4b53e07b8 FOREIGN KEY (application_id) REFERENCES public.oauth_applications(id);


--
-- Name: payables fk_rails_b754b99d46; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payables
    ADD CONSTRAINT fk_rails_b754b99d46 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: projects fk_rails_b872a6760a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT fk_rails_b872a6760a FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: documents fk_rails_bb94f775d4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT fk_rails_bb94f775d4 FOREIGN KEY (uploaded_by_id) REFERENCES public.users(id);


--
-- Name: receivables fk_rails_bbd22dd23b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT fk_rails_bbd22dd23b FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: tickets fk_rails_bfd1018be0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT fk_rails_bfd1018be0 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: databases fk_rails_ca21348b41; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.databases
    ADD CONSTRAINT fk_rails_ca21348b41 FOREIGN KEY (app_id) REFERENCES public.apps(id);


--
-- Name: customer_services fk_rails_caa146859c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_services
    ADD CONSTRAINT fk_rails_caa146859c FOREIGN KEY (contract_id) REFERENCES public.contracts(id);


--
-- Name: customer_services fk_rails_d1d6dcd85b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_services
    ADD CONSTRAINT fk_rails_d1d6dcd85b FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: recurring_expenses fk_rails_d2410703ae; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_expenses
    ADD CONSTRAINT fk_rails_d2410703ae FOREIGN KEY (external_service_id) REFERENCES public.external_services(id);


--
-- Name: apps fk_rails_d296c622dc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apps
    ADD CONSTRAINT fk_rails_d296c622dc FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: whatsapp_messages fk_rails_db315c944a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_messages
    ADD CONSTRAINT fk_rails_db315c944a FOREIGN KEY (whatsapp_conversation_id) REFERENCES public.whatsapp_conversations(id);


--
-- Name: receivables fk_rails_e179c5abc7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT fk_rails_e179c5abc7 FOREIGN KEY (contact_id) REFERENCES public.contacts(id);


--
-- Name: ticket_messages fk_rails_e3ac3f9f84; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_messages
    ADD CONSTRAINT fk_rails_e3ac3f9f84 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: tickets fk_rails_e692bb4a5b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT fk_rails_e692bb4a5b FOREIGN KEY (contact_id) REFERENCES public.contacts(id);


--
-- Name: oauth_access_tokens fk_rails_ee63f25419; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT fk_rails_ee63f25419 FOREIGN KEY (resource_owner_id) REFERENCES public.users(id);


--
-- Name: proposal_items fk_rails_f0ef1ccf9b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proposal_items
    ADD CONSTRAINT fk_rails_f0ef1ccf9b FOREIGN KEY (service_id) REFERENCES public.services(id);


--
-- Name: time_entries fk_rails_f493b0c8e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT fk_rails_f493b0c8e1 FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: proposals fk_rails_f643061ad3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proposals
    ADD CONSTRAINT fk_rails_f643061ad3 FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id);


--
-- Name: recurring_expenses fk_rails_f6e42da676; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_expenses
    ADD CONSTRAINT fk_rails_f6e42da676 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: external_services fk_rails_fd07a767ac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.external_services
    ADD CONSTRAINT fk_rails_fd07a767ac FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id);


--
-- Name: time_entries fk_rails_fea7a886c0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT fk_rails_fea7a886c0 FOREIGN KEY (ticket_id) REFERENCES public.tickets(id);


--
-- Name: leads fk_rails_ff7b5232cd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT fk_rails_ff7b5232cd FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261028190000'),
('20261028180000'),
('20261028120000'),
('20261027200000'),
('20261027180000'),
('20261027120000'),
('20261023120000'),
('20261009150000'),
('20261009120000'),
('20261006153022'),
('20261006151158'),
('20261006130008'),
('20261006130007'),
('20261006130006'),
('20261006130005'),
('20261006130004'),
('20261006130003'),
('20261006130002'),
('20261006130001'),
('20261006130000'),
('20261006120006'),
('20261006120005'),
('20261006120004'),
('20261006120003'),
('20261006120002'),
('20261006120001'),
('20261006120000'),
('20261005120004'),
('20261005120003'),
('20261005120002'),
('20261005120001'),
('20261005120000'),
('20261002120004'),
('20261002120003'),
('20261002120002'),
('20261002120001'),
('20261002120000'),
('20261001224249'),
('20261001215904'),
('20261001215831'),
('20261001215830'),
('20261001215829'),
('20261001215828'),
('20261001215827'),
('20261001215826'),
('20261001215825'),
('20261001215824'),
('20261001215823'),
('20261001215822'),
('20261001182403'),
('20261001181915'),
('20261001181914'),
('20261001181913');

