#ifndef PG_TTL_INDEX_H
#define PG_TTL_INDEX_H

#include "postgres.h"
#include "postmaster/bgworker.h"

/* Configuration constants */
#define TTL_DEFAULT_NAPTIME_SECONDS 60
#define TTL_NAPTIME_MIN_SECONDS 1
#define TTL_MILLISECONDS_PER_SECOND 1000L
#define TTL_EXTENSION_NAME "pg_ttl_index"
#define TTL_WORKER_NAME_PREFIX "TTL Worker DB "
#define TTL_WORKER_TYPE "TTL Index Worker"
#define TTL_LIBRARY_NAME "pg_ttl_index"
#define TTL_MAIN_FUNCTION_NAME "ttl_worker_main"
#define TTL_QUERY_LIMIT 1

/* Global configuration variables */
extern int ttl_naptime;
extern bool ttl_worker_enabled;

/* Shared function declarations for background worker */
void configure_background_worker(BackgroundWorker *worker);

#endif /* PG_TTL_INDEX_H */
