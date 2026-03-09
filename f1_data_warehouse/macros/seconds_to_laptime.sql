{% macro seconds_to_laptime(column_name) %}
    concat(
        lpad(cast(floor({{ column_name }} / 60) as string), 1, '0'),
        ':',
        lpad(cast(floor({{ column_name }} % 60) as string), 2, '0'),
        '.',
        lpad(cast(round(({{ column_name }} - floor({{ column_name }})) * 1000) as string), 3, '0')
    )
{% endmacro %}