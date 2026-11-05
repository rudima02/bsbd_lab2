BEGIN;

DO $$
DECLARE
    v_table text;
BEGIN
    IF current_database() <> 'bsbd2' THEN
        RAISE EXCEPTION 'Скрипт предназначен только для базы bsbd2';
    END IF;

    FOREACH v_table IN ARRAY ARRAY[
        'app.student', 'app.enrollment', 'app.grade',
        'app.course_offering', 'app.personal_file', 'ref.assessment_type'
    ] LOOP
        IF to_regclass(v_table) IS NULL THEN
            RAISE EXCEPTION 'Отсутствует таблица %. Сначала разверните базу первой лабораторной', v_table;
        END IF;
    END LOOP;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lab2_reader') THEN
        CREATE ROLE lab2_reader LOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lab2_writer') THEN
        CREATE ROLE lab2_writer NOLOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lab2_auditor') THEN
        CREATE ROLE lab2_auditor NOLOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lab2_ddl_admin') THEN
        CREATE ROLE lab2_ddl_admin LOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lab2_dml_admin') THEN
        CREATE ROLE lab2_dml_admin LOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lab2_security_admin') THEN
        CREATE ROLE lab2_security_admin LOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lab2_function_owner') THEN
        CREATE ROLE lab2_function_owner NOLOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'audit_owner') THEN
        CREATE ROLE audit_owner NOLOGIN;
    END IF;
END;
$$;

CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS stg;

REVOKE ALL ON DATABASE bsbd2 FROM PUBLIC;
GRANT CONNECT ON DATABASE bsbd2 TO
    lab2_reader, lab2_writer, lab2_auditor,
    lab2_ddl_admin, lab2_dml_admin, lab2_security_admin;

REVOKE CREATE ON SCHEMA app FROM PUBLIC;
REVOKE ALL ON SCHEMA audit FROM PUBLIC;
GRANT USAGE ON SCHEMA app TO lab2_reader, lab2_writer, lab2_function_owner;
GRANT USAGE ON SCHEMA ref TO lab2_function_owner;
GRANT USAGE ON SCHEMA audit TO lab2_function_owner, lab2_auditor;

REVOKE ALL ON app.personal_file, app.student, app.enrollment, app.grade FROM PUBLIC;
REVOKE ALL ON app.personal_file, app.student, app.enrollment, app.grade
    FROM lab2_reader, lab2_writer;
GRANT SELECT ON app.course_offering TO lab2_reader;

GRANT SELECT ON app.student, app.course_offering, app.enrollment,
    app.grade, ref.assessment_type TO lab2_function_owner;
GRANT INSERT ON app.enrollment, app.grade TO lab2_function_owner;
GRANT UPDATE (status) ON app.student TO lab2_function_owner;

GRANT SELECT ON app.discipline, app.teacher, app.study_group,
    app.student, app.course_offering, app.enrollment, ref.assessment_type
    TO app_owner;
GRANT UPDATE (discipline_id) ON app.discipline TO app_owner;
GRANT UPDATE (teacher_id) ON app.teacher TO app_owner;
GRANT UPDATE (group_id) ON app.study_group TO app_owner;
GRANT UPDATE (student_id) ON app.student TO app_owner;
GRANT UPDATE (offering_id) ON app.course_offering TO app_owner;
GRANT UPDATE (enrollment_id) ON app.enrollment TO app_owner;
GRANT UPDATE (assessment_type_id) ON ref.assessment_type TO app_owner;

CREATE TABLE IF NOT EXISTS audit.function_calls (
    call_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    call_time timestamptz NOT NULL DEFAULT clock_timestamp(),
    function_name text NOT NULL,
    caller_role name NOT NULL,
    input_params jsonb NOT NULL,
    success boolean NOT NULL,
    message text
);

ALTER TABLE audit.function_calls OWNER TO audit_owner;
REVOKE ALL ON audit.function_calls FROM PUBLIC, lab2_reader, lab2_writer;
GRANT INSERT ON audit.function_calls TO lab2_function_owner;
GRANT SELECT ON audit.function_calls TO lab2_auditor;

COMMENT ON TABLE audit.function_calls IS
    'Журнал вызовов функций SECURITY DEFINER (лабораторная работа №2)';

COMMIT;
