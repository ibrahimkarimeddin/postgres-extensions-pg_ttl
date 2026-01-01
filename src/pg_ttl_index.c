#include "postgres.h"
#include "fmgr.h"
#include "utils/guc.h"
#include <limits.h>

#include "pg_ttl_index.h"

PG_MODULE_MAGIC;

/* Define gloabl variables */
int ttl_naptime = TTL_DEFAULT_NAPTIME_SECONDS;
bool ttl_worker_enabled = true;

void _PG_init(void);

void _PG_init(void)
{
    DefineCustomIntVariable(
        "pg_ttl_index.naptime", "Duration between TTL cleanup runs (seconds)",
        NULL, &ttl_naptime, TTL_DEFAULT_NAPTIME_SECONDS,
        TTL_NAPTIME_MIN_SECONDS, INT_MAX, PGC_SIGHUP, 0, NULL, NULL, NULL);

    DefineCustomBoolVariable(
        "pg_ttl_index.enabled", "Enable TTL background worker", NULL,
        &ttl_worker_enabled, true, PGC_SIGHUP, 0, NULL, NULL, NULL);
}
