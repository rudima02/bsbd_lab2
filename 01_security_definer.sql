BEGIN;

DO $$
BEGIN
    IF current_database() <> 'bsbd2' THEN
        RAISE EXCEPTION 'Скрипт предназначен только для базы bsbd2';
    END IF;
END;
$$;

GRANT CREATE ON SCHEMA app TO lab2_function_owner;

CREATE OR REPLACE FUNCTION app.enroll_student(
    p_student_id bigint,
    p_offering_id bigint
)
RETURNS TABLE (
    success boolean,
    enrollment_id bigint,
    message text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_group_id bigint;
    v_status varchar(30);
    v_offering_group_id bigint;
    v_error text;
BEGIN
    success := false;
    enrollment_id := NULL;

    BEGIN
        IF p_student_id IS NULL OR p_student_id <= 0 THEN
            RAISE EXCEPTION 'Некорректный идентификатор студента';
        END IF;

        IF p_offering_id IS NULL OR p_offering_id <= 0 THEN
            RAISE EXCEPTION 'Некорректный идентификатор занятия';
        END IF;

        SELECT group_id, status
        INTO v_group_id, v_status
        FROM app.student
        WHERE student_id = p_student_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Студент не найден';
        END IF;

        IF v_status <> 'ACTIVE' THEN
            RAISE EXCEPTION 'Зачисление разрешено только активным студентам';
        END IF;

        SELECT group_id
        INTO v_offering_group_id
        FROM app.course_offering
        WHERE offering_id = p_offering_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Учебное занятие не найдено';
        END IF;

        IF v_group_id <> v_offering_group_id THEN
            RAISE EXCEPTION 'Группа студента не соответствует группе занятия';
        END IF;

        INSERT INTO app.enrollment AS e (student_id, offering_id)
        VALUES (p_student_id, p_offering_id)
        RETURNING e.enrollment_id INTO enrollment_id;

        success := true;
        message := 'Студент успешно зачислен';

    EXCEPTION
        WHEN raise_exception THEN
            message := SQLERRM;
        WHEN unique_violation THEN
            message := 'Студент уже зачислен на занятие';
        WHEN OTHERS THEN
            v_error := SQLERRM;
            message := 'Внутренняя ошибка зачисления';
    END;

    INSERT INTO audit.function_calls (
        function_name, caller_role, input_params, success, message
    )
    VALUES (
        'app.enroll_student',
        COALESCE(NULLIF(current_setting('role', true), 'none'), session_user::text)::name,
        jsonb_build_object(
            'student_id', p_student_id,
            'offering_id', p_offering_id
        ),
        success,
        COALESCE(v_error, message)
    );

    RETURN NEXT;
END;
$$;



CREATE OR REPLACE FUNCTION app.assign_grade(
    p_enrollment_id bigint,
    p_type_id smallint,
    p_number numeric DEFAULT NULL,
    p_text text DEFAULT NULL
)
RETURNS TABLE(success boolean, grade_id bigint, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_scale text;
    v_id bigint;
    v_success boolean := false;
    v_message text;
BEGIN
    BEGIN
        IF p_enrollment_id IS NULL OR p_enrollment_id <= 0 THEN
            RAISE EXCEPTION 'Некорректный идентификатор зачисления';
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM app.enrollment e
            WHERE e.enrollment_id = p_enrollment_id
        ) THEN
            RAISE EXCEPTION 'Зачисление не найдено';
        END IF;

        SELECT a.grading_scale INTO v_scale
        FROM ref.assessment_type a
        WHERE a.assessment_type_id = p_type_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Тип оценивания не найден';
        END IF;

        IF (
            (v_scale = 'FIVE_POINT' AND p_number IN (2,3,4,5) AND p_text IS NULL)
            OR (v_scale = 'PASS_FAIL' AND p_number IS NULL
                AND p_text IN ('Зачтено', 'Не зачтено'))
            OR (v_scale = 'PERCENT' AND p_number BETWEEN 0 AND 100
                AND p_text IS NULL)
        ) IS NOT TRUE THEN
            RAISE EXCEPTION 'Оценка не соответствует шкале';
        END IF;

        INSERT INTO app.grade AS g (
            enrollment_id, assessment_type_id, numeric_value, text_value
        )
        VALUES (p_enrollment_id, p_type_id, p_number, p_text)
        RETURNING g.grade_id INTO v_id;

        v_success := true;
        v_message := 'Оценка успешно выставлена';

    EXCEPTION
        WHEN raise_exception THEN v_message := SQLERRM;
        WHEN OTHERS THEN v_message := 'Ошибка сохранения оценки';
    END;

    INSERT INTO audit.function_calls (
        function_name, caller_role, input_params, success, message
    )
    VALUES (
        'app.assign_grade',
        COALESCE(NULLIF(current_setting('role', true), 'none'), session_user::text)::name,
        jsonb_build_object(
            'enrollment_id', p_enrollment_id,
            'type_id', p_type_id,
            'number', p_number,
            'text', p_text
        ),
        v_success, v_message
    );

    RETURN QUERY SELECT v_success, v_id, v_message;
END;
$$;



CREATE OR REPLACE FUNCTION app.update_student_status(
    p_student_id bigint,
    p_new_status varchar(30)
)
RETURNS TABLE(success boolean, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_old_status varchar(30);
    v_success boolean := false;
    v_message text;
BEGIN
    BEGIN
        IF p_student_id IS NULL OR p_student_id <= 0 THEN
            RAISE EXCEPTION 'Некорректный идентификатор студента';
        END IF;

        IF p_new_status IS NULL OR p_new_status NOT IN
            ('ACTIVE', 'ACADEMIC_LEAVE', 'GRADUATED', 'EXPELLED') THEN
            RAISE EXCEPTION 'Недопустимый статус студента';
        END IF;

        SELECT s.status INTO v_old_status
        FROM app.student AS s
        WHERE s.student_id = p_student_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Студент не найден';
        END IF;

        IF NOT (
            (v_old_status = 'ACTIVE'
                AND p_new_status IN
                ('ACADEMIC_LEAVE', 'GRADUATED', 'EXPELLED'))
            OR
            (v_old_status = 'ACADEMIC_LEAVE'
                AND p_new_status IN ('ACTIVE', 'EXPELLED'))
        ) THEN
            RAISE EXCEPTION 'Переход между статусами запрещён';
        END IF;

        UPDATE app.student
        SET status = p_new_status
        WHERE student_id = p_student_id;

        v_success := true;
        v_message := 'Статус студента успешно изменён';

    EXCEPTION
        WHEN raise_exception THEN v_message := SQLERRM;
        WHEN OTHERS THEN v_message := 'Ошибка изменения статуса';
    END;

    INSERT INTO audit.function_calls (
        function_name, caller_role, input_params, success, message
    )
    VALUES (
        'app.update_student_status',
        COALESCE(NULLIF(current_setting('role', true), 'none'), session_user::text)::name,
        jsonb_build_object(
            'student_id', p_student_id,
            'new_status', p_new_status
        ),
        v_success, v_message
    );

    RETURN QUERY SELECT v_success, v_message;
END;
$$;

ALTER FUNCTION app.enroll_student(bigint, bigint)
    OWNER TO lab2_function_owner;
ALTER FUNCTION app.assign_grade(bigint, smallint, numeric, text)
    OWNER TO lab2_function_owner;
ALTER FUNCTION app.update_student_status(bigint, varchar)
    OWNER TO lab2_function_owner;

REVOKE ALL ON FUNCTION app.enroll_student(bigint, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION app.assign_grade(bigint, smallint, numeric, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION app.update_student_status(bigint, varchar) FROM PUBLIC;
REVOKE ALL ON FUNCTION app.enroll_student(bigint, bigint)
    FROM lab2_reader, lab2_auditor;
REVOKE ALL ON FUNCTION app.assign_grade(bigint, smallint, numeric, text)
    FROM lab2_reader, lab2_auditor;
REVOKE ALL ON FUNCTION app.update_student_status(bigint, varchar)
    FROM lab2_reader, lab2_auditor;

GRANT EXECUTE ON FUNCTION app.enroll_student(bigint, bigint) TO lab2_writer;
GRANT EXECUTE ON FUNCTION app.assign_grade(bigint, smallint, numeric, text) TO lab2_writer;
GRANT EXECUTE ON FUNCTION app.update_student_status(bigint, varchar) TO lab2_writer;

REVOKE CREATE ON SCHEMA app FROM lab2_function_owner;

COMMENT ON FUNCTION app.enroll_student(bigint,bigint)
    IS 'Безопасное зачисление студента';
COMMENT ON FUNCTION app.assign_grade(bigint,smallint,numeric,text)
    IS 'Выставление оценки по выбранной шкале';
COMMENT ON FUNCTION app.update_student_status(bigint,varchar)
    IS 'Переходы между допустимыми статусами студента';

COMMIT;
