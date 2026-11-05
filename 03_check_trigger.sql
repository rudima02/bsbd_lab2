BEGIN;

DO $$
BEGIN
    IF current_database() <> 'bsbd2' THEN
        RAISE EXCEPTION 'Скрипт предназначен только для базы bsbd2';
    END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS stg.lab2_grade_check (
    grade_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    numeric_value numeric(5,2),
    text_value varchar(50),
    CONSTRAINT ck_lab2_grade_value CHECK (
        (numeric_value IS NOT NULL
         AND text_value IS NULL
         AND numeric_value BETWEEN 0 AND 100)
        OR
        (numeric_value IS NULL
         AND text_value IS NOT NULL
         AND btrim(text_value) <> '')
    )
);

CREATE TABLE IF NOT EXISTS stg.lab2_grade_trigger (
    grade_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    numeric_value numeric(5,2),
    text_value varchar(50)
);

CREATE OR REPLACE FUNCTION stg.lab2_validate_grade()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF NOT (
        (NEW.numeric_value IS NOT NULL
         AND NEW.text_value IS NULL
         AND NEW.numeric_value BETWEEN 0 AND 100)
        OR
        (NEW.numeric_value IS NULL
         AND NEW.text_value IS NOT NULL
         AND btrim(NEW.text_value) <> '')
    ) THEN
        RAISE EXCEPTION 'Некорректное значение оценки'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lab2_validate_grade ON stg.lab2_grade_trigger;
CREATE TRIGGER trg_lab2_validate_grade
BEFORE INSERT OR UPDATE
ON stg.lab2_grade_trigger
FOR EACH ROW
EXECUTE FUNCTION stg.lab2_validate_grade();

COMMIT;
