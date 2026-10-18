create TABLE customers (
id 	serial 	PRIMARY KEY,
name 	text 	NOT NULL,
email	text	NOT NULL UNIQUE,
created_at timestamptz NOT NULL
);

CREATE TABLE orders (
id		serial 		PRIMARY KEY,
customer_id	int		NOT NULL REFERENCES customers (id),
amount		numeric(10,2)	NOT NULL,
status		text		NOT NULL,
created_at	timestamptz	NOT NULL
);

CREATE INDEX orders_customer_id_idx ON orders (customer_id);
