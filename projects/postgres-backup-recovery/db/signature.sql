SET TIME ZONE 'UTC';

SELECT 'customers' AS table_name,
	count(*) AS row_count,
	md5(COALESCE(string_agg(md5(concat_ws('|', id, name, email, created_at::timestamptz::text)),
		'' ORDER BY id), '')) AS checksum
FROM customers

UNION ALL 

SELECT 'orders' AS table_name,
        count(*) AS row_count,
        md5(COALESCE(string_agg(md5(concat_ws('|', id, customer_id, amount, status, created_at::timestamptz::text)),
                '' ORDER BY id), '')) AS checksum
FROM orders

ORDER BY table_name
;
