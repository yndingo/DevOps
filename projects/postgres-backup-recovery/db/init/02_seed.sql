INSERT INTO customers (id, name, email, created_at)
SELECT i,
	'Customer ' || i,
	'customer' || i || '@example.com',
	'2026-01-01 00:00:00+00'::timestamptz + (i * interval '1 hour')
FROM generate_series(1,50) AS i;

INSERT INTO orders (id, customer_id, amount, status, created_at)
SELECT i,
	(i % 50) + 1,
	round ((sin(i) * 100 + 100)::numeric, 2),
	(ARRAY['new', 'paid', 'shipped', 'delivered'])[1 + (i % 4)],
	'2026-01-02 00:00:00+00'::timestamptz + (i * interval '1 minute')
FROM generate_series(1, 500) AS i;

SELECT setval('customers_id_seq', (SELECT max(id) FROM customers));
SELECT setval('orders_id_seq', 	  (Select max(id) FROM orders));
