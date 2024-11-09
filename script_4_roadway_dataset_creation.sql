
--------------------- SCRIPT 4 -------------------------
---------- 25.03.2024 ----- by Anna Mengden ------------
---------- creation of roadway dataset -----------------

-- Final dataset name: "merged_highways_1_to_7_final"

----- (1) Einzelne Straßentypen über
----- QuickOSM in QGIS herunterladen
----- key = highway, Value = primary, secondary, etc.
----- mit CRS 25833 und weniger Spalten exportieren
----- gespeichert als "highway_primary_ring" und so weiter je nach Straßentyp


-----------------------------------------------------------------------------
---- Order of the following script: ----

-- 1) Assign roadway widths to road types (road type by road type)

-- 2) Buffer and dissolve datasets per road type

-- 3) Merging road types hierarchically

-- 4) Roadway area calculation
-----------------------------------------------------------------------------



------------------------------------------------------------------------------
-------------- 1) ASSIGN ROADWAY WIDTH TO ROAD TYPES (ROAD TYPE BY ROAD TYPE)
------------------------------------------------------------------------------


-------- (2) Den Straßentypen ihre Fahrbahnbreiten ---------------
-------- (von parking_segments Dataset) zuweisen -----------------

------zu erst:------
--  bei parking_segments sind die osm_ids noch mit 0000 dahinter,
-- ich behebe das indem ich die osm_id Spalte von parking_segments_ad_130324 zu INTEGER ändere (ein Datentyp mit ganzen Zahlen) 
-- deswegen: datatyp von osm_id von highway Daten ändern zu Integer, weil das in parking_segments so ist


---------- 2.1) Primary

ALTER TABLE highway_primary_ring
ALTER COLUMN osm_id TYPE INTEGER
USING osm_id::INTEGER;

-- Kopie des primary layers erstellen

CREATE TABLE highway_primary_ring_width AS
SELECT * FROM highway_primary_ring;

-- 1. Hinzufügen der Spalte highway__1_missing für die osm_ids die keine Fahrbahnbreite bekommen können
	-- weil es es hier keine parking segments gibt (z.B. bei Kreuzungen)

ALTER TABLE highway_primary_ring_width
ADD COLUMN highway__1_missing DECIMAL;


-- 2. Aktualisieren der Spalte highway__1_missing mit "9999" für die osm_ids, die 
-- zwar in den primary highways vorhanden sind aber nicht bei parking segments
	-- damit ich sie dann leicht ansprechen kann

UPDATE highway_primary_ring_width rh
SET highway__1_missing = '9999'
WHERE NOT EXISTS (
    SELECT 1
    FROM parking_segments_ad_130324 ps
    WHERE rh.osm_id = ps.osm_id
);
-- 271


-- 3. Hinzufügen der Spalte highway__1 
	-- (normale (effektive) Fahrbahnbreite die in parking_segments vorhanden ist)

ALTER TABLE highway_primary_ring_width
ADD COLUMN highway__1 DECIMAL;


-- 4. Aktualisieren der Spalte highway__1 mit den Werten aus parking_segments

UPDATE highway_primary_ring_width rh
SET highway__1 = ps.highway__1
FROM parking_segments_ad_130324 ps
WHERE rh.osm_id = ps.osm_id;
-- UPDATE 1256

-- 5. Die Spalte effektive Fahrbahnbreite (highway__1) soll modifiziert werden, weil 
	-- sie teilweise NICHT Fahrbahnbreite (highway_wi) minus Parkplatzbreite (width) ist,
	-- was es aber sein soll
-- (hier neuer Teil (vom 13.09.): wenn die effektive fahrbahnbreite gleich der fahrbahnbreite ist, 
				-- dann die modified on-street Parkplatzbreite (width_modified)
				-- von der highway_wi (normale Fahrbahnbreite) abziehen. 

ALTER TABLE highway_primary_ring_width 
ADD COLUMN highway__1_modif DECIMAL;

UPDATE highway_primary_ring_width AS h
SET highway__1_modif = CASE
    WHEN ps.highway__1 = ps.highway_wi THEN ps.highway_wi - ps.width_modified
    ELSE h.highway__1
END
FROM parking_segments_ad_130324 AS ps
WHERE h.osm_id = ps.osm_id;
-- UPDATE 1256


-- 6. highway__1_missing wird aufgefüllt basierend auf der nächstgelegenen Geometrie,
	-- wenn hier ein highway__1 Wert ist (IS NOT NULL)

UPDATE highway_primary_ring_width rh
SET highway__1_missing = (
    SELECT rh2.highway__1_modif
    FROM highway_primary_ring_width rh2
    WHERE rh2.highway__1_modif IS NOT NULL
    ORDER BY rh.geom <-> rh2.geom
    LIMIT 1
)
WHERE highway__1_missing = 9999;
-- 271


-- 7. Erstellen der neuen Spalte highway__1_new 
	-- für die Werte von highway__1 und highway__1_missing zusammen

ALTER TABLE highway_primary_ring_width
ADD COLUMN highway__1_new DECIMAL;

UPDATE highway_primary_ring_width
SET highway__1_new = COALESCE(highway__1_modif, highway__1_missing);
-- 1527



-- 8. highway__1_new modifizieren, 
	-- weil bei fehlenden Daten von parking_segments (datamissing und notprocessedyet)
	-- die effetive Fahrbahnbreite noch der "nicht-effektiven" Fahrbahnbreite entspricht,
	-- obwohl es hier Parkplätze gibt!

ALTER TABLE highway_primary_ring_width
ADD COLUMN highway_wi_effec_final DECIMAL;

-- Berechne die neue Parkplatzbreite für die fehlenden Daten (data_missing & not_processed_yet),
	-- wenn Fahrbahnbreite gleich der effektiven fahrbahnbreite ist,
	-- sie den Standardwert von Alex und Co. bekommen haben muss, weil: width von OSM highway IS NULL,
	-- und sie NICHT den überflüssigen notprocessedyet Daten angehört (capacity_s_2 IS NOT NULL),
-- mit den Parkplatzbreiten aufgrund von Parkausrichtungsprozentsätzen.
-- Ansonsten nehme highway__1_new von der Modification von Punkt 5.

UPDATE highway_primary_ring_width AS h
SET highway_wi_effec_final = CASE
    WHEN h.width IS NULL THEN
        (
            SELECT 
                h.highway__1_new - (
                    SELECT 
                        (2 * (ps.percentage_parallel / 100.0)) +
                        (5 * (ps.percentage_perpendicular / 100.0)) +
                        (4.5 * (ps.percentage_diagonal / 100.0))
                    FROM parking_segments_ad_130324 AS ps
                    WHERE ps.highway = 'primary'
                    AND ps.capacity_s_2 IS NOT NULL
                    AND ps.capacity_s IN ('data_missing', 'not_processed_yet')
                    AND ps.highway_wi = ps.highway__1
                    LIMIT 1
                )
        )
    ELSE
        h.highway__1_new
END;
-- 1527

-- Durchschnitt effektive Fahrbahnbreite
SELECT AVG(highway_wi_effec_final) FROM highway_primary_ring_width;
-- 15.59 m


-- primary key festlegen
ALTER TABLE highway_primary_ring_width
ADD CONSTRAINT id PRIMARY KEY (id);


-- zum anschauen
SELECT * FROM highway_primary_ring_width;

-- data cleaning successful?
SELECT * FROM highway_primary_ring_width WHERE highway_wi_effec_final IS NULL;
SELECT * FROM highway_primary_ring_width WHERE highway_wi_effec_final = 0;
SELECT * FROM highway_primary_ring_width WHERE highway_wi_effec_final < 0;
-- 0 rows affected - yes



----------- 2.2) Secondary 

ALTER TABLE highway_secondary_ring
ALTER COLUMN osm_id TYPE INTEGER
USING osm_id::INTEGER;


CREATE TABLE highway_secondary_ring_width AS
SELECT * FROM highway_secondary_ring;
-- 3427


-- 1. Hinzufügen der Spalte highway__1_missing für die osm_ids die keine Fahrbahnbreite bekommen können
	-- weil es eine Kreuzung ist z.B.

ALTER TABLE highway_secondary_ring_width
ADD COLUMN highway__1_missing DECIMAL;

-- 2. Aktualisieren der Spalte highway__1_missing mit "9999" für die osm_ids, die 
-- zwar in den secondary highways vorhanden sind aber nicht bei parking segments
	-- damit ich sie dann leicht ansprechen kann

UPDATE highway_secondary_ring_width rh
SET highway__1_missing = '9999'
WHERE NOT EXISTS (
    SELECT 1
    FROM parking_segments_ad_130324 ps
    WHERE rh.osm_id = ps.osm_id
);
-- 609

-- 3. Hinzufügen der Spalte highway__1 
	-- (normale (effektive) Fahrbahnbreite die in parking_segments vorhanden ist)

ALTER TABLE highway_secondary_ring_width
ADD COLUMN highway__1 DECIMAL;

UPDATE highway_secondary_ring_width rh
SET highway__1 = ps.highway__1
FROM parking_segments_ad_130324 ps
WHERE rh.osm_id = ps.osm_id;
-- 2817


-- 4. Die Spalte effektive Fahrbahnbreite (highway__1) soll modifiziert werden, weil 
	-- sie teilweise nicht Fahrbahnbreite (highway_wi) minus Parkplatzbreite (width)
	-- was es sein soll

ALTER TABLE highway_secondary_ring_width
ADD COLUMN highway__1_modif DECIMAL;

UPDATE highway_secondary_ring_width AS h
SET highway__1_modif = CASE
    WHEN ps.highway__1 = ps.highway_wi THEN ps.highway_wi - ps.width_modified
    ELSE h.highway__1
END
FROM parking_segments_ad_130324 AS ps
WHERE h.osm_id = ps.osm_id;

-- UPDATE 2817


-- 5. highway__1 noch mal modifien, 
-- weil es eine negative Fahrbahnbreite gibt!
-- Werte von highway__1 in highway__1_modif übertragen und negative Werte korrigieren
UPDATE highway_secondary_ring_width
SET highway__1_modif = CASE 
                            WHEN highway__1 < 0 THEN ABS(highway__1)
                            ELSE highway__1
                        END;
-- UPDATE 3426				


-- 6. highway__1_missing wird nun endlich aufgefüllt basierend auf der nächstgelegenen Geometrie,
	-- wenn hier ein highway__1_modif Wert ist (IS NOT NULL)

UPDATE highway_secondary_ring_width rh
SET highway__1_missing = (
    SELECT rh2.highway__1_modif
    FROM highway_secondary_ring_width rh2
    WHERE rh2.highway__1_modif IS NOT NULL
    ORDER BY rh.geom <-> rh2.geom
    LIMIT 1
)
WHERE highway__1_missing = 9999;
-- 609

-- 7. Erstellen der neuen Spalte highway__1_new 
	-- für die Werte von highway__1_modif und highway__1_missing zusammen

ALTER TABLE highway_secondary_ring_width
ADD COLUMN highway__1_new DECIMAL;

UPDATE highway_secondary_ring_width
SET highway__1_new = COALESCE(highway__1_modif, highway__1_missing);
-- 3426

-- checken dass hier kein highway__1_new NULL ist
SELECT * FROM highway_secondary_ring_width WHERE highway__1_new IS NULL;
-- 0 - yes!


-- 8. highway__1_new modifizieren, 
	-- weil bei fehlenden Daten von parking_segments (datamissing und notprocessedyet)
	-- die effetive Fahrbahnbreite noch der nicht-effektiven Fahrbahnbreite entspricht,
	-- obwohl es hier Parkplätze gibt!

ALTER TABLE highway_secondary_ring_width
ADD COLUMN highway_wi_effec_final DECIMAL;

-- Berechne die neue Parkplatzbreite für die fehlenden Daten (data_missing & not_processed_yet),
	-- wenn fahrbahnbreite gleich der effektiven fahrbahnbreite ist,
	-- sie den Standardwert von Alex und Co. bekommen haben muss, weil: width von OSM highway IS NULL,
	-- und sie NICHT den überflüssigen notprocessedyet Daten angehört (capacity_s_2 IS NOT NULL),
-- mit den Parkplatzbreiten aufgrund von Parkausrichtungsprozentsätzen.
-- Ansonsten nehme highway__1_new von der Modification von Punkt 5.

UPDATE highway_secondary_ring_width AS h
SET highway_wi_effec_final = CASE
    WHEN h.width IS NULL THEN
        (
            SELECT 
                h.highway__1_new - (
                    SELECT 
                        (2 * (ps.percentage_parallel / 100.0)) +
                        (5 * (ps.percentage_perpendicular / 100.0)) +
                        (4.5 * (ps.percentage_diagonal / 100.0))
                    FROM parking_segments_ad_130324 AS ps
                    WHERE ps.highway = 'secondary'
                    AND ps.capacity_s_2 IS NOT NULL
                    AND ps.capacity_s IN ('data_missing', 'not_processed_yet')
                    AND ps.highway_wi = ps.highway__1
                    LIMIT 1
                )
        )
    ELSE
        h.highway__1_new
END;

-- UPDATE 3426

-- Durchschnitt effektive Fahrbahnbreite
SELECT AVG(highway_wi_effec_final) FROM highway_secondary_ring_width;
-- 12.66 m

-- wie immer primary key festlegen
ALTER TABLE highway_secondary_ring_width
ADD PRIMARY KEY (id);

-- zum anschauen und abchecken
SELECT * FROM highway_secondary_ring_width;
-- soll jetzt nix NULL ODER 0 sein
SELECT * FROM highway_secondary_ring_width WHERE highway_wi_effec_final IS NULL;
SELECT * FROM highway_secondary_ring_width WHERE highway_wi_effec_final = 0;
SELECT * FROM highway_secondary_ring_width WHERE highway_wi_effec_final < 0;



----------- 2.3) Tertiary

ALTER TABLE highway_tertiary_ring
ALTER COLUMN osm_id TYPE INTEGER
USING osm_id::INTEGER;


CREATE TABLE highway_tertiary_ring_width AS
SELECT * FROM highway_tertiary_ring;
-- 1838


-- 1. Hinzufügen der Spalte highway__1_missing für die osm_ids die keine Fahrbahnbreite bekommen können
	-- weil es eine Kreuzung ist z.B.

ALTER TABLE highway_tertiary_ring_width
ADD COLUMN highway__1_missing DECIMAL;


-- 2. Aktualisieren der Spalte highway__1_missing mit "9999" für die osm_ids, die 
-- zwar in den secondary highways vorhanden sind aber nicht bei parking segments
	-- damit ich sie dann leicht ansprechen kann

UPDATE highway_tertiary_ring_width rh
SET highway__1_missing = '9999'
WHERE NOT EXISTS (
    SELECT 1
    FROM parking_segments_ad_130324 ps
    WHERE rh.osm_id = ps.osm_id
);
-- 275

-- 3. Hinzufügen der Spalte highway__1 
	-- (normale (effektive) Fahrbahnbreite die in parking_segments vorhanden ist)

ALTER TABLE highway_tertiary_ring_width
ADD COLUMN highway__1 DECIMAL;

UPDATE highway_tertiary_ring_width rh
SET highway__1 = ps.highway__1
FROM parking_segments_ad_130324 ps
WHERE rh.osm_id = ps.osm_id;
-- 1563 


-- 4. Die Spalte effektive Fahrbahnbreite (highway__1) soll modifiziert werden, weil 
	-- sie teilweise nicht Fahrbahnbreite (highway_wi) minus Parkplatzbreite (width)
	-- was es sein soll

ALTER TABLE highway_tertiary_ring_width
ADD COLUMN highway__1_modif DECIMAL;

UPDATE highway_tertiary_ring_width AS h
SET highway__1_modif = CASE
    WHEN ps.highway__1 = ps.highway_wi THEN ps.highway_wi - ps.width_modified
    ELSE h.highway__1
END
FROM parking_segments_ad_130324 AS ps
WHERE h.osm_id = ps.osm_id;

-- UPDATE 1563


-- 5. highway__1 noch mal modifien, 
-- weil es eine negative Fahrbahnbreite gibt!
-- Werte von highway__1 in highway__1_modif übertragen und negative Werte korrigieren

UPDATE highway_tertiary_ring_width
SET highway__1_modif = CASE 
                            WHEN highway__1 < 0 THEN ABS(highway__1)
                            ELSE highway__1
                        END;

-- UPDATE 1838


-- 6. highway__1 noch mal modifying
	-- weil es ein highway__1 = 0 gibt
	-- bei highway__1 = 0, den Wert der nächstgelegenen Geometrie verwenden

UPDATE highway_tertiary_ring_width AS h
SET highway__1_modif = CASE
    WHEN h.highway__1 IS NOT NULL AND h.highway__1 = 0 THEN
        (SELECT highway__1_modif FROM highway_tertiary_ring_width h ORDER BY h.geom <-> h.geom LIMIT 1)
    ELSE
        h.highway__1_modif
END
WHERE h.highway__1 IS NOT NULL;

-- check obs kein 0 mehr gibt
SELECT * FROM highway_tertiary_ring_width WHERE highway__1_modif = 0;
				
				
-- 7. highway__1_missing wird nun endlich aufgefüllt basierend auf der nächstgelegenen Geometrie,
	-- wenn hier ein highway__1_modif Wert ist (IS NOT NULL)

UPDATE highway_tertiary_ring_width rh
SET highway__1_missing = (
    SELECT rh2.highway__1_modif
    FROM highway_tertiary_ring_width rh2
    WHERE rh2.highway__1_modif IS NOT NULL
    ORDER BY rh.geom <-> rh2.geom
    LIMIT 1
)
WHERE highway__1_missing = 9999;
-- 275


-- 7. Erstellen der neuen Spalte highway__1_new 
	-- für die Werte von highway__1_modif und highway__1_missing zusammen

ALTER TABLE highway_tertiary_ring_width
ADD COLUMN highway__1_new DECIMAL;

UPDATE highway_tertiary_ring_width
SET highway__1_new = COALESCE(highway__1_modif, highway__1_missing);
-- 1838

-- checken dass hier kein highway__1_new NULL ist
SELECT * FROM highway_tertiary_ring_width WHERE highway__1_new IS NULL;
-- 0 - yes!

-- 8. highway__1_new modifizieren, 
	-- weil bei fehlenden Daten von parking_segments (datamissing und notprocessedyet)
	-- die effetive Fahrbahnbreite noch der nicht-effektiven Fahrbahnbreite entspricht,
	-- obwohl es hier Parkplätze gibt!

ALTER TABLE highway_tertiary_ring_width
ADD COLUMN highway_wi_effec_final DECIMAL;

-- Berechne die neue Parkplatzbreite für die fehlenden Daten (data_missing & not_processed_yet),
	-- wenn fahrbahnbreite gleich der effektiven fahrbahnbreite ist,
	-- sie den Standardwert von Alex und Co. bekommen haben muss, weil: width von OSM highway IS NULL,
	-- und sie NICHT den überflüssigen notprocessedyet Daten angehört (capacity_s_2 IS NOT NULL),
-- mit den Parkplatzbreiten aufgrund von Parkausrichtungsprozentsätzen.
-- Ansonsten nehme highway__1_new von der Modification von Punkt 5.

UPDATE highway_tertiary_ring_width AS h
SET highway_wi_effec_final = CASE
    WHEN h.width IS NULL THEN
        (
            SELECT 
                h.highway__1_new - (
                    SELECT 
                        (2 * (ps.percentage_parallel / 100.0)) +
                        (5 * (ps.percentage_perpendicular / 100.0)) +
                        (4.5 * (ps.percentage_diagonal / 100.0))
                    FROM parking_segments_ad_130324 AS ps
                    WHERE ps.highway = 'tertiary'
                    AND ps.capacity_s_2 IS NOT NULL
                    AND ps.capacity_s IN ('data_missing', 'not_processed_yet')
                    AND ps.highway_wi = ps.highway__1
                    LIMIT 1
                )
        )
    ELSE
        h.highway__1_new
END;

-- Durchschnitt effektive Fahrbahnbreite
SELECT AVG(highway_wi_effec_final) FROM highway_tertiary_ring_width;
-- 9.84 m

-- wie immer primary key festlegen
ALTER TABLE highway_tertiary_ring_width
ADD PRIMARY KEY (id);

-- zum anschauen und abchecken
SELECT * FROM highway_tertiary_ring_width;
-- soll jetzt alles 0 sein
SELECT * FROM highway_tertiary_ring_width WHERE highway_wi_effec_final IS NULL;
SELECT * FROM highway_tertiary_ring_width WHERE highway_wi_effec_final = 0;
SELECT * FROM highway_tertiary_ring_width WHERE highway_wi_effec_final < 0;


----------- 2.4) Unclassified

ALTER TABLE highway_unclassified_ring
ALTER COLUMN osm_id TYPE INTEGER
USING osm_id::INTEGER;

CREATE TABLE highway_unclassified_ring_width AS
SELECT * FROM highway_unclassified_ring;
-- 86


-- 1. Hinzufügen der Spalte highway__1_missing für die osm_ids die keine Fahrbahnbreite bekommen können
	-- weil es eine Kreuzung ist z.B.

ALTER TABLE highway_unclassified_ring_width
ADD COLUMN highway__1_missing DECIMAL;


-- 2. Aktualisieren der Spalte highway__1_missing mit "9999" für die osm_ids, die 
-- zwar in den secondary highways vorhanden sind aber nicht bei parking segments
	-- damit ich sie dann leicht ansprechen kann

UPDATE highway_unclassified_ring_width rh
SET highway__1_missing = '9999'
WHERE NOT EXISTS (
    SELECT 1
    FROM parking_segments_ad_130324 ps
    WHERE rh.osm_id = ps.osm_id
);
-- 22

-- 3. Hinzufügen der Spalte highway__1 
	-- (normale (effektive) Fahrbahnbreite die in parking_segments vorhanden ist)

ALTER TABLE highway_unclassified_ring_width
ADD COLUMN highway__1 DECIMAL;

UPDATE highway_unclassified_ring_width rh
SET highway__1 = ps.highway__1
FROM parking_segments_ad_130324 ps
WHERE rh.osm_id = ps.osm_id;
-- 64


-- 4. Die Spalte effektive Fahrbahnbreite (highway__1) soll modifiziert werden, weil 
	-- sie teilweise nicht Fahrbahnbreite (highway_wi) minus Parkplatzbreite (width)
	-- was es sein soll

ALTER TABLE highway_unclassified_ring_width
ADD COLUMN highway__1_modif DECIMAL;

UPDATE highway_unclassified_ring_width AS h
SET highway__1_modif = CASE
    WHEN ps.highway__1 = ps.highway_wi THEN ps.highway_wi - ps.width_modified
    ELSE h.highway__1
END
FROM parking_segments_ad_130324 AS ps
WHERE h.osm_id = ps.osm_id;
-- 64


-- 5. highway__1_missing wird nun endlich aufgefüllt basierend auf der nächstgelegenen Geometrie,
	-- wenn hier ein highway__1_modif Wert ist (IS NOT NULL)

UPDATE highway_unclassified_ring_width rh
SET highway__1_missing = (
    SELECT rh2.highway__1_modif
    FROM highway_unclassified_ring_width rh2
    WHERE rh2.highway__1_modif IS NOT NULL
    ORDER BY rh.geom <-> rh2.geom
    LIMIT 1
)
WHERE highway__1_missing = 9999;
-- 22


-- 6. Erstellen der neuen Spalte highway__1_new 
	-- für die Werte von highway__1_modif und highway__1_missing zusammen

ALTER TABLE highway_unclassified_ring_width
ADD COLUMN highway__1_new DECIMAL;

UPDATE highway_unclassified_ring_width
SET highway__1_new = COALESCE(highway__1_modif, highway__1_missing);
-- 86

-- checken dass hier kein highway__1_new NULL ist
SELECT * FROM highway_unclassified_ring_width WHERE highway__1_new IS NULL;
-- 0 - yes!

-- 8. highway__1_new modifizieren, 
	-- weil bei fehlenden Daten von parking_segments (datamissing und notprocessedyet)
	-- die effetive Fahrbahnbreite noch der nicht-effektiven Fahrbahnbreite entspricht,
	-- obwohl es hier Parkplätze gibt!

ALTER TABLE highway_unclassified_ring_width
ADD COLUMN highway_wi_effec_final DECIMAL;

-- Berechne die neue Parkplatzbreite für die fehlenden Daten (data_missing & not_processed_yet),
	-- wenn fahrbahnbreite gleich der effektiven fahrbahnbreite ist,
	-- sie den Standardwert von Alex und Co. bekommen haben muss, weil: width von OSM highway IS NULL,
	-- und sie NICHT den überflüssigen notprocessedyet Daten angehört (capacity_s_2 IS NOT NULL),
-- mit den Parkplatzbreiten aufgrund von Parkausrichtungsprozentsätzen.
-- Ansonsten nehme highway__1_new von der Modification

-- in diesem Fall bestimmt ich noch dass es keine highway_wi_effec_final
-- kleiner als 1 geben darf. Das ist unrealistisch

UPDATE highway_unclassified_ring_width AS h
SET highway_wi_effec_final = CASE
    WHEN h.width IS NULL THEN
        (
            SELECT 
                GREATEST(h.highway__1_new - (
                    SELECT 
                        (2 * (ps.percentage_parallel / 100.0)) +
                        (5 * (ps.percentage_perpendicular / 100.0)) +
                        (4.5 * (ps.percentage_diagonal / 100.0))
                    FROM parking_segments_ad_130324 AS ps
                    WHERE ps.highway = 'unclassified'
                    AND ps.capacity_s_2 IS NOT NULL
                    AND ps.capacity_s IN ('data_missing', 'not_processed_yet')
                    AND ps.highway_wi = ps.highway__1
                    LIMIT 1
                ), 1)
        )
    ELSE
        h.highway__1_new
END;


-- Durchschnitt effektive Fahrbahnbreite
SELECT AVG(highway_wi_effec_final) FROM highway_unclassified_ring_width;
-- 7.23 m

-- wie immer primary key festlegen
ALTER TABLE highway_unclassified_ring_width
ADD PRIMARY KEY (id);

-- zum anschauen und abchecken
SELECT * FROM highway_unclassified_ring_width;
-- soll jetzt nix 0 sein
SELECT * FROM highway_unclassified_ring_width WHERE highway_wi_effec_final IS NULL;
SELECT * FROM highway_unclassified_ring_width WHERE highway_wi_effec_final = 0;
SELECT * FROM highway_unclassified_ring_width WHERE highway_wi_effec_final < 0;



----------- 2.5) Residential

-- wie immer erst mal (auch wenn ich es dann wieder zu REAL umändere, damit das dann wieder mit dem mergen passt)
ALTER TABLE highway_residential_ring
ALTER COLUMN osm_id TYPE INTEGER
USING osm_id::INTEGER;


CREATE TABLE highway_residential_ring_width AS
SELECT * FROM highway_residential_ring;
-- 6859

-- 1. Hinzufügen der Spalte highway__1_missing für die osm_ids die keine Fahrbahnbreite bekommen können
ALTER TABLE highway_residential_ring_width
ADD COLUMN highway__1_missing DECIMAL;

-- 2. Aktualisieren der Spalte highway__1_missing mit "9999" für die osm_ids, die 
-- zwar in den residential highways vorhanden sind aber nicht bei parking segments
UPDATE highway_residential_ring_width rh
SET highway__1_missing = '9999'
WHERE NOT EXISTS (
    SELECT 1
    FROM parking_segments_ad_130324 ps
    WHERE rh.osm_id = ps.osm_id
);
-- 1059

-- 3. Neue Spalte highway__1 von parking_segments_ad_130324 in highway_residential_ring kopieren
ALTER TABLE highway_residential_ring_width
ADD COLUMN highway__1 DECIMAL;

UPDATE highway_residential_ring_width ht
SET highway__1 = p.highway__1
FROM parking_segments_ad_130324 p
WHERE ht.osm_id = p.osm_id;
-- 5800


------ 1. Modification von effektiver Fahrbahnbreite ----

-- 5. Neue Spalte "highway__1_modif" erstellen
ALTER TABLE highway_residential_ring_width
ADD COLUMN highway__1_modif DECIMAL;

-- 6. highway__1 modifizieren, weil
	-- sie teilweise nicht Fahrbahnbreite (highway_wi) minus Parkplatzbreite (width) haben
	-- was es sein soll
	
UPDATE highway_residential_ring_width AS h
SET highway__1_modif = CASE
    WHEN ps.highway__1 = ps.highway_wi 
	AND ps.capacity_s_2 IS NOT NULL
		THEN ps.highway_wi - ps.width_modified
    ELSE h.highway__1
END
FROM parking_segments_ad_130324 AS ps
WHERE h.osm_id = ps.osm_id;

-- UPDATE 5800


-- Ansonsten schauen welche Werte noch modifiziert werden sollten:
-- Ausreißer in residential Data sehen: Boxplot in R studio.
-- Dafür:
COPY highway_residential_ring_width TO 'C:\Dokumente\MASTER_GEO\Master Thesis\MY DATA\highway_residential_ring_width.csv' DELIMITER ',' CSV HEADER;

-- daraufhin hab ich entschieden die highway__1 Spalte von highway residential zu modifizieren, 
	-- hier sind einige Ausreißer (extrem breit), negative Werte die als positiver Wert richtig sein können und
	-- 0 meter Angaben

-- 7. Modifikationen an highway__1 vornehmen und in highway__1_modif speichern
	-- a. werte über 30 (breiter Ausreißer) durch 10 teilen
UPDATE highway_residential_ring_width
SET highway__1_modif = CASE 
                            WHEN highway__1 > 30 THEN highway__1 / 10
                            ELSE ABS(highway__1)
                        END;

	-- b. Bei negative Werte in highway__1_modif auch den wert der nächsten geometrie nehemn
UPDATE highway_residential_ring_width rh
SET highway__1_modif = (
    SELECT rh.highway__1_modif
    FROM highway_residential_ring_width rh
    WHERE rh.highway__1_modif IS NOT NULL 
    ORDER BY rh.geom <-> rh.geom
    LIMIT 1
)
WHERE highway__1 < 0;
-- 18 affected

	-- c. Wenn Fahrbahnbreiten 0 sind, die Breite des benachbarten Straßenabschnitts nehmen
UPDATE highway_residential_ring_width rh
SET highway__1_modif = (
    SELECT rh.highway__1_modif
    FROM highway_residential_ring_width rh
    WHERE rh.highway__1_modif IS NOT NULL 
    ORDER BY rh.geom <-> rh.geom
    LIMIT 1
)
WHERE highway__1 = 0;
-- 8 affected

-- 8. Aktualisieren der Spalte highway__1_missing basierend auf der nächstgelegenen Geometrie
UPDATE highway_residential_ring_width rh
SET highway__1_missing = (
    SELECT rh.highway__1_modif
    FROM highway_residential_ring_width rh
    WHERE rh.highway__1_modif IS NOT NULL 
    ORDER BY rh.geom <-> rh.geom
    LIMIT 1
)
WHERE highway__1_missing = 9999;
-- 1059


-- checken
SELECT * FROM highway_residential_ring_width WHERE highway__1_modif = 0;


-- 9. Erstellen der neuen Spalte highway__1_new und Zusammenführen der Werte von highway__1 und highway__1_missing
ALTER TABLE highway_residential_ring_width
ADD COLUMN highway__1_new DECIMAL;

UPDATE highway_residential_ring_width
SET highway__1_new = COALESCE(highway__1_modif, highway__1_missing);
-- 6859

SELECT * FROM highway_residential_ring_width WHERE highway__1_new IS NULL;
-- 0

----- 2. Modification von effektiver Fahrbahnbreite ------

-- 10. highway__1_new modifizieren, 
	-- weil bei fehlenden Daten von parking_segments (datamissing und notprocessedyet)
	-- die effetive Fahrbahnbreite noch der nicht-effektiven Fahrbahnbreite entspricht,
	-- obwohl es hier Parkplätze gibt!
ALTER TABLE highway_residential_ring_width
ADD COLUMN highway_wi_effec_final DECIMAL;

UPDATE highway_residential_ring_width AS h
SET highway_wi_effec_final = CASE
    WHEN h.width IS NULL THEN
        COALESCE(
            (
                SELECT 
                    GREATEST(h.highway__1_new - (
                        SELECT 
                            (2 * (ps.percentage_parallel / 100.0)) +
                            (5 * (ps.percentage_perpendicular / 100.0)) +
                            (4.5 * (ps.percentage_diagonal / 100.0))
                        FROM parking_segments_ad_130324 AS ps
                        WHERE ps.highway = 'residential'
                        AND ps.capacity_s_2 IS NOT NULL
                        AND ps.capacity_s IN ('data_missing', 'not_processed_yet')
                        AND ps.highway_wi = ps.highway__1
                        LIMIT 1
                    ), 1)
            ), h.highway__1_new
        )
    ELSE
        h.highway__1_new
END;



SELECT AVG(highway_wi_effec_final) FROM highway_residential_ring_width;
-- 6.59 m
-- mit der Bedingung oben (capacity_s_2 NOT NULL) jetzt noch 6.57 m


-- primary key festlegen
ALTER TABLE highway_residential_ring_width
ADD PRIMARY KEY (id);


-- jetzt noch mal boxplot mit R anschauen: 

COPY highway_residential_ring_width TO 'C:\Dokumente\MASTER_GEO\Master Thesis\MY DATA\highway_residential_ring_width_new.csv' DELIMITER ',' CSV HEADER;


-- zum anschauen und abchecken
SELECT * FROM highway_unclassified_ring_width;
-- soll jetzt alles 0 sein
SELECT * FROM highway_residential_ring_width WHERE highway_wi_effec_final IS NULL;
SELECT * FROM highway_residential_ring_width WHERE highway_wi_effec_final = 0;
SELECT * FROM highway_residential_ring_width WHERE highway_wi_effec_final < 0;


----------- 2.6) Living street

ALTER TABLE highway_living_street_ring
ALTER COLUMN osm_id TYPE INTEGER
USING osm_id::INTEGER;

CREATE TABLE highway_living_street_ring_width AS
SELECT * FROM highway_living_street_ring;
-- 650 

-- 1. Hinzufügen der Spalte highway__1_missing für die osm_ids die keine Fahrbahnbreite bekommen können
ALTER TABLE highway_living_street_ring_width
ADD COLUMN highway__1_missing DECIMAL;

-- 2. Aktualisieren der Spalte highway__1_missing mit "9999" für die osm_ids, die 
-- zwar in den residential highways vorhanden sind aber nicht bei parking segments
UPDATE highway_living_street_ring_width rh
SET highway__1_missing = '9999'
WHERE NOT EXISTS (
    SELECT 1
    FROM parking_segments_ad_130324 ps
    WHERE rh.osm_id = ps.osm_id
);
-- 86

-- 3. Hinzufügen der Spalte highway__1
ALTER TABLE highway_living_street_ring_width
ADD COLUMN highway__1 DECIMAL;

-- 4. Aktualisieren der Spalte highway__1 mit den Werten aus parking_segments
UPDATE highway_living_street_ring_width rh
SET highway__1 = ps.highway__1
FROM parking_segments_ad_130324 ps
WHERE rh.osm_id = ps.osm_id;
-- 564


------ 1. Modification von effektiver Fahrbahnbreite ----

-- 5. Neue Spalte "highway__1_modif" erstellen
ALTER TABLE highway_living_street_ring_width
ADD COLUMN highway__1_modif DECIMAL;

-- 6. highway__1 modifizieren, weil
	-- sie teilweise nicht Fahrbahnbreite (highway_wi) minus Parkplatzbreite (width)
	-- was es sein soll

UPDATE highway_living_street_ring_width AS h
SET highway__1_modif = CASE
    WHEN ps.highway__1 = ps.highway_wi THEN ps.highway_wi - ps.width_modified
    ELSE h.highway__1
END
FROM parking_segments_ad_130324 AS ps
WHERE h.osm_id = ps.osm_id;
-- 564

-- 7. Modifikationen an highway__1 vornehmen und in highway__1_modif speichern
	-- a. Bei negative Werte in highway__1_modif auch den wert der nächsten geometrie nehemn
UPDATE highway_living_street_ring_width rh
SET highway__1_modif = (
    SELECT rh.highway__1_modif
    FROM highway_living_street_ring_width rh
    WHERE rh.highway__1_modif IS NOT NULL 
    ORDER BY rh.geom <-> rh.geom
    LIMIT 1
)
WHERE highway__1 < 0;

-- chekcn ob das nciht der fall ist
SELECT * FROM highway_living_street_ring_width WHERE highway__1 = 0;
-- nope

-- 8. Aktualisieren der Spalte highway__1_missing basierend auf der nächstgelegenen Geometrie
UPDATE highway_living_street_ring_width rh
SET highway__1_missing = (
    SELECT rh2.highway__1_modif
    FROM highway_living_street_ring_width rh2
    WHERE rh2.highway__1_modif IS NOT NULL
    ORDER BY rh.geom <-> rh2.geom
    LIMIT 1
)
WHERE highway__1_missing = 9999;
-- 86

-- checken
SELECT * FROM highway_living_street_ring_width WHERE highway__1_modif = 0;
SELECT * FROM highway_living_street_ring_width WHERE highway__1_missing = 9999;


-- 9. Erstellen der neuen Spalte highway__1_new und Zusammenführen der Werte von highway__1 und highway__1_missing
ALTER TABLE highway_living_street_ring_width
ADD COLUMN highway__1_new DECIMAL;

UPDATE highway_living_street_ring_width
SET highway__1_new = COALESCE(highway__1_modif, highway__1_missing);
-- 650

SELECT * FROM highway_living_street_ring_width WHERE highway__1_new IS NULL;
-- 0

----- 2. Modification von effektiver Fahrbahnbreite ------

-- 10. highway__1_new modifizieren, 
	-- weil bei fehlenden Daten von parking_segments (datamissing und notprocessedyet)
	-- die effetive Fahrbahnbreite noch der nicht-effektiven Fahrbahnbreite entspricht,
	-- obwohl es hier Parkplätze gibt!
ALTER TABLE highway_living_street_ring_width
ADD COLUMN highway_wi_effec_final DECIMAL;

UPDATE highway_living_street_ring_width AS h
SET highway_wi_effec_final = CASE
    WHEN h.width IS NULL THEN
        COALESCE(
            (
                SELECT 
                    GREATEST(h.highway__1_new - (
                        SELECT 
                            (2 * (ps.percentage_parallel / 100.0)) +
                            (5 * (ps.percentage_perpendicular / 100.0)) +
                            (4.5 * (ps.percentage_diagonal / 100.0))
                        FROM parking_segments_ad_130324 AS ps
                        WHERE ps.highway = 'living_street'
                        AND ps.capacity_s_2 IS NOT NULL
                        AND ps.capacity_s IN ('data_missing', 'not_processed_yet')
                        AND ps.highway_wi = ps.highway__1
                        LIMIT 1
                    ), 1)
            ), h.highway__1_new
        )
    ELSE
        h.highway__1_new
END;

-- durchschnittliche fahrbahnbreite living street:
SELECT AVG(highway_wi_effec_final) FROM highway_living_street_ring_width;
-- 6.31 m


-- primary key festlegen
ALTER TABLE highway_living_street_ring_width
ADD PRIMARY KEY (id);


-- zum anschauen
SELECT * FROM highway_living_street_ring_width;
-- soll jetzt nix 0 sein
SELECT * FROM highway_living_street_ring_width WHERE highway_wi_effec_final IS NULL;
SELECT * FROM highway_living_street_ring_width WHERE highway_wi_effec_final = 0;
SELECT * FROM highway_living_street_ring_width WHERE highway_wi_effec_final < 0;



----------- 2.7) Pedestrian


ALTER TABLE highway_pedestrian_ring
ALTER COLUMN osm_id TYPE INTEGER
USING osm_id::INTEGER;

CREATE TABLE highway_pedestrian_ring_width AS
SELECT * FROM highway_pedestrian_ring;
-- 233

-- 1. Hinzufügen der Spalte highway__1_missing für die osm_ids die keine Fahrbahnbreite bekommen können
ALTER TABLE highway_pedestrian_ring_width
ADD COLUMN highway__1_missing DECIMAL;

-- 2. Aktualisieren der Spalte highway__1_missing mit "9999" für die osm_ids, die 
-- zwar in den residential highways vorhanden sind aber nicht bei parking segments
UPDATE highway_pedestrian_ring_width rh
SET highway__1_missing = '9999'
WHERE NOT EXISTS (
    SELECT 1
    FROM parking_segments_ad_130324 ps
    WHERE rh.osm_id = ps.osm_id
);
-- 44


-- 3. Hinzufügen der Spalte highway__1
ALTER TABLE highway_pedestrian_ring_width
ADD COLUMN highway__1 DECIMAL;

-- 4. Aktualisieren der Spalte highway__1 mit den Werten aus parking_segments
UPDATE highway_pedestrian_ring_width rh
SET highway__1 = ps.highway__1
FROM parking_segments_ad_130324 ps
WHERE rh.osm_id = ps.osm_id;
-- 189

------ 1. Modification von effektiver Fahrbahnbreite ----

-- 5. Neue Spalte "highway__1_modif" erstellen
ALTER TABLE highway_pedestrian_ring_width
ADD COLUMN highway__1_modif DECIMAL;

-- 6. highway__1 modifizieren, weil
	-- sie teilweise nicht Fahrbahnbreite (highway_wi) minus Parkplatzbreite (width)
	-- was es sein soll

UPDATE highway_pedestrian_ring_width AS h
SET highway__1_modif = CASE
    WHEN ps.highway__1 = ps.highway_wi THEN ps.highway_wi - ps.width_modified
    ELSE h.highway__1
END
FROM parking_segments_ad_130324 AS ps
WHERE h.osm_id = ps.osm_id;
-- 189

-- chekcn ob das nciht der fall ist
SELECT * FROM highway_pedestrian_ring_width WHERE highway__1_modif = 0;
-- 0
SELECT * FROM highway_pedestrian_ring_width WHERE highway__1_modif < 0;
-- 0

-- 7. Aktualisieren der Spalte highway__1_missing basierend auf der nächstgelegenen Geometrie
UPDATE highway_pedestrian_ring_width rh
SET highway__1_missing = (
    SELECT rh2.highway__1_modif
    FROM highway_pedestrian_ring_width rh2
    WHERE rh2.highway__1_modif IS NOT NULL
    ORDER BY rh.geom <-> rh2.geom
    LIMIT 1
)
WHERE highway__1_missing = 9999;
-- 44

-- 8. Erstellen der neuen Spalte highway__1_new und Zusammenführen der Werte von highway__1 und highway__1_missing
ALTER TABLE highway_pedestrian_ring_width
ADD COLUMN highway__1_new DECIMAL;

UPDATE highway_pedestrian_ring_width
SET highway__1_new = COALESCE(highway__1_modif, highway__1_missing);
-- 233

SELECT * FROM highway_pedestrian_ring_width WHERE highway__1_new IS NULL;
-- 0

----- 2. Modification von effektiver Fahrbahnbreite ------

-- 10. highway__1_new modifizieren, 
	-- weil bei fehlenden Daten von parking_segments (datamissing und notprocessedyet)
	-- die effetive Fahrbahnbreite noch der nicht-effektiven Fahrbahnbreite entspricht,
	-- obwohl es hier Parkplätze gibt!
ALTER TABLE highway_pedestrian_ring_width
ADD COLUMN highway_wi_effec_final DECIMAL;

UPDATE highway_pedestrian_ring_width AS h
SET highway_wi_effec_final = CASE
    WHEN h.width IS NULL THEN
        COALESCE(
            (
                SELECT 
                    GREATEST(h.highway__1_new - (
                        SELECT 
                            (2 * (ps.percentage_parallel / 100.0)) +
                            (5 * (ps.percentage_perpendicular / 100.0)) +
                            (4.5 * (ps.percentage_diagonal / 100.0))
                        FROM parking_segments_ad_130324 AS ps
                        WHERE ps.highway = 'pedestrian'
                        AND ps.capacity_s_2 IS NOT NULL
                        AND ps.capacity_s IN ('data_missing', 'not_processed_yet')
                        AND ps.highway_wi = ps.highway__1
                        LIMIT 1
                    ), 1)
            ), h.highway__1_new
        )
    ELSE
        h.highway__1_new
END;

-- durchschnittliche Fahrbahnbreite pedestrian
SELECT AVG(highway_wi_effec_final) FROM highway_pedestrian_ring_width;
-- 10.86 m


-- primary key festlegen
ALTER TABLE highway_pedestrian_ring_width
ADD PRIMARY KEY (id);


-- zum anschauen
SELECT * FROM highway_pedestrian_ring_width;
-- soll jetzt nix 0 sein
SELECT * FROM highway_pedestrian_ring_width WHERE highway_wi_effec_final IS NULL;
SELECT * FROM highway_pedestrian_ring_width WHERE highway_wi_effec_final = 0;
SELECT * FROM highway_pedestrian_ring_width WHERE highway_wi_effec_final < 0;
-- yes

SELECT * FROM highway_pedestrian_ring_width WHERE highway IS NULL;
-- 15 sind NULL
-- das sind Stellen bei einer Fußgängerzone we Gebäude oder Freiflächen in der 
-- Fußgängerzone sind. 
-- also einfach Löschen:

DELETE FROM highway_pedestrian_ring_width
WHERE highway IS NULL;



------------------------------------------------------------------------------
-------- 2) BUFFER AND DISSOLVE DATASETS PER ROAD TYPE
------------------------------------------------------------------------------


--------------(3) 'highway_[...]_ring_width' Datensätze buffern und dissolven per road type


------ 3.1) PRIMARY 

-- neue Tabelle erstellen 

CREATE TABLE primary_dissolved_2 (
    id SERIAL PRIMARY KEY,
    highway VARCHAR,
    highway_wi_effec_total NUMERIC,
    geom GEOMETRY(MultiPolygon, 25833)
);

-- Straßentyp (highway) einfügen, effektive Fahrbahnbreite summiert einfügen,
-- Geometrie mit der effektiven Fahrbahnbreite geteilt durch 2 buffern und
-- fusioniert als ein Polygonlayer (QGIS tool heißt 'dissolved')

INSERT INTO primary_dissolved_2 (highway, highway_wi_effec_total, geom)
SELECT
    highway_primary_ring_width.highway,
    SUM(highway_primary_ring_width.highway_wi_effec_final) AS highway_wi_effec_total,
    ST_Multi(ST_Union(ST_Buffer(highway_primary_ring_width.geom, highway_primary_ring_width.highway_wi_effec_final / 2))) AS geom
FROM
    highway_primary_ring_width
GROUP BY
    highway_primary_ring_width.highway;


------ 3.2) SECONDARY

-- neue tabelle
CREATE TABLE secondary_dissolved_2 (
    id SERIAL PRIMARY KEY,
    highway VARCHAR,
    highway_wi_effec_total NUMERIC,
    geom GEOMETRY(MultiPolygon, 25833)
);

-- tabelle füllen
INSERT INTO secondary_dissolved_2 (highway, highway_wi_effec_total, geom)
SELECT
    highway_secondary_ring_width.highway,
    SUM(highway_secondary_ring_width.highway_wi_effec_final) AS highway_wi_effec_total,
    ST_Multi(ST_Union(ST_Buffer(highway_secondary_ring_width.geom, highway_secondary_ring_width.highway_wi_effec_final / 2))) AS geom
FROM
    highway_secondary_ring_width
GROUP BY
    highway_secondary_ring_width.highway;


----- 3.3) TERTIARY

-- neue tabelle
CREATE TABLE tertiary_dissolved_2 (
    id SERIAL PRIMARY KEY,
    highway VARCHAR,
    highway_wi_effec_total NUMERIC,
    geom GEOMETRY(MultiPolygon, 25833)
);

-- tabelle füllen
INSERT INTO tertiary_dissolved_2 (highway, highway_wi_effec_total, geom)
SELECT
    highway_tertiary_ring_width.highway,
    SUM(highway_tertiary_ring_width.highway_wi_effec_final) AS highway_wi_effec_total,
    ST_Multi(ST_Union(ST_Buffer(highway_tertiary_ring_width.geom, highway_tertiary_ring_width.highway_wi_effec_final / 2))) AS geom
FROM
    highway_tertiary_ring_width
GROUP BY
    highway_tertiary_ring_width.highway;
	

------ 3.4) UNCLASSIFIED

-- neue tabelle

CREATE TABLE unclassified_dissolved_2 (
    id SERIAL PRIMARY KEY,
    highway VARCHAR,
    highway_wi_effec_total NUMERIC,
    geom GEOMETRY(MultiPolygon, 25833)
);

-- tabelle füllen
INSERT INTO unclassified_dissolved_2 (highway, highway_wi_effec_total, geom)
SELECT
    highway_unclassified_ring_width.highway,
    SUM(highway_unclassified_ring_width.highway_wi_effec_final) AS highway_wi_effec_total,
    ST_Multi(ST_Union(ST_Buffer(highway_unclassified_ring_width.geom, highway_unclassified_ring_width.highway_wi_effec_final / 2))) AS geom
FROM
    highway_unclassified_ring_width
GROUP BY
    highway_unclassified_ring_width.highway;


------- 3.5) RESIDENTIAL

-- neue tabelle
CREATE TABLE residential_dissolved_2 (
    id SERIAL PRIMARY KEY,
    highway VARCHAR,
    highway_wi_effec_total NUMERIC,
    geom GEOMETRY(MultiPolygon, 25833)
);

-- tabelle füllen
INSERT INTO residential_dissolved_2 (highway, highway_wi_effec_total, geom)
SELECT
    highway_residential_ring_width.highway,
    SUM(highway_residential_ring_width.highway_wi_effec_final) AS highway_wi_effec_total,
    ST_Multi(ST_Union(ST_Buffer(highway_residential_ring_width.geom, highway_residential_ring_width.highway_wi_effec_final / 2))) AS geom
FROM
    highway_residential_ring_width
GROUP BY
    highway_residential_ring_width.highway;


------ 3.6) LIVING STREET

-- neue tabelle
CREATE TABLE living_street_dissolved_2 (
    id SERIAL PRIMARY KEY,
    highway VARCHAR,
    highway_wi_effec_total NUMERIC,
    geom GEOMETRY(MultiPolygon, 25833)
);

-- tabelle füllen
INSERT INTO living_street_dissolved_2 (highway, highway_wi_effec_total, geom)
SELECT
    highway_living_street_ring_width.highway,
    SUM(highway_living_street_ring_width.highway_wi_effec_final) AS highway_wi_effec_total,
    ST_Multi(ST_Union(ST_Buffer(highway_living_street_ring_width.geom, highway_living_street_ring_width.highway_wi_effec_final / 2))) AS geom
FROM
    highway_living_street_ring_width
GROUP BY
    highway_living_street_ring_width.highway;
	

----------- 3.7) PEDESTRIAN

-- neue tabelle
CREATE TABLE pedestrian_dissolved_2 (
    id SERIAL PRIMARY KEY,
    highway VARCHAR,
    highway_wi_effec_total NUMERIC,
    geom GEOMETRY(MultiPolygon, 25833)
);

-- tabelle füllen
INSERT INTO pedestrian_dissolved_2 (highway, highway_wi_effec_total, geom)
SELECT
    highway_pedestrian_ring_width.highway,
    SUM(highway_pedestrian_ring_width.highway_wi_effec_final) AS highway_wi_effec_total,
    ST_Multi(ST_Union(ST_Buffer(highway_pedestrian_ring_width.geom, highway_pedestrian_ring_width.highway_wi_effec_final / 2))) AS geom
FROM
    highway_pedestrian_ring_width
GROUP BY
    highway_pedestrian_ring_width.highway;
	


------------------------------------------------------------------------------
------- 3) MERGING ROAD TYPE HIERARCHICALLY
------------------------------------------------------------------------------


-------- (4) Straßentypen hierarchisch zusammenfügen --------------------------
-------- (4.1.A) "difference" von ---------------------------------------------
---------------- 'secondary_dissolved_2' und 'primary_dissolved_2' ------------
----------------- Ergebnis = secondary Straßen ohne ---------------------------
---------------------------- Überschneidungen zu primary Straßen --------------
---------------------------- -> Neue Table: "difference_sec" ------------------
----------- (p.s. die Summierte Fahrbahnbreite wird hier nicht abgezogen) -----
-------- (4.2.B) "merge" (heißt so in QGIS) hier: ST_union --------------------
----------------- von 'difference_sec' und 'primary_dissolved_2' --------------
----------------- Ergebnis = Überlappungsfreie merged Dataset -----------------
---------------------------- von primary und secondary Straßen ----------------
---------------------------- -> Layername "merged_typ1_bis2" ------------------

---------- A) und B) für alle andern Straßentypen wiederholen ---------------

------ (4.1.A) difference sec und primary
-------------- Name: difference_sec

CREATE TABLE difference_sec AS 
SELECT a.id, a.highway, a.highway_wi_effec_total, ST_Difference(a.geom, ST_Union(b.geom)) AS geom
FROM secondary_dissolved_2 AS a
JOIN primary_dissolved_2 AS b
ON ST_Intersects(a.geom, b.geom)
GROUP BY a.id;

-- primary key festlegen
ALTER TABLE difference_sec
ADD PRIMARY KEY(id);


------ (4.2.B) merge difference_sec und primary
-------------- Dataname: merged_pri_to_sec

CREATE TABLE merged_pri_to_sec (
    id SERIAL PRIMARY KEY,
    highway VARCHAR,
    geom GEOMETRY(MultiPolygon, 25833),
    highway_wi_effec_total DECIMAL
);

-- ST(Union)

INSERT INTO merged_pri_to_sec (highway, geom, highway_wi_effec_total)
SELECT highway, ST_Multi(ST_Union(geom)) AS geom,
       SUM(highway_wi_effec_total) AS highway_wi_effec_total
FROM (
    SELECT highway, geom, highway_wi_effec_total
    FROM difference_sec
    UNION ALL
    SELECT highway, geom, highway_wi_effec_total
    FROM primary_dissolved_2
) AS merged_data
GROUP BY highway;


------ (4.2.A) difference tertiary und merged_pri_to_sec
-------------- Name: difference_ter

CREATE TABLE difference_ter AS 
SELECT a.id, a.highway, a.highway_wi_effec_total, ST_Difference(a.geom, ST_Union(b.geom)) AS geom
FROM tertiary_dissolved_2 AS a
JOIN merged_pri_to_sec AS b
ON ST_Intersects(a.geom, b.geom)
GROUP BY a.id;

-- primary key festlegen
ALTER TABLE difference_ter
ADD PRIMARY KEY(id);


------ (4.2.B) merge difference_ter und merged_pri_to_sec
-------------- Dataname: merged_pri_to_ter

CREATE TABLE merged_pri_to_ter (
    id SERIAL PRIMARY KEY,
    highway VARCHAR,
    geom GEOMETRY(MultiPolygon, 25833),
    highway_wi_effec_total DECIMAL
);

-- ST(Union)

INSERT INTO merged_pri_to_ter (highway, geom, highway_wi_effec_total)
SELECT highway, ST_Multi(ST_Union(geom)) AS geom,
       SUM(highway_wi_effec_total) AS highway_wi_effec_total
FROM (
    SELECT highway, geom, highway_wi_effec_total
    FROM difference_ter
    UNION ALL
    SELECT highway, geom, highway_wi_effec_total
    FROM merged_pri_to_sec
) AS merged_data
GROUP BY highway;


------ (4.3.A) difference unclassified und merged_pri_to_ter
-------------- Name: difference_uncla

CREATE TABLE difference_uncla AS 
SELECT a.id, a.highway, a.highway_wi_effec_total, ST_Difference(a.geom, ST_Union(b.geom)) AS geom
FROM unclassified_dissolved_2 AS a
JOIN merged_pri_to_ter AS b
ON ST_Intersects(a.geom, b.geom)
GROUP BY a.id;

-- primary key festlegen
ALTER TABLE difference_uncla
ADD PRIMARY KEY(id);


------ (4.3.B) merge difference_uncla und merged_pri_to_ter
-------------- Dataname: merged_pri_to_uncla

CREATE TABLE merged_pri_to_uncla (
    id SERIAL PRIMARY KEY,
    highway VARCHAR,
    geom GEOMETRY(MultiPolygon, 25833),
    highway_wi_effec_total DECIMAL
);

-- ST(Union)

INSERT INTO merged_pri_to_uncla (highway, geom, highway_wi_effec_total)
SELECT highway, ST_Multi(ST_Union(geom)) AS geom,
       SUM(highway_wi_effec_total) AS highway_wi_effec_total
FROM (
    SELECT highway, geom, highway_wi_effec_total
    FROM difference_uncla
    UNION ALL
    SELECT highway, geom, highway_wi_effec_total
    FROM merged_pri_to_ter
) AS merged_data
GROUP BY highway;



------ (4.4.A) difference residential und merged_pri_to_uncla
-------------- Name: difference_resi

CREATE TABLE difference_resi AS 
SELECT a.id, a.highway, a.highway_wi_effec_total, ST_Difference(a.geom, ST_Union(b.geom)) AS geom
FROM residential_dissolved_2 AS a
JOIN merged_pri_to_uncla AS b
ON ST_Intersects(a.geom, b.geom)
GROUP BY a.id;

-- primary key festlegen
ALTER TABLE difference_resi
ADD PRIMARY KEY(id);


------ (4.4.B) merge difference_resi und merged_pri_to_uncla
-------------- Dataname: merged_pri_to_resi

CREATE TABLE merged_pri_to_resi (
    id SERIAL PRIMARY KEY,
    highway VARCHAR,
    geom GEOMETRY(MultiPolygon, 25833),
    highway_wi_effec_total DECIMAL
);

-- ST(Union)

INSERT INTO merged_pri_to_resi (highway, geom, highway_wi_effec_total)
SELECT highway, ST_Multi(ST_Union(geom)) AS geom,
       SUM(highway_wi_effec_total) AS highway_wi_effec_total
FROM (
    SELECT highway, geom, highway_wi_effec_total
    FROM difference_resi
    UNION ALL
    SELECT highway, geom, highway_wi_effec_total
    FROM merged_pri_to_uncla
) AS merged_data
GROUP BY highway;


------ (4.5.A) difference living_street und merged_pri_to_resi
-------------- Name: difference_livi

CREATE TABLE difference_livi AS 
SELECT a.id, a.highway, a.highway_wi_effec_total, ST_Difference(a.geom, ST_Union(b.geom)) AS geom
FROM living_street_dissolved_2 AS a
JOIN merged_pri_to_resi AS b
ON ST_Intersects(a.geom, b.geom)
GROUP BY a.id;

-- primary key festlegen
ALTER TABLE difference_livi
ADD PRIMARY KEY(id);


------ (4.5.B) merge difference_resi und merged_pri_to_uncla
-------------- Dataname: merged_pri_to_livi

CREATE TABLE merged_pri_to_livi (
    id SERIAL PRIMARY KEY,
    highway VARCHAR,
    geom GEOMETRY(MultiPolygon, 25833),
    highway_wi_effec_total DECIMAL
);

-- ST(Union)

INSERT INTO merged_pri_to_livi (highway, geom, highway_wi_effec_total)
SELECT highway, ST_Multi(ST_Union(geom)) AS geom,
       SUM(highway_wi_effec_total) AS highway_wi_effec_total
FROM (
    SELECT highway, geom, highway_wi_effec_total
    FROM difference_livi
    UNION ALL
    SELECT highway, geom, highway_wi_effec_total
    FROM merged_pri_to_resi
) AS merged_data
GROUP BY highway;



------ (4.6.A) difference pedestrian und merged_pri_to_livi
-------------- Name: difference_pedes

CREATE TABLE difference_pedes AS 
SELECT a.id, a.highway, a.highway_wi_effec_total, ST_Difference(a.geom, ST_Union(b.geom)) AS geom
FROM pedestrian_dissolved_2 AS a
JOIN merged_pri_to_livi AS b
ON ST_Intersects(a.geom, b.geom)
GROUP BY a.id;

-- primary key festlegen
ALTER TABLE difference_pedes
ADD PRIMARY KEY(id);


------ (4.6.B) merge difference_resi und merged_pri_to_uncla
-------------- Dataname: merged_pri_to_pedes

CREATE TABLE merged_pri_to_pedes (
    id SERIAL PRIMARY KEY,
    highway VARCHAR,
    geom GEOMETRY(MultiPolygon, 25833),
    highway_wi_effec_total DECIMAL
);

-- ST(Union)

INSERT INTO merged_pri_to_pedes (highway, geom, highway_wi_effec_total)
SELECT highway, ST_Multi(ST_Union(geom)) AS geom,
       SUM(highway_wi_effec_total) AS highway_wi_effec_total
FROM (
    SELECT highway, geom, highway_wi_effec_total
    FROM difference_pedes
    UNION ALL
    SELECT highway, geom, highway_wi_effec_total
    FROM merged_pri_to_livi
) AS merged_data
GROUP BY highway;


-- finale Tabelle erstellen
CREATE TABLE merged_highways_1_to_7_final AS
SELECT * FROM merged_pri_to_pedes;


ALTER TABLE merged_highways_1_to_7_final
ADD PRIMARY KEY(id);



------------------------------------------------------------------------------
-------------- 4) Roadway area calculation 
------------------------------------------------------------------------------

-- Gesamt Straßenfläche im Ring:
-- ohne die Fahrradparkplätze:
SELECT SUM(ST_Area(geom)) AS area
FROM merged_highways_1_to_7_final;
-- 7 990 220 m² = 799 ha

