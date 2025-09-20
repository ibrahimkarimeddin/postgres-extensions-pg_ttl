EXTENSION = pg_ttl_index
MODULE_big = pg_ttl_index
OBJS = pg_ttl_index.o

DATA = pg_ttl_index--1.0.sql
PGFILEDESC = "TTL index extension for automatic data expiration"

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)