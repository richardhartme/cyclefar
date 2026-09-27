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
-- Name: protect_completed_workout(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_completed_workout() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.status = 'completed' THEN
    RAISE EXCEPTION 'Completed workouts are immutable' USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;


--
-- Name: protect_completed_workout_child(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_completed_workout_child() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  parent_id bigint;
  parent_status text;
BEGIN
  -- Lock both old and new parents when reparenting. This serializes edits
  -- against completion so no child can slip into an immutable snapshot.
  FOR parent_id IN
    SELECT DISTINCT value FROM unnest(ARRAY[
      CASE WHEN TG_OP != 'INSERT' THEN OLD.planned_workout_id END,
      CASE WHEN TG_OP != 'DELETE' THEN NEW.planned_workout_id END
    ]) AS value WHERE value IS NOT NULL ORDER BY value
  LOOP
    SELECT status INTO parent_status FROM planned_workouts WHERE id = parent_id FOR UPDATE;
    IF parent_status = 'completed' THEN
      RAISE EXCEPTION 'Completed workout structure and feedback are immutable' USING ERRCODE = '23514';
    END IF;
  END LOOP;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: adaptation_proposals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.adaptation_proposals (
    id bigint NOT NULL,
    training_plan_id bigint NOT NULL,
    reason character varying NOT NULL,
    payload jsonb NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT adaptation_proposals_payload_object CHECK ((jsonb_typeof(payload) = 'object'::text))
);


--
-- Name: adaptation_proposals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.adaptation_proposals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: adaptation_proposals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.adaptation_proposals_id_seq OWNED BY public.adaptation_proposals.id;


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
-- Name: availability_slots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.availability_slots (
    id bigint NOT NULL,
    availability_template_id bigint NOT NULL,
    weekday integer NOT NULL,
    duration_minutes integer NOT NULL,
    intent character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT availability_slots_intent_values CHECK (((intent)::text = ANY ((ARRAY['intervals'::character varying, 'endurance'::character varying, 'recovery'::character varying, 'vo2_max'::character varying, 'threshold'::character varying, 'sweet_spot'::character varying, 'tempo'::character varying])::text[]))),
    CONSTRAINT availability_slots_minimum_duration CHECK ((duration_minutes >= 30)),
    CONSTRAINT availability_slots_weekday CHECK (((weekday >= 1) AND (weekday <= 7)))
);


--
-- Name: COLUMN availability_slots.weekday; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.availability_slots.weekday IS 'ISO weekday: Monday=1 through Sunday=7';


--
-- Name: availability_slots_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.availability_slots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: availability_slots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.availability_slots_id_seq OWNED BY public.availability_slots.id;


--
-- Name: availability_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.availability_templates (
    id bigint NOT NULL,
    training_plan_id bigint NOT NULL,
    effective_from date NOT NULL,
    effective_until date,
    source character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT availability_templates_ordered_dates CHECK ((effective_until >= effective_from)),
    CONSTRAINT availability_templates_source_values CHECK (((source)::text = ANY ((ARRAY['initial'::character varying, 'one_week_override'::character varying, 'from_date_change'::character varying])::text[])))
);


--
-- Name: availability_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.availability_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: availability_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.availability_templates_id_seq OWNED BY public.availability_templates.id;


--
-- Name: ftp_readings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ftp_readings (
    id bigint NOT NULL,
    rider_profile_id bigint NOT NULL,
    ftp_watts integer NOT NULL,
    effective_on date NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT ftp_readings_positive_ftp CHECK ((ftp_watts > 0))
);


--
-- Name: ftp_readings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ftp_readings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ftp_readings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ftp_readings_id_seq OWNED BY public.ftp_readings.id;


--
-- Name: intervals_icu_syncs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.intervals_icu_syncs (
    id bigint NOT NULL,
    planned_workout_id bigint,
    external_id character varying NOT NULL,
    intervals_event_id bigint,
    last_synced_at timestamp(6) without time zone,
    payload_digest character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT intervals_icu_syncs_owned_external_id CHECK ((((external_id)::text ~~ 'cyclefar-%'::text) AND (length((external_id)::text) > 9)))
);


--
-- Name: intervals_icu_syncs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.intervals_icu_syncs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: intervals_icu_syncs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.intervals_icu_syncs_id_seq OWNED BY public.intervals_icu_syncs.id;


--
-- Name: plan_phases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_phases (
    id bigint NOT NULL,
    training_plan_id bigint NOT NULL,
    kind character varying NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    "position" integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT plan_phases_kind_values CHECK (((kind)::text = ANY ((ARRAY['base'::character varying, 'build'::character varying, 'speciality'::character varying, 'taper'::character varying])::text[]))),
    CONSTRAINT plan_phases_ordered_dates CHECK ((ends_on >= starts_on)),
    CONSTRAINT plan_phases_positive_position CHECK (("position" > 0))
);


--
-- Name: plan_phases_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.plan_phases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: plan_phases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.plan_phases_id_seq OWNED BY public.plan_phases.id;


--
-- Name: planned_workouts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.planned_workouts (
    id bigint NOT NULL,
    training_plan_id bigint NOT NULL,
    plan_phase_id bigint,
    scheduled_on date NOT NULL,
    kind character varying DEFAULT 'workout'::character varying NOT NULL,
    intent character varying,
    subtype character varying,
    duration_minutes integer,
    name character varying,
    purpose character varying,
    detail_status character varying DEFAULT 'outline'::character varying NOT NULL,
    status character varying DEFAULT 'planned'::character varying NOT NULL,
    progression_level integer,
    variation_key character varying,
    estimated_np_watts numeric(12,4),
    estimated_if numeric(8,5),
    estimated_tss numeric(12,4),
    estimated_work_kj numeric(14,4),
    completed_ftp_watts integer,
    completed_target_snapshot jsonb,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT planned_workouts_completion_snapshot CHECK (((((status)::text = ANY ((ARRAY['planned'::character varying, 'missed'::character varying])::text[])) AND (completed_at IS NULL) AND (completed_ftp_watts IS NULL) AND (completed_target_snapshot IS NULL)) OR (((status)::text = 'completed'::text) AND (completed_at IS NOT NULL) AND (((kind)::text = 'ftp_test'::text) OR (((detail_status)::text = 'structured'::text) AND (completed_ftp_watts IS NOT NULL) AND (completed_ftp_watts > 0) AND (completed_target_snapshot IS NOT NULL) AND (jsonb_typeof(completed_target_snapshot) = 'object'::text) AND (completed_target_snapshot <> '{}'::jsonb)))))),
    CONSTRAINT planned_workouts_detail_status_values CHECK (((detail_status)::text = ANY ((ARRAY['outline'::character varying, 'structured'::character varying])::text[]))),
    CONSTRAINT planned_workouts_ftp_test_no_protocol CHECK ((((kind)::text <> 'ftp_test'::text) OR ((estimated_np_watts IS NULL) AND (estimated_if IS NULL) AND (estimated_tss IS NULL) AND (estimated_work_kj IS NULL) AND (duration_minutes IS NULL) AND ((detail_status)::text = 'outline'::text)))),
    CONSTRAINT planned_workouts_intent_values CHECK (((intent)::text = ANY ((ARRAY['intervals'::character varying, 'endurance'::character varying, 'recovery'::character varying, 'vo2_max'::character varying, 'threshold'::character varying, 'sweet_spot'::character varying, 'tempo'::character varying])::text[]))),
    CONSTRAINT planned_workouts_kind_values CHECK (((kind)::text = ANY ((ARRAY['workout'::character varying, 'ftp_test'::character varying, 'opener'::character varying])::text[]))),
    CONSTRAINT planned_workouts_minimum_duration CHECK ((((kind)::text = 'ftp_test'::text) OR ((duration_minutes IS NOT NULL) AND (duration_minutes >= 30) AND (intent IS NOT NULL)))),
    CONSTRAINT planned_workouts_nonnegative_metrics CHECK (((estimated_np_watts >= (0)::numeric) AND (estimated_if >= (0)::numeric) AND (estimated_tss >= (0)::numeric) AND (estimated_work_kj >= (0)::numeric))),
    CONSTRAINT planned_workouts_progression_level CHECK (((progression_level >= 1) AND (progression_level <= 7))),
    CONSTRAINT planned_workouts_status_values CHECK (((status)::text = ANY ((ARRAY['planned'::character varying, 'missed'::character varying, 'completed'::character varying])::text[]))),
    CONSTRAINT planned_workouts_subtype_values CHECK (((subtype)::text = ANY ((ARRAY['recovery'::character varying, 'endurance'::character varying, 'tempo'::character varying, 'sweet_spot'::character varying, 'threshold'::character varying, 'vo2_max'::character varying, 'over_under'::character varying])::text[])))
);


--
-- Name: planned_workouts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.planned_workouts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: planned_workouts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.planned_workouts_id_seq OWNED BY public.planned_workouts.id;


--
-- Name: rider_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rider_profiles (
    id bigint NOT NULL,
    ftp_watts integer NOT NULL,
    intervals_icu_api_key text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT rider_profiles_positive_ftp CHECK ((ftp_watts > 0)),
    CONSTRAINT rider_profiles_singleton CHECK ((id = 1))
);


--
-- Name: rider_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rider_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rider_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rider_profiles_id_seq OWNED BY public.rider_profiles.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    ip_address character varying,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: target_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.target_events (
    id bigint NOT NULL,
    training_plan_id bigint NOT NULL,
    name character varying NOT NULL,
    event_on date NOT NULL,
    discipline character varying NOT NULL,
    distance_km numeric(10,2),
    elevation_m integer,
    expected_duration_minutes integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT target_events_discipline_values CHECK (((discipline)::text = ANY ((ARRAY['road'::character varying, 'gravel'::character varying, 'mtb'::character varying, 'ultra_endurance'::character varying])::text[]))),
    CONSTRAINT target_events_valid_measurements CHECK (((distance_km > (0)::numeric) AND (elevation_m >= 0) AND (expected_duration_minutes > 0)))
);


--
-- Name: target_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.target_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: target_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.target_events_id_seq OWNED BY public.target_events.id;


--
-- Name: time_off_periods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.time_off_periods (
    id bigint NOT NULL,
    training_plan_id bigint NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    reason character varying NOT NULL,
    return_ramp_days integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    name character varying,
    CONSTRAINT time_off_periods_ordered_dates CHECK ((ends_on >= starts_on)),
    CONSTRAINT time_off_periods_reason_values CHECK (((reason)::text = ANY ((ARRAY['holiday'::character varying, 'illness'::character varying, 'recovery'::character varying, 'event'::character varying, 'other'::character varying])::text[]))),
    CONSTRAINT time_off_periods_return_ramp CHECK (((((reason)::text = ANY ((ARRAY['illness'::character varying, 'recovery'::character varying])::text[])) AND (return_ramp_days IS NOT NULL) AND (return_ramp_days > 0)) OR (((reason)::text = ANY ((ARRAY['holiday'::character varying, 'event'::character varying, 'other'::character varying])::text[])) AND (return_ramp_days IS NULL))))
);


--
-- Name: time_off_periods_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.time_off_periods_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: time_off_periods_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.time_off_periods_id_seq OWNED BY public.time_off_periods.id;


--
-- Name: training_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.training_plans (
    id bigint NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    goal character varying NOT NULL,
    discipline character varying NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    include_base boolean DEFAULT true NOT NULL,
    progression_mode character varying NOT NULL,
    hard_weeks_before_recovery integer,
    initial_ftp_watts integer NOT NULL,
    progression_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    engine_version character varying DEFAULT 'v1'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT training_plans_discipline_values CHECK (((discipline)::text = ANY ((ARRAY['road'::character varying, 'gravel'::character varying, 'mtb'::character varying, 'ultra_endurance'::character varying])::text[]))),
    CONSTRAINT training_plans_goal_values CHECK (((goal)::text = ANY ((ARRAY['general_fitness'::character varying, 'increase_ftp'::character varying, 'improve_endurance'::character varying, 'improve_climbing'::character varying, 'event'::character varying])::text[]))),
    CONSTRAINT training_plans_ordered_dates CHECK ((ends_on >= starts_on)),
    CONSTRAINT training_plans_positive_ftp CHECK ((initial_ftp_watts > 0)),
    CONSTRAINT training_plans_progression_mode_values CHECK (((progression_mode)::text = ANY ((ARRAY['continuous'::character varying, 'hard_recovery_cycle'::character varying])::text[]))),
    CONSTRAINT training_plans_progression_object CHECK ((jsonb_typeof(progression_state) = 'object'::text)),
    CONSTRAINT training_plans_recovery_cycle CHECK (((((progression_mode)::text = 'continuous'::text) AND (hard_weeks_before_recovery IS NULL)) OR (((progression_mode)::text = 'hard_recovery_cycle'::text) AND (hard_weeks_before_recovery IS NOT NULL) AND (hard_weeks_before_recovery > 0)))),
    CONSTRAINT training_plans_status_values CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'archived'::character varying])::text[])))
);


--
-- Name: training_plans_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.training_plans_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: training_plans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.training_plans_id_seq OWNED BY public.training_plans.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email_address character varying NOT NULL,
    password_digest character varying NOT NULL,
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
-- Name: workout_feedbacks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workout_feedbacks (
    id bigint NOT NULL,
    planned_workout_id bigint NOT NULL,
    rpe integer NOT NULL,
    completion_quality character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT workout_feedbacks_completion_quality_values CHECK (((completion_quality)::text = ANY ((ARRAY['as_planned'::character varying, 'struggled_completed'::character varying, 'could_not_complete'::character varying])::text[]))),
    CONSTRAINT workout_feedbacks_rpe CHECK (((rpe >= 1) AND (rpe <= 10)))
);


--
-- Name: workout_feedbacks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.workout_feedbacks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: workout_feedbacks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.workout_feedbacks_id_seq OWNED BY public.workout_feedbacks.id;


--
-- Name: workout_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workout_steps (
    id bigint NOT NULL,
    planned_workout_id bigint NOT NULL,
    "position" integer NOT NULL,
    kind character varying NOT NULL,
    label character varying NOT NULL,
    duration_seconds integer NOT NULL,
    target_low_pct_ftp numeric(7,3) NOT NULL,
    target_high_pct_ftp numeric(7,3) NOT NULL,
    end_target_low_pct_ftp numeric(7,3),
    end_target_high_pct_ftp numeric(7,3),
    group_key character varying,
    group_iteration integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT workout_steps_kind_values CHECK (((kind)::text = ANY ((ARRAY['steady'::character varying, 'ramp'::character varying])::text[]))),
    CONSTRAINT workout_steps_positive_iteration CHECK ((group_iteration > 0)),
    CONSTRAINT workout_steps_positive_position_duration CHECK ((("position" > 0) AND (duration_seconds > 0))),
    CONSTRAINT workout_steps_ramp_endpoints CHECK (((((kind)::text = 'steady'::text) AND (end_target_low_pct_ftp IS NULL) AND (end_target_high_pct_ftp IS NULL)) OR (((kind)::text = 'ramp'::text) AND (end_target_low_pct_ftp IS NOT NULL) AND (end_target_high_pct_ftp IS NOT NULL) AND (end_target_low_pct_ftp > (0)::numeric) AND (end_target_low_pct_ftp <= end_target_high_pct_ftp)))),
    CONSTRAINT workout_steps_target_range CHECK (((target_low_pct_ftp > (0)::numeric) AND (target_low_pct_ftp <= target_high_pct_ftp)))
);


--
-- Name: workout_steps_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.workout_steps_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: workout_steps_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.workout_steps_id_seq OWNED BY public.workout_steps.id;


--
-- Name: adaptation_proposals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adaptation_proposals ALTER COLUMN id SET DEFAULT nextval('public.adaptation_proposals_id_seq'::regclass);


--
-- Name: availability_slots id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.availability_slots ALTER COLUMN id SET DEFAULT nextval('public.availability_slots_id_seq'::regclass);


--
-- Name: availability_templates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.availability_templates ALTER COLUMN id SET DEFAULT nextval('public.availability_templates_id_seq'::regclass);


--
-- Name: ftp_readings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ftp_readings ALTER COLUMN id SET DEFAULT nextval('public.ftp_readings_id_seq'::regclass);


--
-- Name: intervals_icu_syncs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intervals_icu_syncs ALTER COLUMN id SET DEFAULT nextval('public.intervals_icu_syncs_id_seq'::regclass);


--
-- Name: plan_phases id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_phases ALTER COLUMN id SET DEFAULT nextval('public.plan_phases_id_seq'::regclass);


--
-- Name: planned_workouts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planned_workouts ALTER COLUMN id SET DEFAULT nextval('public.planned_workouts_id_seq'::regclass);


--
-- Name: rider_profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rider_profiles ALTER COLUMN id SET DEFAULT nextval('public.rider_profiles_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: target_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.target_events ALTER COLUMN id SET DEFAULT nextval('public.target_events_id_seq'::regclass);


--
-- Name: time_off_periods id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_off_periods ALTER COLUMN id SET DEFAULT nextval('public.time_off_periods_id_seq'::regclass);


--
-- Name: training_plans id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.training_plans ALTER COLUMN id SET DEFAULT nextval('public.training_plans_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: workout_feedbacks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workout_feedbacks ALTER COLUMN id SET DEFAULT nextval('public.workout_feedbacks_id_seq'::regclass);


--
-- Name: workout_steps id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workout_steps ALTER COLUMN id SET DEFAULT nextval('public.workout_steps_id_seq'::regclass);


--
-- Name: adaptation_proposals adaptation_proposals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adaptation_proposals
    ADD CONSTRAINT adaptation_proposals_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: availability_slots availability_slots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.availability_slots
    ADD CONSTRAINT availability_slots_pkey PRIMARY KEY (id);


--
-- Name: availability_templates availability_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.availability_templates
    ADD CONSTRAINT availability_templates_pkey PRIMARY KEY (id);


--
-- Name: ftp_readings ftp_readings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ftp_readings
    ADD CONSTRAINT ftp_readings_pkey PRIMARY KEY (id);


--
-- Name: intervals_icu_syncs intervals_icu_syncs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intervals_icu_syncs
    ADD CONSTRAINT intervals_icu_syncs_pkey PRIMARY KEY (id);


--
-- Name: plan_phases plan_phases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_phases
    ADD CONSTRAINT plan_phases_pkey PRIMARY KEY (id);


--
-- Name: planned_workouts planned_workouts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planned_workouts
    ADD CONSTRAINT planned_workouts_pkey PRIMARY KEY (id);


--
-- Name: rider_profiles rider_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rider_profiles
    ADD CONSTRAINT rider_profiles_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: target_events target_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.target_events
    ADD CONSTRAINT target_events_pkey PRIMARY KEY (id);


--
-- Name: time_off_periods time_off_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_off_periods
    ADD CONSTRAINT time_off_periods_pkey PRIMARY KEY (id);


--
-- Name: training_plans training_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.training_plans
    ADD CONSTRAINT training_plans_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: workout_feedbacks workout_feedbacks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workout_feedbacks
    ADD CONSTRAINT workout_feedbacks_pkey PRIMARY KEY (id);


--
-- Name: workout_steps workout_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workout_steps
    ADD CONSTRAINT workout_steps_pkey PRIMARY KEY (id);


--
-- Name: idx_on_availability_template_id_weekday_62ef633d01; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_availability_template_id_weekday_62ef633d01 ON public.availability_slots USING btree (availability_template_id, weekday);


--
-- Name: index_adaptation_proposals_on_training_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_adaptation_proposals_on_training_plan_id ON public.adaptation_proposals USING btree (training_plan_id);


--
-- Name: index_availability_slots_on_availability_template_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_availability_slots_on_availability_template_id ON public.availability_slots USING btree (availability_template_id);


--
-- Name: index_availability_templates_on_training_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_availability_templates_on_training_plan_id ON public.availability_templates USING btree (training_plan_id);


--
-- Name: index_ftp_readings_on_rider_profile_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ftp_readings_on_rider_profile_id ON public.ftp_readings USING btree (rider_profile_id);


--
-- Name: index_intervals_icu_syncs_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_intervals_icu_syncs_on_external_id ON public.intervals_icu_syncs USING btree (external_id);


--
-- Name: index_intervals_icu_syncs_on_planned_workout_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_intervals_icu_syncs_on_planned_workout_id ON public.intervals_icu_syncs USING btree (planned_workout_id);


--
-- Name: index_plan_phases_on_training_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_plan_phases_on_training_plan_id ON public.plan_phases USING btree (training_plan_id);


--
-- Name: index_plan_phases_on_training_plan_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_plan_phases_on_training_plan_id_and_position ON public.plan_phases USING btree (training_plan_id, "position");


--
-- Name: index_planned_workouts_on_plan_phase_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_planned_workouts_on_plan_phase_id ON public.planned_workouts USING btree (plan_phase_id);


--
-- Name: index_planned_workouts_on_training_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_planned_workouts_on_training_plan_id ON public.planned_workouts USING btree (training_plan_id);


--
-- Name: index_planned_workouts_on_training_plan_id_and_scheduled_on; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_planned_workouts_on_training_plan_id_and_scheduled_on ON public.planned_workouts USING btree (training_plan_id, scheduled_on);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_target_events_on_training_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_target_events_on_training_plan_id ON public.target_events USING btree (training_plan_id);


--
-- Name: index_time_off_periods_on_training_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_off_periods_on_training_plan_id ON public.time_off_periods USING btree (training_plan_id);


--
-- Name: index_users_on_email_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email_address ON public.users USING btree (email_address);


--
-- Name: index_workout_feedbacks_on_planned_workout_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_workout_feedbacks_on_planned_workout_id ON public.workout_feedbacks USING btree (planned_workout_id);


--
-- Name: index_workout_steps_on_planned_workout_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workout_steps_on_planned_workout_id ON public.workout_steps USING btree (planned_workout_id);


--
-- Name: index_workout_steps_on_planned_workout_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_workout_steps_on_planned_workout_id_and_position ON public.workout_steps USING btree (planned_workout_id, "position");


--
-- Name: one_active_training_plan; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_active_training_plan ON public.training_plans USING btree (status) WHERE ((status)::text = 'active'::text);


--
-- Name: planned_workouts_calendar_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX planned_workouts_calendar_lookup ON public.planned_workouts USING btree (scheduled_on, status, detail_status);


--
-- Name: planned_workouts protect_completed_workout; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER protect_completed_workout BEFORE DELETE OR UPDATE ON public.planned_workouts FOR EACH ROW EXECUTE FUNCTION public.protect_completed_workout();


--
-- Name: workout_feedbacks protect_completed_workout_feedback; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER protect_completed_workout_feedback BEFORE INSERT OR DELETE OR UPDATE ON public.workout_feedbacks FOR EACH ROW EXECUTE FUNCTION public.protect_completed_workout_child();


--
-- Name: workout_steps protect_completed_workout_steps; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER protect_completed_workout_steps BEFORE INSERT OR DELETE OR UPDATE ON public.workout_steps FOR EACH ROW EXECUTE FUNCTION public.protect_completed_workout_child();


--
-- Name: workout_steps fk_rails_00361ce4c5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workout_steps
    ADD CONSTRAINT fk_rails_00361ce4c5 FOREIGN KEY (planned_workout_id) REFERENCES public.planned_workouts(id);


--
-- Name: intervals_icu_syncs fk_rails_1b42bdfe2e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intervals_icu_syncs
    ADD CONSTRAINT fk_rails_1b42bdfe2e FOREIGN KEY (planned_workout_id) REFERENCES public.planned_workouts(id) ON DELETE SET NULL;


--
-- Name: target_events fk_rails_3b15ecb01e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.target_events
    ADD CONSTRAINT fk_rails_3b15ecb01e FOREIGN KEY (training_plan_id) REFERENCES public.training_plans(id);


--
-- Name: workout_feedbacks fk_rails_41527fb704; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workout_feedbacks
    ADD CONSTRAINT fk_rails_41527fb704 FOREIGN KEY (planned_workout_id) REFERENCES public.planned_workouts(id);


--
-- Name: planned_workouts fk_rails_57a930ba19; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planned_workouts
    ADD CONSTRAINT fk_rails_57a930ba19 FOREIGN KEY (plan_phase_id) REFERENCES public.plan_phases(id);


--
-- Name: plan_phases fk_rails_6237434079; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_phases
    ADD CONSTRAINT fk_rails_6237434079 FOREIGN KEY (training_plan_id) REFERENCES public.training_plans(id);


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: availability_slots fk_rails_7bf4b89dc8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.availability_slots
    ADD CONSTRAINT fk_rails_7bf4b89dc8 FOREIGN KEY (availability_template_id) REFERENCES public.availability_templates(id);


--
-- Name: adaptation_proposals fk_rails_99bb4455b5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adaptation_proposals
    ADD CONSTRAINT fk_rails_99bb4455b5 FOREIGN KEY (training_plan_id) REFERENCES public.training_plans(id);


--
-- Name: ftp_readings fk_rails_a29c9e67df; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ftp_readings
    ADD CONSTRAINT fk_rails_a29c9e67df FOREIGN KEY (rider_profile_id) REFERENCES public.rider_profiles(id);


--
-- Name: time_off_periods fk_rails_c75fbde598; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_off_periods
    ADD CONSTRAINT fk_rails_c75fbde598 FOREIGN KEY (training_plan_id) REFERENCES public.training_plans(id);


--
-- Name: availability_templates fk_rails_cfce6000d0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.availability_templates
    ADD CONSTRAINT fk_rails_cfce6000d0 FOREIGN KEY (training_plan_id) REFERENCES public.training_plans(id);


--
-- Name: planned_workouts fk_rails_e016bf7fc7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planned_workouts
    ADD CONSTRAINT fk_rails_e016bf7fc7 FOREIGN KEY (training_plan_id) REFERENCES public.training_plans(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260927123825'),
('20260927123824'),
('20260921000001'),
('20260921000000'),
('20260912000001'),
('20260912000000'),
('20260910000000'),
('20260906000001'),
('20260905000002'),
('20260905000001');

