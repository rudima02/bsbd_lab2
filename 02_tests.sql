\set ON_ERROR_STOP on
\echo Тесты ЛР2. База bsbd2

RESET ROLE;

DO $$
BEGIN
    IF current_database() <> 'bsbd2' THEN
        RAISE EXCEPTION 'Тесты разрешено запускать только в bsbd2';
    END IF;
END;
$$;

SET ROLE lab2_reader;
SELECT offering_id, discipline_id, teacher_id, group_id
FROM app.course_offering
LIMIT 5;
RESET ROLE;

SET ROLE lab2_reader;
DO $$
BEGIN
    PERFORM 1 FROM app.personal_file LIMIT 1;
    RAISE EXCEPTION 'FAIL: lab2_reader получил доступ к личным делам';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: чтение личных дел запрещено';
END;
$$;
RESET ROLE;

SET ROLE lab2_writer;
DO $$
BEGIN
    EXECUTE 'CREATE TABLE app.lab2_forbidden_ddl (id bigint)';
    RAISE EXCEPTION 'FAIL: создание таблицы разрешено';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: DDL запрещён';
END;
$$;
RESET ROLE;

SET ROLE lab2_writer;
DO $$
BEGIN
    INSERT INTO audit.function_calls
        (function_name, caller_role, input_params, success)
    VALUES ('manual', 'lab2_writer', '{}'::jsonb, true);
    RAISE EXCEPTION 'FAIL: прямой INSERT в audit разрешён';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: прямой INSERT в audit запрещён';
END;
$$;
RESET ROLE;

SET ROLE lab2_writer;
DO $$
BEGIN
    PERFORM enrollment_id FROM app.enrollment LIMIT 1;
    RAISE EXCEPTION 'FAIL: прямое чтение enrollment разрешено';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: прямое чтение enrollment запрещено';
END;
$$;
RESET ROLE;

SET ROLE lab2_reader;
DO $$
BEGIN
    PERFORM 1 FROM app.enroll_student(NULL::bigint, 1::bigint);
    RAISE EXCEPTION 'FAIL: lab2_reader смог вызвать enroll_student';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS: вызов SECURITY DEFINER читателю запрещён';
END;
$$;
RESET ROLE;

SET ROLE lab2_writer;
SELECT current_user AS acting_role, success, enrollment_id, message
FROM app.enroll_student(NULL::bigint, 1::bigint);
RESET ROLE;

SELECT q.enrollment_id AS invalid_grade_enrollment_id,
       q.assessment_type_id AS percent_type_id
FROM (SELECT 1) AS seed
LEFT JOIN LATERAL (
    SELECT e.enrollment_id, a.assessment_type_id
    FROM app.enrollment AS e
    CROSS JOIN ref.assessment_type AS a
    WHERE a.grading_scale = 'PERCENT'
    ORDER BY e.enrollment_id, a.assessment_type_id
    LIMIT 1
) AS q ON true
\gset
\if :{?invalid_grade_enrollment_id}
SET ROLE lab2_writer;
SELECT current_user AS acting_role, success, grade_id, message
FROM app.assign_grade(:invalid_grade_enrollment_id::bigint, :percent_type_id::smallint, 150::numeric, NULL);
RESET ROLE;
\else
\echo SKIP: нет зачисления или процентной шкалы для отрицательного теста оценки
\endif

SET ROLE lab2_writer;
SELECT current_user AS acting_role, success, message
FROM app.update_student_status(1::bigint, 'SUSPENDED'::varchar);
RESET ROLE;

SELECT q.enrollment_id AS valid_enrollment_id,
       q.assessment_type_id AS valid_type_id
FROM (SELECT 1) AS seed
LEFT JOIN LATERAL (
    SELECT e.enrollment_id, a.assessment_type_id
    FROM app.enrollment AS e
    CROSS JOIN ref.assessment_type AS a
    WHERE a.grading_scale = 'PERCENT'
    ORDER BY e.enrollment_id, a.assessment_type_id
    LIMIT 1
) AS q ON true
\gset
\if :{?valid_enrollment_id}
BEGIN;
SET ROLE lab2_writer;
SELECT current_user AS acting_role, success, grade_id, message
FROM app.assign_grade(:valid_enrollment_id::bigint, :valid_type_id::smallint, 87::numeric, NULL);
RESET ROLE;
ROLLBACK;
\else
\echo SKIP: нет зачисления для положительного теста оценки
\endif

SELECT (
    SELECT student_id FROM app.student
    WHERE status = 'ACTIVE'
    ORDER BY student_id LIMIT 1
) AS active_student_id
\gset
\if :{?active_student_id}
SET ROLE lab2_writer;
SELECT current_user AS acting_role, success, message
FROM app.update_student_status(:active_student_id::bigint, 'ACADEMIC_LEAVE'::varchar);
SELECT current_user AS acting_role, success, message
FROM app.update_student_status(:active_student_id::bigint, 'ACTIVE'::varchar);
RESET ROLE;
\else
\echo SKIP: нет активного студента для проверки перехода статуса
\endif

SELECT q.student_id AS free_student_id, q.offering_id AS free_offering_id
FROM (SELECT 1) AS seed
LEFT JOIN LATERAL (
    SELECT s.student_id, o.offering_id
    FROM app.student AS s
    JOIN app.course_offering AS o ON o.group_id = s.group_id
    WHERE s.status = 'ACTIVE'
      AND NOT EXISTS (
          SELECT 1 FROM app.enrollment AS e
          WHERE e.student_id = s.student_id AND e.offering_id = o.offering_id
      )
    ORDER BY s.student_id, o.offering_id
    LIMIT 1
) AS q ON true
\gset
\if :{?free_student_id}
BEGIN;
SET ROLE lab2_writer;
SELECT current_user AS acting_role, success, enrollment_id, message
FROM app.enroll_student(:free_student_id::bigint, :free_offering_id::bigint);
RESET ROLE;
ROLLBACK;
\else
\echo SKIP: нет доступной незачисленной пары студент/занятие
\endif

SET ROLE lab2_auditor;
SELECT call_id, call_time, function_name, caller_role, success, message
FROM audit.function_calls
ORDER BY call_id DESC
LIMIT 10;
RESET ROLE;

SELECT p.proname AS function_name,
       has_function_privilege('lab2_writer', p.oid, 'EXECUTE') AS writer_execute,
       has_function_privilege('lab2_reader', p.oid, 'EXECUTE') AS reader_execute,
       has_function_privilege('lab2_auditor', p.oid, 'EXECUTE') AS auditor_execute
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'app'
  AND p.proname IN ('enroll_student', 'assign_grade', 'update_student_status')
ORDER BY p.proname;
