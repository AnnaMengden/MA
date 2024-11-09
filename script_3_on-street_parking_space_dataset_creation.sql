
--------------------- SCRIPT 3 -------------------------
---------- 17.03.2024 ----- by Anna Mengden ------------
----- creation of on-street parking space dataset ------


	-- Basisdaten-Name: "parking_segments_ring_141023_crs25833" --> downloaded here: https://parkraum.osm-verkehrswende.org/regions/berlin/ und in QGIS re-projiziert.
	-- Ziel: neue Tabelle erstellen mit "added data" = "ad" --> Tabellenname = parking_segments_ad_130324


------------------------------------------------------------------------------
---- Order of the following script:

-- 1) How much % of the parking segments are missing information
	-- Result: 27.54%

-- 2) Creating table "parking_segments_ad_130324" and adding length and width
	-- depending on the length and width of the existing data per road type

-- 3) Data modification 
	-- (clipping to planning area layer; data cleanding)

-- 4) Parking area calculation

-- 5) Total sum of on-street parking spaces
------------------------------------------------------------------------------



------------------------------------------------------------------------------
-------------- 1) HOW MUCH % OF PARKING SEGMENTS ARE MISSING INFORMATION
------------------------------------------------------------------------------


----zu erst: ----
-- Wie viel Prozent der OSM-Project Daten im S-Bahn Ring fehlen? 
	-- also "data_missing"
SELECT 
    COUNT(*) * 100.0 / (SELECT COUNT(*) FROM parking_segments_ring_141023_crs25833) AS percentage_missing_data
FROM parking_segments_ring_141023_crs25833
WHERE capacity_s IN ('data_missing');

-- Ergebnis: 6 %

	-- not_processed_yet heißt, dass sie in OSM als separate Parkplatzflächen kartiert sind und noch nicht im parking_segments-Datensatz
	-- also fehlt quasi auch "not_processed_yet"
	
SELECT 
    COUNT(*) * 100.0 / (SELECT COUNT(*) FROM parking_segments_ring_141023_crs25833) AS percentage_missing_data
FROM parking_segments_ring_141023_crs25833
WHERE capacity_s IN ('not_processed_yet');
-- 21.5% 

	-- zusammengenommen fehlen erstmal:
SELECT 
    COUNT(*) * 100.0 / (SELECT COUNT(*) FROM parking_segments_ring_141023_crs25833) AS percentage_missing_data
FROM parking_segments_ring_141023_crs25833
WHERE capacity_s IN ('data_missing' , 'not_processed_yet');
----- Ergebnis: 27.54% -------

------(einige not_processed_yet Werte sind noch drin, obwohl es schon eine zugehörigen
------"processed" Wert gibt. - das kommt später!)




------------------------------------------------------------------------------
-------------- 2) CREATING NEW TABLE AND ADDING LENGTH AND WIDTH
------------------------------------------------------------------------------


---- DATA PRE-PROCESSING ----

	-- Tabelle ohne "data_missing" (DM) und "not_processed_yet" (NPY) von capacity_status erstellen
		-- damit code nicht so lang, wenn ich die anderen capacity statuses (capacity_s) 
		-- bei denen die Daten vollständig sind, ansprechen will.

CREATE TABLE parking_segments_ring_141023_without_dm_npy AS
SELECT *
FROM parking_segments_ring_141023_crs25833
WHERE capacity_s <> 'data_missing' AND capacity_s <> 'not_processed_yet';

	-- length in length_osm umbenennen, weil "length" Sondername in postgres
ALTER TABLE parking_segments_ring_141023_crs25833
RENAME COLUMN length TO length_osm;

	-- auch bei Tabelle ohne data missing und not processed yet
ALTER TABLE parking_segments_ring_141023_without_dm_npy
RENAME COLUMN length TO length_osm;


---- DATEN-GENERIERUNG ----

-- 1.) Neue Tabelle erstellen mit den Werten von parking_segments_ring_141023_crs25833
	-- = "parking_segments_ad_130324"
-- und 2.) Spalte hinzufügen zu wie viel Prozent abhängig vom Straßentyp bei den Segmenten
-- geparkt wird ('nicht no parking'). Dies wird von den existierenden Daten berechnet und für die
-- fehlenden eingefügt.
	-- Spaltenname = parking_percentage
	-- heißt: auf x % wird durchschnittlichen aufgrund ihres Straßentyps geparkt.
	
CREATE TABLE parking_segments_ad_130324 AS
SELECT p1.*,
       CASE
           WHEN p1.capacity_s IN ('data_missing', 'not_processed_yet') THEN p2.percentage
           ELSE NULL
       END AS parking_percentage
FROM parking_segments_ring_141023_crs25833 AS p1
LEFT JOIN (
 SELECT highway,
	(COUNT(*) FILTER (WHERE capacity_s <> 'no_parking') * 100.0 / COUNT(*)) AS percentage
 FROM parking_segments_ring_141023_without_dm_npy
 GROUP BY highway
) AS p2
ON p1.highway = p2.highway;	

-- um table in QGIS laden zu können, muss ein primary key defined werden
ALTER TABLE parking_segments_ad_130324
ADD PRIMARY KEY (id);

-- 3.) der Prozentsatz wird nun auf die Segmentlängen (length_osm) angewendet.
	-- Es wird also eine Länge berechnet, auf der, wegen ihres Straßentyps wahrscheinlich
	-- geparkt wird. 
	-- (dort wo "percentage" NULL ist, weil ich das ja nicht für die existierenden 
	-- Daten berechnen wollte und habe, wird nach dieser Berechnung auch NULL stehen.)
	
ALTER TABLE parking_segments_ad_130324
ADD COLUMN estimated_parking_length numeric;

UPDATE parking_segments_ad_130324
SET estimated_parking_length = length_osm::numeric * (parking_percentage / 100.0);


-- 4.) Spalten erstellen, für die Prozentsätze von 4.1) parallel, 4.2) perpendicular, oder
	-- 4.3) diagonal parken und 4.4) ob überhaupt geparkt wird.

-- 4.1) Spalte für parallel parken erstellen

ALTER TABLE parking_segments_ad_130324
ADD COLUMN percentage_parallel numeric;

UPDATE parking_segments_ad_130324 AS p1
SET percentage_parallel = p2.percentage
FROM (
    SELECT p1.id, 
        CASE 
            WHEN p1.capacity_s IN ('data_missing', 'not_processed_yet') THEN p2.percentage 
            ELSE NULL 
        END AS percentage
    FROM parking_segments_ad_130324 AS p1
    LEFT JOIN (
        SELECT highway,
            (COUNT(*) FILTER (WHERE orientatio = 'parallel') * 100.0 / COUNT(*)) AS percentage
        FROM parking_segments_ring_141023_without_dm_npy
        GROUP BY highway
    ) AS p2 ON p1.highway = p2.highway
) AS p2
WHERE p1.id = p2.id;


-- 4.2) Spalte für perpendicular parken erstellen

ALTER TABLE parking_segments_ad_130324
ADD COLUMN percentage_perpendicular numeric;

UPDATE parking_segments_ad_130324 AS p1
SET percentage_perpendicular = p2.percentage
FROM (
    SELECT p1.id, 
        CASE 
            WHEN p1.capacity_s IN ('data_missing', 'not_processed_yet') THEN p2.percentage 
            ELSE NULL 
        END AS percentage
    FROM parking_segments_ad_130324 AS p1
    LEFT JOIN (
        SELECT highway,
            (COUNT(*) FILTER (WHERE orientatio = 'perpendicular') * 100.0 / COUNT(*)) AS percentage
        FROM parking_segments_ring_141023_without_dm_npy
        GROUP BY highway
    ) AS p2 ON p1.highway = p2.highway
) AS p2
WHERE p1.id = p2.id;



-- 4.3) Spalte für diagonal parken erstellen

ALTER TABLE parking_segments_ad_130324
ADD COLUMN percentage_diagonal numeric;

UPDATE parking_segments_ad_130324 AS p1
SET percentage_diagonal = p2.percentage
FROM (
    SELECT p1.id, 
        CASE 
            WHEN p1.capacity_s IN ('data_missing', 'not_processed_yet') THEN p2.percentage 
            ELSE NULL 
        END AS percentage
    FROM parking_segments_ad_130324 AS p1
    LEFT JOIN (
        SELECT highway,
            (COUNT(*) FILTER (WHERE orientatio = 'diagonal') * 100.0 / COUNT(*)) AS percentage
        FROM parking_segments_ring_141023_without_dm_npy
        GROUP BY highway
    ) AS p2 ON p1.highway = p2.highway
) AS p2
WHERE p1.id = p2.id;


-- 4.4) zu wie viel Prozent wird auf den Segmenten nicht geparkt 
	-- Spalte: "percentage_no_parking"

ALTER TABLE parking_segments_ad_130324
ADD COLUMN percentage_no_parking numeric;

UPDATE parking_segments_ad_130324 AS p1
SET percentage_no_parking = p2.percentage
FROM (
    SELECT p1.id, 
        CASE 
            WHEN p1.capacity_s IN ('data_missing', 'not_processed_yet') THEN p2.percentage 
            ELSE NULL 
        END AS percentage
    FROM parking_segments_ad_130324 AS p1
    LEFT JOIN (
        SELECT highway,
            (COUNT(*) FILTER (WHERE capacity_s = 'no_parking') * 100.0 / COUNT(*)) AS percentage
        FROM parking_segments_ring_141023_without_dm_npy
        GROUP BY highway
    ) AS p2 ON p1.highway = p2.highway
) AS p2
WHERE p1.id = p2.id;



-- 5) Prozentsätze von 4.1), 4.2) und 4.3) auf Längen anwenden
-- 5.1) Länge auf der durchschnittlich parallel geparkt wird, um wahrscheinliche Parkplatzflächen berechnen zu können
	-- Spaltenname "parallel_parking_length"
	
ALTER TABLE parking_segments_ad_130324
ADD COLUMN parallel_parking_length numeric;

UPDATE parking_segments_ad_130324
SET parallel_parking_length = (length_osm * percentage_parallel / 100.0)
WHERE capacity_s IN ('data_missing', 'not_processed_yet');


-- 5.2) Länge auf der durchschnittlich perpendicular geparkt wird
	-- Spaltenname "perpendicular_parking_length"
	
ALTER TABLE parking_segments_ad_130324
ADD COLUMN perpendicular_parking_length numeric;

UPDATE parking_segments_ad_130324
SET perpendicular_parking_length = (length_osm * percentage_perpendicular / 100.0)
WHERE capacity_s IN ('data_missing', 'not_processed_yet');


-- 5.3) Länge auf der durchschnittlich diagonal geparkt wird
	-- Spaltenname "diagonal_parking_length"

ALTER TABLE parking_segments_ad_130324
ADD COLUMN diagonal_parking_length numeric;

UPDATE parking_segments_ad_130324
SET diagonal_parking_length = (length_osm * percentage_diagonal / 100.0)
WHERE capacity_s IN ('data_missing', 'not_processed_yet');


-- 5.4) Länge auf der nicht geparkt werden kann
	-- spaltenname "no_parking_length"
ALTER TABLE parking_segments_ad_130324
ADD COLUMN no_parking_length numeric;

UPDATE parking_segments_ad_130324
SET no_parking_length = (length_osm * percentage_no_parking / 100.0)
WHERE capacity_s IN ('data_missing', 'not_processed_yet');


-------------test ob das mit den Längen passt:----------------------------------------
-- Dafür ein Segment nehmen (id = 385213)
-- und die Längen zusammenrechnen 

SELECT parallel_parking_length
FROM parking_segments_ad_130324
WHERE id = '385213';
-- 2.67 m.
SELECT perpendicular_parking_length
FROM parking_segments_ad_130324
WHERE id = '385213';
-- 0.57 m
SELECT diagonal_parking_length
FROM parking_segments_ad_130324
WHERE id = '385213';
-- 0.07 m 
SELECT no_parking_length
FROM parking_segments_ad_130324
WHERE id = '385213';
-- 2.799 m 
-- 2.799 + 0.07 + 0.57 + 2.67 = 6.109 m ---------> 6.2 m length_osm ??????

SELECT length_osm
FROM parking_segments_ad_130324
WHERE id = '385213';
-- 6.2 m
-- also: ja! 
-------------------------------------------------------------------------



------------------------------------------------------------------------------
-------------- 3) DATA MODIFICATION
------------------------------------------------------------------------------

----- ZUSCHNEIDEN DER DATEN AUF DIE LORS IM RING ----------

--- 1. PLRs in parking_segments Tabelle hinzufügen
	-- lor id und name zur visualisierung
	-- (character varying weil das bei LOR Datensatz auch so ist. muss für den Abgleich gleicher Datentyp sein)

ALTER TABLE parking_segments_ad_130324
ADD COLUMN plr_id character varying;

UPDATE parking_segments_ad_130324
SET plr_id = CAST(plr_ring_modi.plr_id AS character varying)
FROM plr_ring_modi
WHERE ST_Intersects(parking_segments_ad_130324.geom, plr_ring_modi.geom);
-- Dauert: 45 sek

ALTER TABLE parking_segments_ad_130324
ADD COLUMN plr_name text;

UPDATE parking_segments_ad_130324
SET plr_name = CAST(plr_ring_modi.plr_name AS TEXT)
FROM plr_ring_modi
WHERE ST_Intersects(parking_segments_ad_130324.geom, plr_ring_modi.geom);
-- dauert: 45 sek


-- 2. "ZUSCHNEIDEN" AUF DIE RICHTIGEN LORs
-- Löschen der Werte, die keinen plr_id oder plr_name haben von grade ^^ haben

DELETE FROM parking_segments_ad_130324
WHERE plr_id IS NULL AND plr_name IS NULL;

-- delete 65


----- DATA CLEANING ------


---- 1. Die "width" fehlt bei manchen "processed" data (bzw. hier 0 meter breite, obwohl das keinen Sinn ergibt). 
	-- dafür steht dort aber meistens die Park-Ausrichtung: 

	SELECT *
	FROM parking_segments_ad_130324
	WHERE capacity_s = 'processed' 
	 AND width = 0
 	 AND (orientatio = 'parallel' 
  	     OR orientatio = 'diagonal' 
      	     OR orientatio = 'perpendicular');
	-- 3504 mal gibt es eine Parkausrichtung

	SELECT *
	FROM parking_segments_ad_130324
	WHERE capacity_s = 'processed'
	  AND width = 0
	  AND (orientatio IS NULL OR orientatio = '');
	-- 459 gibt es keine Parkausrichtung ----------------------------------- SIND DAS DIE DIE NOCH NPY SEGMENTE "HABEN"?!?!?!

-- Deswegen: width_modified erstellen (damit die alte noch vorhanden ist)
	-- für die processed Values ohne width und mit Parkausrichtung (orientation)
	-- für alle anderen Werte, width übernehmen
	
ALTER TABLE parking_segments_ad_130324
ADD COLUMN width_modified numeric;

UPDATE parking_segments_ad_130324
SET width_modified =
    CASE
        WHEN capacity_s = 'processed' AND width = 0 AND orientatio = 'parallel' THEN 2
        WHEN capacity_s = 'processed' AND width = 0 AND orientatio = 'perpendicular' THEN 5
        WHEN capacity_s = 'processed' AND width = 0 AND orientatio = 'diagonal' THEN 4.5
        WHEN capacity_s = 'processed' AND width = 0 AND orientatio IS NULL THEN 2
        ELSE width
    END;




-- 2. Fehler in original parking segments gefunden: 
	-- bei einigen "not_processed_yet" Segmenten, gibt es eigentlich schon richtige "processed" Segmente.
-- Deswegen: Einige davon aus der Flächenberechnung "entfernen", also, dass sie nicht gezählt werden.

-- Idee:
	-- Neue Spalte "capacity_s_2" erstellen (damit die alte noch vorhanden ist) 
	-- capacity_s_2 NULL setzen, wenn capacity_s = "not_processed_yet" und einen (3 m) Puffer von einem 
	-- Wert mit capacity_s = "processed" und source_c_1 = "OSM" schneidet/berührt. 

ALTER TABLE parking_segments_ad_130324
ADD COLUMN capacity_s_2 character varying;

UPDATE parking_segments_ad_130324
SET capacity_s_2 = 
    CASE 
        WHEN capacity_s = 'not_processed_yet' AND EXISTS (
            SELECT 1
            FROM parking_segments_ad_130324 p
            WHERE p.capacity_s = 'processed'
                AND p.source_c_1 = 'OSM'
                AND ST_Intersects(ST_Buffer(parking_segments_ad_130324.geom, 3.0), ST_Buffer(p.geom, 3.0))
        ) THEN NULL
        ELSE capacity_s
    END;

-- Dauer: 42 minuten

-- (hatte eine Stelle gefunden, wo der Abstand bei einer sonst stimmenden Bedingung mit einem 2 meter Buffer zu groß ist. Deswegen 3.0 (meter) buffern)

-- übrigens: mit der zusätzlichen Bedigung, dass source_c_1 = OSM sein soll, vermeide ich teilweise, 
-- dass nahe liegende (im 3 m Buffer) processed Segmente fälschlicherweise NULL werden.


-- deswegen auch width_modified anpassen für die data_missing und die not_processed_yet, 
	-- die nicht fälschlicherweise noch drin sind (sie haben keinen processed Segment daneben)

UPDATE parking_segments_ad_130324
SET width_modified = (percentage_no_parking * 0) + (percentage_parallel * 2) + (percentage_diagonal * 4.5) + (percentage_perpendicular * 5)
WHERE (capacity_s = 'data_missing') OR (capacity_s = 'not_processed_yet' AND capacity_s_2 IS NOT NULL);


----------x--------------x--------------x--------------x------------x---------x
-----kurz zwischendurch:
-- ganz am Anfang hab ich gesagt 21,6% der Daten sind "not_processed_yet"
-- nach der modification sind es noch:

SELECT 
    COUNT(*) * 100.0 / (SELECT COUNT(*) FROM parking_segments_ad_130324) AS percentage_missing_data
FROM parking_segments_ad_130324
WHERE capacity_s_2 IN ('not_processed_yet');

-- Ergbenis: 6,4%
-- das heißt es "fehlen" tatsächlich "nur" : 
	-- 6% (data_missing) + Ergebnis^^ = 12,4%
------------x--------------x---------------x-----------x----------------x-------



------------------------------------------------------------------------------
-------------- 4) PARKING AREA CALCULATION
------------------------------------------------------------------------------


------- DATA GENERATION WEITER ----------

-- 6.) Parking-Fläche berechnen für die "data_missing" (dm) und "not_processed_yet" (npy)
	-- neue Spalte mit parking_area erstellen 
	-- in der "parallel_length" * 2 + "perpendicular_length" * 5 + "diagonal_length" * 4,5 
	-- 2, 5 und 4,5 sind die Parkplatzbreiten (meter) je nach Parkausrichtung (von Parkraum-Projekt genommen)
	-- die, die in data-modification (1) ausgeschlossen wurden werden mit "WHERE capacity_s_2 IS NOT NULL" ausgeschlossen
		-- weil wenn capacity_s_2 IS NULL, dann sollen sie nicht beachtet werden, weil es hier schon "processed" werte gibt. 
	
ALTER TABLE parking_segments_ad_130324
ADD COLUMN parking_area_dm_npy numeric;

UPDATE parking_segments_ad_130324
SET parking_area_dm_npy = (parallel_parking_length * 2) + (perpendicular_parking_length * 5) + (diagonal_parking_length * 4.5)
WHERE capacity_s_2 IS NOT NULL;


-- 7.) Parking-Fläche berechnen für die bereits existierenden Daten ("processed", "other", "segments_too_small" [da es in meinem Fall egal ist, ob segment too small ist])
	-- = length_osm * width_modified

ALTER TABLE parking_segments_ad_130324
ADD COLUMN parking_area_existing_data numeric;

UPDATE parking_segments_ad_130324
SET parking_area_existing_data = (width_modified * length_osm);


-- 8.) Beide Flächendaten in einer Spalte zusammenführen
-- Neue Spalte "parking_area" hinzufügen

ALTER TABLE parking_segments_ad_130324
ADD COLUMN parking_area numeric; 

-- Werte von der parking area von data_missing und not_processed_yet und die parking area von den andern zusammenführen
-- für eine Flächen-Spalte der ganzen Daten

UPDATE parking_segments_ad_130324
SET parking_area = 
    COALESCE(parking_area_dm_npy, parking_area_existing_data);


-------------- 5) TOTAL SUM OF ON-STREET PARKING SPACES

-- Gesamt-Straßenparkplatzfläche im Ring:

SELECT SUM(parking_area) AS total_parking_area
FROM parking_segments_ad_130324;

-- Ergebnis: 2.794.890m² = 279,48 ha (kartiert in OSM-Parkraum-Projekt und selbst vervollständigt siehe oben)



------------ DARSTELLUNG IN QGIS (pro Planungsraum (PLR))------------------

-- spaces_per_lor_v3 -> Spalte "on_street_parking_spaces"