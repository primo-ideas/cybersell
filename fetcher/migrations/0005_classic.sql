-- Mists of Pandaria Classic, next to World of Warcraft as it is today. Its markets are
-- told apart by their region, as Battle.net does in its namespaces: `classic-eu` next to
-- `eu`. So a Classic realm never collides with a retail one of the same name, and what
-- refers to a realm by region and slug needs no change.
--
-- Items and pets are another matter: the two games share ids, but not always names,
-- levels or icons. Each edition gets its own rows: 'retail' or 'classic'.

ALTER TABLE auction_houses ADD COLUMN edition TEXT NOT NULL DEFAULT 'retail';
ALTER TABLE auction_houses ALTER COLUMN edition DROP DEFAULT;

ALTER TABLE items ADD COLUMN edition TEXT NOT NULL DEFAULT 'retail';
ALTER TABLE items ALTER COLUMN edition DROP DEFAULT;
ALTER TABLE items DROP CONSTRAINT items_pkey;
ALTER TABLE items ADD PRIMARY KEY (edition, id);

ALTER TABLE pets ADD COLUMN edition TEXT NOT NULL DEFAULT 'retail';
ALTER TABLE pets ALTER COLUMN edition DROP DEFAULT;
ALTER TABLE pets DROP CONSTRAINT pets_pkey;
ALTER TABLE pets ADD PRIMARY KEY (edition, species_id);
