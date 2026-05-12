-- ============================================================
-- Macro : cardinal_to_degrees
-- ============================================================
-- Convertit une direction cardinale (string genre 'NNW', 'WSW') en degrés.
-- 16 points de la rose des vents, espacés de 22.5° (= 360 / 16).
--
-- Convention météo : 0° = Nord, 90° = Est, 180° = Sud, 270° = Ouest.
-- Le vent souffle DEPUIS la direction indiquée (un vent de N arrive du Nord).
--
-- Renvoie NULL si l'entrée ne correspond à aucun point cardinal connu
-- (typiquement quand le vent est nul ou la valeur source est NULL/'').
--
-- Usage dans un modèle :
--   {{ cardinal_to_degrees('wind_direction_cardinal') }} as wind_direction_deg

{% macro cardinal_to_degrees(column_name) %}
    case upper(trim({{ column_name }}))
        when 'N'   then 0
        when 'NNE' then 22.5
        when 'NE'  then 45
        when 'ENE' then 67.5
        when 'E'   then 90
        when 'ESE' then 112.5
        when 'SE'  then 135
        when 'SSE' then 157.5
        when 'S'   then 180
        when 'SSW' then 202.5
        when 'SW'  then 225
        when 'WSW' then 247.5
        when 'W'   then 270
        when 'WNW' then 292.5
        when 'NW'  then 315
        when 'NNW' then 337.5
        else null
    end
{% endmacro %}
