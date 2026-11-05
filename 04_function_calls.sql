RESET ROLE;

SELECT
    call_id,
    call_time,
    function_name,
    caller_role,
    input_params,
    success,
    message
FROM audit.function_calls
WHERE function_name IN (
    'app.enroll_student',
    'app.assign_grade',
    'app.update_student_status'
)
ORDER BY call_id DESC
LIMIT 30;

SELECT
    function_name,
    COUNT(*) AS total_calls,
    COUNT(*) FILTER (WHERE success) AS successful_calls,
    COUNT(*) FILTER (WHERE NOT success) AS failed_calls
FROM audit.function_calls
WHERE function_name IN (
    'app.enroll_student',
    'app.assign_grade',
    'app.update_student_status'
)
GROUP BY function_name
ORDER BY function_name;
