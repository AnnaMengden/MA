--------------------- SCRIPT 2 -------------------------
---------- 17.03.2024 -----by  Anna Mengden ------------
-- Gesamtfläche der off-street parking spaces im Ring --

-- Datensatz "amenity_parking_parking_surface_ring" 
	--> Quick OSM: key = amenity:parking, value = surface in QGIS
	--> clipped to plr_ring_modi Layer in QGIS

-- Flächenberechnung mit Geometrie:
SELECT SUM(ST_Area(geom)) AS area
FROM amenity_parking_parking_surface_ring;
-- 1347985 m² = 134,8 ha große Parkplätze (Kartiert in OSM)

