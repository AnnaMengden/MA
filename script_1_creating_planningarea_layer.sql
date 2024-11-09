
--------------------- SCRIPT 1 -------------------------
---------- 03.03.2024 ----- by Anna Mengden ------------
--------- PLR (Planungsraum Layer) erstellen -----------


-- manche LOR (die am Rand) sind kaum im Ring und haben damit dann oft auch keine parking_segments inne
	-- Lösung: checken zu wie viel Prozent die LORs jeweils innerhalb des Rings liegen:
		-- tabelle erstellen mit plr_id und dem flächeninhalt aus dem LOR-Berlin Layer 


-- Tabelle "plr_area_berlin_ring" erstellen
CREATE TABLE plr_area_berlin_ring (
    plr_id character varying,
    finhalt_berlin FLOAT,
    finhalt_ring FLOAT,
    percentage_im_ring FLOAT
);

-- Daten von "LOR_planungsr_berlin" einfügen
INSERT INTO plr_area_berlin_ring (plr_id, finhalt_berlin)
SELECT "PLR_ID", ST_Area(geom)
FROM "LOR_planungsr_berlin";

-- Daten von "LOR_planungsraeume_ring" einfügen
UPDATE plr_area_berlin_ring
SET finhalt_ring = ST_Area(geom)
FROM "LOR_planungsraeume_ring"
WHERE plr_area_berlin_ring.plr_id = "LOR_planungsraeume_ring".PLR_ID;


-- Prozentsatz berechnen und in die Spalte "percentage_ring" einfügen
UPDATE plr_area_berlin_ring
SET percentage_im_ring = (finhalt_ring * 100.0) / finhalt_berlin;


-- Nun Ergebnis anschauen:
-- Prozentsätze zwischen 1 und 50 zeigen, um zu entscheiden, welche LORs 
	-- dazugehören sollen, welche nicht 
SELECT *
FROM plr_area_berlin_ring
WHERE percentage_im_ring BETWEEN 1 AND 50
ORDER BY percentage_im_ring;

--^^ Ergbenis: Maximalste ist 49,3% , dann lange nix, dann nur noch zu 6%
-- Die 49% muss mit rein. deswegen mach ich die die mindestens 45% 
-- im Ring sind


-- LOR Layer erstellen, der nur die LORs beinhaltet, die mindestens zur 49% im Ring sind
-- Begründung: dann ist der Ring ausgefüllt und keine große Lücke entsteht (siehe oben)

CREATE TABLE plr_ring_modi  AS
SELECT
    p.*
FROM
    "LOR_planungsraeume_ring" p
JOIN
    plr_area_berlin_ring m ON p.PLR_ID = m.plr_id
WHERE
    m.percentage_im_ring >= 49;
	
-- Ergebnis: 145 Zeilen


-- PLR Fläche einfügen durch Flächenberechnung der Geometrie (für später) 
-- weil ja manche PLRs jetzt zerschnitten und deswegen kleiner sind 

ALTER TABLE plr_ring_modi
ADD COLUMN plr_area FLOAT;

UPDATE plr_ring_modi
SET plr_area = CAST(ST_Area(geom) AS FLOAT);

-- set primary key

ALTER TABLE plr_ring_modi
ADD PRIMARY KEY (plr_id);

-- anschauen
SELECT * FROM plr_ring_modi;


-- Was ist meinem PLR Layer zufolge die Gesamtfläche vom Ring?

SELECT SUM(ST_Area(geom)) FROM plr_ring_modi;
-- 87,463,889.403792 m²


-- laut AfS 2023b (Flächenerhebung nach Art der tatsächlichen Nutzung in Berlin 2022. Statistischer Bericht A V 3 – j / 22)
-- Ganz Berlin: 89,112 ha

-- 8,746 ha (Ring) von 89,112 ha (ganz Berlin laut AfS 2023b) sind 9.8%
