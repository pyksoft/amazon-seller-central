--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: notifications; Type: TABLE; Schema: public; Owner: ekoper; Tablespace: 
--

CREATE TABLE notifications (
    id integer NOT NULL,
    text text,
    product_id integer,
    created_at timestamp without time zone,
    seen boolean,
    icon character varying(255)
);


ALTER TABLE public.notifications OWNER TO ekoper;

--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: ekoper
--

CREATE SEQUENCE notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.notifications_id_seq OWNER TO ekoper;

--
-- Name: notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: ekoper
--

ALTER SEQUENCE notifications_id_seq OWNED BY notifications.id;


--
-- Name: products; Type: TABLE; Schema: public; Owner: ekoper; Tablespace: 
--

CREATE TABLE products (
    id integer NOT NULL,
    ebay_item_id character varying(255),
    amazon_asin_number character varying(255),
    title text,
    image_url text,
    old_price double precision,
    new_price double precision,
    prime boolean,
    seen boolean,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.products OWNER TO ekoper;

--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: ekoper
--

CREATE SEQUENCE products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.products_id_seq OWNER TO ekoper;

--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: ekoper
--

ALTER SEQUENCE products_id_seq OWNED BY products.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: ekoper; Tablespace: 
--

CREATE TABLE schema_migrations (
    version character varying(255) NOT NULL
);


ALTER TABLE public.schema_migrations OWNER TO ekoper;

--
-- Name: id; Type: DEFAULT; Schema: public; Owner: ekoper
--

ALTER TABLE ONLY notifications ALTER COLUMN id SET DEFAULT nextval('notifications_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: ekoper
--

ALTER TABLE ONLY products ALTER COLUMN id SET DEFAULT nextval('products_id_seq'::regclass);


--
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: ekoper
--

COPY notifications (id, text, product_id, created_at, seen, icon) FROM stdin;
13	\N	\N	2014-08-23 16:31:07.546657	t	\N
\.


--
-- Name: notifications_id_seq; Type: SEQUENCE SET; Schema: public; Owner: ekoper
--

SELECT pg_catalog.setval('notifications_id_seq', 13, true);


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: ekoper
--

COPY products (id, ebay_item_id, amazon_asin_number, title, image_url, old_price, new_price, prime, seen, created_at, updated_at) FROM stdin;
2	251619755615	B00HWPAAQA	Waterfall Bathroom Sink Vessel Faucet Oil Rubbed Bronze One Hole Basin Mixer Tap	http://ecx.images-amazon.com/images/I/51EZGSpfh7L._SL160_.jpg	59	\N	t	f	2014-08-23 11:43:06.798698	2014-08-23 11:43:06.798698
3	261559137845	B004RNR9QY	Camco 22853 Premium Drinking Water Hose (5/8"ID x 50')	http://ecx.images-amazon.com/images/I/41JqKDXPb1L._SL160_.jpg	25	\N	t	f	2014-08-23 11:43:07.303093	2014-08-23 11:43:07.303093
4	251556490097	B0009Y0188	Coleman Replacement Power Cord	http://ecx.images-amazon.com/images/I/51Y5c2kBIrL._SL160_.jpg	15.9900000000000002	\N	t	f	2014-08-23 11:43:07.839453	2014-08-23 11:43:07.839453
5	261563180543	B0024AKCTS	Kamenstein Perfect Tear Horizontal Paper Towel Holder	http://ecx.images-amazon.com/images/I/41whDpfUmnL._SL160_.jpg	14.9900000000000002	\N	t	f	2014-08-23 11:43:08.57634	2014-08-23 11:43:08.57634
6	261545924304	B007VAS2K2	IMAX Wise Owls, Set of 3	http://ecx.images-amazon.com/images/I/41uVQ5W3HJL._SL160_.jpg	21.8299999999999983	\N	t	f	2014-08-23 11:43:12.773735	2014-08-23 11:43:12.773735
7	251619755615	B00HWPAAQA	Waterfall Bathroom Sink Vessel Faucet Oil Rubbed Bronze One Hole Basin Mixer Tap	http://ecx.images-amazon.com/images/I/51EZGSpfh7L._SL160_.jpg	59	\N	t	f	2014-08-23 11:43:14.248938	2014-08-23 11:43:14.248938
8	251600958201	B005KR4LP8	Arnold 4902900013 Universal Lawn Track Cover, Black	http://ecx.images-amazon.com/images/I/31XPEd5mloL._SL160_.jpg	28.9899999999999984	\N	t	f	2014-08-23 11:43:15.152385	2014-08-23 11:43:15.152385
9	261541742459	B001L9FTTG	Head Case	http://ecx.images-amazon.com/images/I/41tx5yuC%2BNL._SL160_.jpg	20.4299999999999997	\N	t	f	2014-08-23 11:43:16.154892	2014-08-23 11:43:16.154892
10	251588738999	B003XGYDE2	Goodyear i8000 120-Volt Direct Drive Tire Inflator	http://ecx.images-amazon.com/images/I/51Xj2gSiQDL._SL160_.jpg	50.0900000000000034	\N	t	f	2014-08-23 11:43:17.025247	2014-08-23 11:43:17.025247
12	261547288428	B00C5TEJJC	Valterra A01-2004VP White Carded Gravity/Plastic City Water Inlet Hatch	http://ecx.images-amazon.com/images/I/41wvEzdVDqL._SL160_.jpg	26.5199999999999996	\N	t	f	2014-08-23 11:43:22.985046	2014-08-23 11:43:22.985046
1	251572120366	B009XON646	External Super Slim USB 2.0 Slot-In DVD-RW, Silver	http://ecx.images-amazon.com/images/I/31olRRUFpjL._SL160_.jpg	26.379999999999999	\N	t	f	2014-08-23 11:43:06.339965	2014-08-23 15:20:57.975002
11	261569849238	B00CMXH2FY	Ceramic Blue Coffee Mug with Owls and Scripture - Be Strong	http://ecx.images-amazon.com/images/I/51i88am-I3L._SL160_.jpg	12.9499999999999993	\N	t	f	2014-08-23 11:43:20.166431	2014-08-23 15:21:09.240849
13	261538233399	B005GEPO3S	Black Light Reactive Neon Beer Pong Party Pack #79080	http://ecx.images-amazon.com/images/I/41OWKMIFYjL._SL160_.jpg	15.3900000000000006	\N	t	f	2014-08-23 11:43:45.923573	2014-08-23 15:21:15.404853
14	261544272131	B002NU5O9C	\N	http://ecx.images-amazon.com/images/I/41aVP6iGElL._SL160_.jpg	18.9899999999999984	\N	t	\N	2014-08-25 21:29:23.556876	2014-08-25 21:29:23.556876
\.


--
-- Name: products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: ekoper
--

SELECT pg_catalog.setval('products_id_seq', 14, true);


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: ekoper
--

COPY schema_migrations (version) FROM stdin;
20140731132430
20140731142755
20140802131309
\.


--
-- Name: notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: ekoper; Tablespace: 
--

ALTER TABLE ONLY notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: products_pkey; Type: CONSTRAINT; Schema: public; Owner: ekoper; Tablespace: 
--

ALTER TABLE ONLY products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: unique_schema_migrations; Type: INDEX; Schema: public; Owner: ekoper; Tablespace: 
--

CREATE UNIQUE INDEX unique_schema_migrations ON schema_migrations USING btree (version);


--
-- Name: public; Type: ACL; Schema: -; Owner: ekoper
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM ekoper;
GRANT ALL ON SCHEMA public TO ekoper;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

