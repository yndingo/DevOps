-- Порция записей, имитирующая работу приложения ПОСЛЕ последнего бэкапа.
-- now() здесь правильный выбор: эти строки созданы, чтобы быть ПОТЕРЯННЫМИ.
INSERT INTO orders (customer_id, amount, status, created_at)
SELECT (i % 50) + 1,
       42.00,
       'new',
       now()
FROM generate_series(1, 25) AS i;
