--------------------- SCRIPT 6 -------------------------
---------- 22.08.2024 ----- by Anna Mengden ------------
------ Creation of dataset "spaces_per_lor_v3" ---------
------ with traffic area, traffic area rel. to ---------
------ built up area and green space provision ---------
------ per planning area  ------------------------------


--- Used datasets: "merged_highways_1_to_7_final" (created roadway dataset)
		-- "parking_segments_ad_130324" (created on-street parking spaces dataset)
		-- "amenity_parking_parking_surface_ring" (created off-street parking spaces dataset)
		-- "plr_ring_modi" (created planning area boundary dataset)
		-- "flaechennutzung_2021_ring" (reale nutzung dataset by SenStadt 2022a)
		-- "umweltgerech_gruenversorgung_2021_2022" (Grünflächenversorgung by SenMVKU 2022)


------------------------------------------------------------------------------
---- Order of the following script:

-- 1) Create "spaces_per_lor_v3" based on planning area layer 

-- 2) Aggregate traffic area types to planning areas

-- 3) Summing up traffic areas depending on conversion Option 1,2,3

-- 4) Assign built-up and inhabited area to planning areas

-- 5) Divide traffic areas by built-up area

-- 6) Calculate proportion of inhabited area per built-up area

-- 7) Assign green space provision categories to planning areas in "spaces_per_lor_v3"

-- 8) Save "spaces_per_lor_v3" as csv for plotting in R

-- 9) Create table with all values for results 3 table
------------------------------------------------------------------------------


-------------- 1) Create "spaces_per_lor_v3" based on planning area layer 


----- Verkehrsflächen (roadway, on-street und off-street parking spaces)
----- pro LOR (Planungsraum (PLR))
----- in neue Tabelle (spaces_per_lor_v3)

-- dafür plr_id, name und geometrie von plr_ring_modi übernehmen

CREATE TABLE spaces_per_lor_v3 AS
SELECT plr_id, plr_name, plr_area, geom
FROM plr_ring_modi;

-- primary key muss immer
ALTER TABLE spaces_per_lor_v3
ADD COLUMN id SERIAL PRIMARY KEY;

-- weitere Spalten hinzufügen (absolute und relative Verkehrsflächengrößen/mengen)
ALTER TABLE spaces_per_lor_v3

ADD COLUMN roadway_area FLOAT,
ADD COLUMN on_street_parking_spaces FLOAT,
ADD COLUMN off_street_parking_spaces FLOAT,

ADD COLUMN max_decision_option FLOAT,
ADD COLUMN mix_decision_option FLOAT,
ADD COLUMN mod_decision_option FLOAT,

ADD COLUMN bebaut_area FLOAT,
ADD COLUMN bewohnt_area FLOAT,

ADD COLUMN roadway_per_bebaut FLOAT,
ADD COLUMN on_str_per_bebaut FLOAT,
ADD COLUMN off_str_per_bebaut FLOAT,

ADD COLUMN max_d_o_per_bebaut FLOAT,
ADD COLUMN mix_d_o_per_bebaut FLOAT,
ADD COLUMN mod_d_o_per_bebaut FLOAT,

ADD COLUMN share_bewohnt_an_bebaut FLOAT,

ADD COLUMN roadway_per_bewohnt FLOAT,
ADD COLUMN on_str_per_bewohnt FLOAT,
ADD COLUMN off_str_per_bewohnt FLOAT,

ADD COLUMN max_d_o_per_bewohnt FLOAT,
ADD COLUMN mix_d_o_per_bewohnt FLOAT,
ADD COLUMN mod_d_o_per_bewohnt FLOAT,

ADD COLUMN gruenver_text TEXT,
ADD COLUMN gruenver_numeric FLOAT,
ADD COLUMN laermbel_text TEXT,
ADD COLUMN laermbel_numeric FLOAT
;


-------------- 2) Aggregate traffic area types to planning areas


---- a. ----
-- roadway area berechnen mit merged_highways_1_to_7_final (das ist das bei dem Fahrradparkplätze in QGIS abgezogen wurden)
	-- je nach geometrie der Planungräume

UPDATE spaces_per_lor_v3 AS s
SET roadway_area = (
    SELECT SUM(ST_Area(ST_Intersection(s.geom, h.geom)))
    FROM merged_highways_1_to_7_final AS h
    WHERE ST_Intersects(s.geom, h.geom)
);

SELECT SUM(roadway_area) FROM spaces_per_lor_v3;
-- (Summe von roadway_area = 799 ha)
 


---- b. ----
-- on-street parking spaces-Fläche berechnen mit den Flächenberechnungen 
	-- aus der parking_segments_ad_130324 tabelle

-- Datenformat von parking_segments_ad_130324 character varying statt integer
-- deswegen ändern: 

ALTER TABLE parking_segments_ad_130324
ALTER COLUMN plr_id TYPE INTEGER USING plr_id::INTEGER;

-- jetzt die Gesamt on-street parking spaces Fläche in die Spalte "on_street_parking_spaces" einfügen
UPDATE spaces_per_lor_v3
SET on_street_parking_spaces = 
  CASE
    WHEN agg2.total_parking_area IS NULL THEN 0
    ELSE agg2.total_parking_area
  END
FROM (
  SELECT
    plr_id,
    SUM(parking_area) AS total_parking_area
  FROM
    parking_segments_ad_130324
  GROUP BY
    plr_id
) agg2
WHERE spaces_per_lor_v3.plr_id = agg2.plr_id;


---- c. ----
-- off-street parking spaces-Fläche berechnen mit Geometrie 
	-- aus der amenity_parking_parking_surface_ring Tabelle
	-- wenn es keine gibt (NULL) soll es 0 m² werden

UPDATE spaces_per_lor_v3 AS s
SET off_street_parking_spaces = (
    CASE
        WHEN (
            SELECT SUM(ST_Area(ST_Intersection(s.geom, a.geom)))
            FROM "amenity_parking_parking_surface_ring" AS a
            WHERE ST_Intersects(s.geom, a.geom)
        ) IS NULL THEN 0
        ELSE (
            SELECT SUM(ST_Area(ST_Intersection(s.geom, a.geom)))
            FROM "amenity_parking_parking_surface_ring" AS a
            WHERE ST_Intersects(s.geom, a.geom)
        )
    END
);


-------------- 3) Summing up traffic areas depending on conversion Option 1,2,3

---- a. ----
-- Conversion Option 1: Maximum

UPDATE spaces_per_lor_v3
SET max_decision_option = roadway_area 
	+ on_street_parking_spaces 
	+ off_street_parking_spaces;

---- b. ----
-- Conversion Option 2: Mixed
	-- roadway area -> mod
	-- on-street parking spaces -> mod
	-- off-street parking spaces -> max
	
UPDATE spaces_per_lor_v3
SET mix_decision_option = (roadway_area * 0.71)
	+ (on_street_parking_spaces * 0.71)
	+ off_street_parking_spaces;


---- c. ----
-- Conversion Option 3: Moderate

UPDATE spaces_per_lor_v3
SET mod_decision_option = (roadway_area * 0.71)
	+ (on_street_parking_spaces * 0.71)
	+ (off_street_parking_spaces * 0.71);



-------------- 4) Assign Built-up and inhabited area to planning areas

---- a. ----
-- Vorbereitung

-- Datensatz: Flächennutzung von 2021 (Reale Nutzung (Umweltatlas)):
SELECT DISTINCT nutzung
FROM flaechennutzung_2021_ring;
-- 19 Nutzungen:
-- Verkehrsfläche (ohne Straßen)
-- Park / Grünfläche
-- Brachfläche, Mischbestand aus Wiesen, Gebüschen und Bäumen
-- Fiedhof
-- Brachfläche, vegetationsfrei
-- Wald
-- Sportnutzung
-- Gewerbe und Industrienutzung, großflächiger Einzelnhandel
-- Wohnnutzung
-- Kerngebietsnutzung
-- Gemeinbedarfs- und Sondernutzung
-- Ver- und Entsorgung
-- Brachfläche, wiesenartiger Vegetationsbestand
-- Baumschule / Gartenbau
-- Kleingartenanlage
-- Mischnutzung
-- Baustelle
-- Stadtplatz / Promenade
-- Gewässer


-- "Baulich geprägte Siedlungs- und Verkehrsfläche" (ohne Siedlungsfreiflächen) definiere ich nach IÖR (n.d) (https://www.ioer-monitor.de/methodik/#c239)
	-- als: 
	-- Verkehrsfläche (ohne Straßen)
	-- Wohnnutzung [in Quelle genannt: Wohnbau]
	-- Mischnutzung
	-- Gemeinbedarfs- und Sondernutzung [Bes. funktionale Prägung]
	-- Ver- und Entsorgung [Bes. funktionale Prägung]
	-- Kerngebietsnutzung [Bes. funktionale Prägung]
	-- Gewerbe und Industrienutzung, großflächiger Einzelhandel [Industrie- und Gewerbe]
-- 7 Nutzungen ^^


-- neue Tabelle für diese 7 Nutzungen --> Baulich gesprägte Siedlungs- und Verkehrsfläche
CREATE TABLE bebaut_siedlung_verkehr AS
SELECT *
FROM flaechennutzung_2021_ring
WHERE nutzung IN (
    'Verkehrsfläche (ohne Straßen)',
    'Wohnnutzung',
    'Mischnutzung',
    'Gemeinbedarfs- und Sondernutzung',
    'Ver- und Entsorgung',
    'Kerngebietsnutzung',
    'Gewerbe- und Industrienutzung, großflächiger Einzelhandel'
);


---- b. ----

-- bebaute Fläche je nach PLR in die spaces_per_lor_v3 einfügen
-- (teilweise überlappen nutzungsflächen mehrere planungsräume - deswegen anteilig zu den planungsräumen zuweisen


-- 1: flächenanteile berechnen der planungsraum-übergreifende nutzungsflächen
CREATE TEMP TABLE temp_flaechen_anteile AS
SELECT 
    prm.plr_id,
    prm.plr_name,
    ST_Area(nt.geom) AS original_area,
    ST_Area(ST_Intersection(nt.geom, prm.geom)) AS intersection_area,
    (ST_Area(ST_Intersection(nt.geom, prm.geom)) / ST_Area(nt.geom)) * ST_Area(nt.geom) AS weighted_area
FROM 
    bebaut_siedlung_verkehr nt
JOIN 
    plr_ring_modi prm 
ON 
    ST_Intersects(nt.geom, prm.geom);

-- 2: Aggregation der Flächenanteile pro plr_id
CREATE TEMP TABLE aggregated_flaechen_anteile AS
SELECT 
    plr_id,
    SUM(weighted_area) AS total_area_per_plr_id
FROM 
    temp_flaechen_anteile
GROUP BY 
    plr_id;

-- 3: bebaute Fläche mit den berechneten Flächenanteilen in spaces_per_lor_v3 einfügen
UPDATE 
    spaces_per_lor_v3 sp
SET 
    bebaut_area = COALESCE(af.total_area_per_plr_id, 0)
FROM 
    aggregated_flaechen_anteile af
WHERE 
    sp.plr_id = af.plr_id;


-- Überprüfung: 
SELECT * FROM spaces_per_lor_v3 WHERE plr_name = 'Christburger Straße';
-- plr_area: 232 706 m²
-- bebaut_area: 177 308 m²
-- in QGIS nachgemessen. Sieht gut aus!


---- c. ----

-- bewohnte Fläche je nach PLR in die spaces_per_lor_v3 einfügen

-- "Bewohnte Fläche" definiere ich nach IÖR (n.d.) (https://www.ioer-monitor.de/methodik/#c239)
	-- als:
	-- Wohnnutzung [Wohnbau]
	-- Mischnutzung
	
-- neue Tabelle für diese 2 Nutzungen
CREATE TABLE bewohnte_flaeche AS
SELECT *
FROM flaechennutzung_2021_ring
WHERE nutzung IN (
    'Wohnnutzung',
    'Mischnutzung'
);


---- d. ----

-- jetzt bewohnte Fläche je nach PLR (teilweise anteilig)
-- in die spaces_per_lor_v2 einfügen

-- 1: flächenanteile berechnen der planungsraum-übergreifende nutzungsflächen
CREATE TEMP TABLE temp_flaechen_anteile_bw AS
SELECT 
    prm.plr_id,
    prm.plr_name,
    ST_Area(nt.geom) AS original_area,
    ST_Area(ST_Intersection(nt.geom, prm.geom)) AS intersection_area,
    (ST_Area(ST_Intersection(nt.geom, prm.geom)) / ST_Area(nt.geom)) * ST_Area(nt.geom) AS weighted_area
FROM 
    bewohnte_flaeche nt
JOIN 
    plr_ring_modi prm 
ON 
    ST_Intersects(nt.geom, prm.geom);

-- 2: Aggregation der Flächenanteile pro plr_id
CREATE TEMP TABLE aggregated_flaechen_anteile_bw AS
SELECT 
    plr_id,
    SUM(weighted_area) AS total_area_per_plr_id
FROM 
    temp_flaechen_anteile_bw
GROUP BY 
    plr_id;

-- 3: bebaute Fläche mit den berechneten Flächenanteilen in spaces_per_lor_v3 einfügen
UPDATE 
    spaces_per_lor_v3 sp
SET 
    bewohnt_area = COALESCE(afbw.total_area_per_plr_id, 0)
FROM 
    aggregated_flaechen_anteile_bw afbw
WHERE 
    sp.plr_id = afbw.plr_id;



-------------- 5) Divide traffic areas by built-up area

-- für results chapter 3 (Appendix)
-- decision options (1,2,3) relativ zur bebauten Fläche

UPDATE spaces_per_lor_v3
SET max_d_o_per_bebaut = max_decision_option / bebaut_area,
    mix_d_o_per_bebaut = mix_decision_option / bebaut_area,
    mod_d_o_per_bebaut = mod_decision_option / bebaut_area;



-------------- 6) Calculate proportion of inhabited area per built-up area

-- für results chapter 3 (table) 
-- Berechnen des prozentualen Anteil der "bewohnt_area" an der "bebaut_area"

UPDATE spaces_per_lor_v3
SET share_bewohnt_an_bebaut = (bewohnt_area / bebaut_area) * 100;



-------------- 7) Assign green space provision categories to planning areas in "spaces_per_lor_v3"

-- für results chapter 3
-- env. jusitce indicator green space provision einfügen


-- plr_id in parking_segments Tabelle zu integer ändern
ALTER TABLE umweltgerech_gruenversorgung_2021_2022
ALTER COLUMN plr TYPE INTEGER USING plr::INTEGER;


-- aus Umweltgerechigkeitskarte Grünversorgung 2021_2022 die Kategorien "gut", "mittel", "schlecht" einfügen

UPDATE spaces_per_lor_v3
SET gruenver_text = umweltgerech_gruenversorgung_2021_2022.kategorie
FROM umweltgerech_gruenversorgung_2021_2022
WHERE spaces_per_lor_v3.plr_id = umweltgerech_gruenversorgung_2021_2022.plr
AND umweltgerech_gruenversorgung_2021_2022.plr IN (SELECT plr_id FROM spaces_per_lor_v3);


-- numerische Spalte für Grünversorgung einfügen für die Ploterstellung

UPDATE spaces_per_lor_v3
SET gruenver_numeric = CASE
                    WHEN gruenver_text = 'gut' THEN 1
                    WHEN gruenver_text = 'mittel' THEN 2
                    WHEN gruenver_text = 'schlecht' THEN 3
                END;



-------------- 8) Save "spaces_per_lor_v3" as csv for plotting in R

----- als csv speichern, um es in RStudio laden zu können

COPY spaces_per_lor_v3 TO 'C:\Dokumente\MASTER_GEO\Master Thesis\Results_pgAdmin\FINAL\spaces_per_lor_v3.csv ' DELIMITER ',' CSV HEADER;



-------------- 9) Create table with all values for results 3 table

-- für results chapter 3 erstelle ich eine Tabelle mit allen Werten aus dem Plot, 
	-- die im 95 Percentil liegen
	-- und den Werten die evtl. für die Bennenung der 
	-- Verkehrsflächen-umwandlungs-potenziale interessant wären

-- Erstelle eine neue Tabelle für die gewünschten Werte
CREATE TABLE table_results3 AS
SELECT 
    plr_name,
	plr_id,
    gruenver_text,
    max_d_o_per_bebaut,
    mix_d_o_per_bebaut,
    mod_d_o_per_bebaut,
    max_decision_option,
    mix_decision_option,
    mod_decision_option,
    share_bewohnt_an_bebaut,
	geom,
	plr_area
FROM spaces_per_lor_v3
WHERE plr_name IN (
    'Großer Tiergarten',
    'Thälmannpark',
    'Alexanderplatzviertel',
    'Volkspark (Rudolph-Wilde-Park)',
    'Schloßstraße',
    'Julius-Leber-Brücke',
    'Stülerstraße',
    'Droysenstraße',
    'Hausburgviertel'
)
ORDER BY CASE plr_name
    WHEN 'Großer Tiergarten' THEN 1
    WHEN 'Thälmannpark' THEN 2
    WHEN 'Alexanderplatzviertel' THEN 3
    WHEN 'Volkspark (Rudolph-Wilde-Park)' THEN 4
    WHEN 'Schloßstraße' THEN 5
    WHEN 'Julius-Leber-Brücke' THEN 6
    WHEN 'Stülerstraße' THEN 7
    WHEN 'Droysenstraße' THEN 8
    WHEN 'Hausburgviertel' THEN 9
    ELSE 10  -- Dieser Fall sollte nicht eintreten, aber ist als Fallback enthalten.
END;

SELECT * FROM table_results3;

COPY table_results3 TO 'C:\Dokumente\MASTER_GEO\Master Thesis\Results_pgAdmin\FINAL\table_results3.csv ' DELIMITER ',' CSV HEADER;
