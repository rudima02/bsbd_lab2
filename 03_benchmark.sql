\set ON_ERROR_STOP on

DO $$
BEGIN
    IF current_database() <> 'bsbd2' THEN
        RAISE EXCEPTION 'Измерения разрешены только в bsbd2';
    END IF;
END;
$$;

TRUNCATE TABLE stg.lab2_grade_check RESTART IDENTITY;
TRUNCATE TABLE stg.lab2_grade_trigger RESTART IDENTITY;

\echo CHECK: вставка 10000 строк
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO stg.lab2_grade_check (numeric_value, text_value)
SELECT (g.n % 101)::numeric, NULL::varchar(50)
FROM generate_series(1, 10000) AS g(n);

\echo TRIGGER: вставка 10000 строк
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO stg.lab2_grade_trigger (numeric_value, text_value)
SELECT (g.n % 101)::numeric, NULL::varchar(50)
FROM generate_series(1, 10000) AS g(n);

SELECT 'CHECK' AS method, COUNT(*) AS total_rows
FROM stg.lab2_grade_check
UNION ALL
SELECT 'TRIGGER', COUNT(*)
FROM stg.lab2_grade_trigger;
