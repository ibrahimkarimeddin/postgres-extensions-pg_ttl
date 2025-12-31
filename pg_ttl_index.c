/*-------------------------------------------------------------------------
 *
 * pg_ttl_index.c
 *		PostgreSQL extension for automatic Time-To-Live (TTL) data expiration
 *
 * This extension provides automatic deletion of expired rows based on
 * timestamp columns. It manages TTL configurations per table/column and
 * runs a background worker process to periodically clean up expired data.
 *
 * Key Features:
 *   - Automatic data expiration based on timestamp columns
 *   - Background worker for periodic cleanup
 *   - Support for multiple tables with different TTL settings
 *   - Configurable cleanup intervals
 *   - ACID-compliant with proper SQL injection protection
 *
 * Background Worker:
 *   The extension uses PostgreSQL's background worker infrastructure to
 *   run periodic cleanup jobs. The worker must be manually started using
 *   ttl_start_worker() and will run until explicitly stopped or PostgreSQL
 *   is restarted.
 *
 * Configuration Parameters:
 *   pg_ttl_index.naptime - Seconds between cleanup runs (default: 60)
 *   pg_ttl_index.enabled - Enable/disable background worker (default: true)
 *
 * Public Functions:
 *   ttl_create_index(table_name, column_name, expire_seconds) - Create TTL
 *   ttl_drop_index(table_name, column_name) - Remove TTL
 *   ttl_start_worker() - Start background worker
 *   ttl_stop_worker() - Stop background worker
 *   ttl_runner() - Manually trigger cleanup (called by worker)
 *
 * Copyright (c) 2024, pg_ttl_index Contributors
 * Licensed under the PostgreSQL License
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "utils/timestamp.h"
#include "executor/spi.h"
#include "access/htup_details.h"
#include "catalog/pg_type.h"
#include "miscadmin.h"
#include "storage/proc.h"
#include "postmaster/bgworker.h"
#include "storage/ipc.h"
#include "storage/latch.h"
#include "utils/guc.h"
#include "tcop/utility.h"
#include "utils/snapmgr.h"
#include "access/xact.h"
#include "utils/wait_event.h"
#include "utils/elog.h"
#include "nodes/pg_list.h"
#include "utils/memutils.h"
#include "pgstat.h" 

PG_MODULE_MAGIC;

#define TTL_DEFAULT_NAPTIME_SECONDS 60
#define TTL_NAPTIME_MIN_SECONDS 1
#define TTL_MILLISECONDS_PER_SECOND 1000L
#define TTL_EXTENSION_NAME "pg_ttl_index"
#define TTL_WORKER_NAME_PREFIX "TTL Worker DB "
#define TTL_WORKER_TYPE "TTL Index Worker"
#define TTL_LIBRARY_NAME "pg_ttl_index"
#define TTL_MAIN_FUNCTION_NAME "ttl_worker_main"
#define TTL_QUERY_LIMIT 1

static int  ttl_naptime = TTL_DEFAULT_NAPTIME_SECONDS;
static bool ttl_worker_enabled = true;
static volatile sig_atomic_t got_SIGTERM = false;
static volatile sig_atomic_t got_SIGHUP  = false;

static void ttl_sigterm_handler(SIGNAL_ARGS);
static void ttl_sighup_handler(SIGNAL_ARGS);

void _PG_init(void);
PGDLLEXPORT void ttl_worker_main(Datum main_arg);

PG_FUNCTION_INFO_V1(ttl_create_index);
PG_FUNCTION_INFO_V1(ttl_drop_index);
PG_FUNCTION_INFO_V1(ttl_start_worker);
PG_FUNCTION_INFO_V1(ttl_stop_worker);

static bool validate_date_column(const char *table_name, const char *column_name);
static bool is_ttl_worker_running(void);
static void initialize_worker_signals(void);
static void initialize_worker_database_connection(Oid database_id);
static void set_worker_application_name(Oid database_id);
static bool should_perform_cleanup(int wait_result);
static bool can_perform_cleanup(void);
static void perform_ttl_cleanup(void);
static void handle_cleanup_error(void);
static void configure_background_worker(BackgroundWorker *worker);
static bool execute_spi_query(const char *query, int limit);
static void cleanup_spi_resources(StringInfoData *query);


static void
ttl_sigterm_handler(SIGNAL_ARGS)
{
    int save_errno = errno;
    got_SIGTERM = true;
    SetLatch(MyLatch);
    errno = save_errno;
}

static void
ttl_sighup_handler(SIGNAL_ARGS)
{
    int save_errno = errno;
    got_SIGHUP = true;
    SetLatch(MyLatch);
    errno = save_errno;
}


void
_PG_init(void)
{
    DefineCustomIntVariable("pg_ttl_index.naptime",
                            "Duration between TTL cleanup runs (seconds)",
                            NULL,
                            &ttl_naptime,
                            TTL_DEFAULT_NAPTIME_SECONDS,
                            TTL_NAPTIME_MIN_SECONDS,
                            INT_MAX,
                            PGC_SIGHUP,
                            0,
                            NULL, NULL, NULL);

    DefineCustomBoolVariable("pg_ttl_index.enabled",
                             "Enable TTL background worker",
                             NULL,
                             &ttl_worker_enabled,
                             true,
                             PGC_SIGHUP,
                             0,
                             NULL, NULL, NULL);
}


PGDLLEXPORT void
ttl_worker_main(Datum main_arg)
{
    Oid database_id = DatumGetObjectId(main_arg);

    initialize_worker_signals();
    initialize_worker_database_connection(database_id);
    set_worker_application_name(database_id);

    while (!got_SIGTERM)
    {
        int wait_result;
        bool should_cleanup;

        ResetLatch(MyLatch);
        CHECK_FOR_INTERRUPTS();

        wait_result = WaitLatch(MyLatch,
#if PG_VERSION_NUM >= 100000
                               WL_LATCH_SET | WL_TIMEOUT | WL_EXIT_ON_PM_DEATH,
#else
                               WL_LATCH_SET | WL_TIMEOUT | WL_POSTMASTER_DEATH,
#endif
                               (long) ttl_naptime * TTL_MILLISECONDS_PER_SECOND,
                               PG_WAIT_EXTENSION);

        if (got_SIGTERM)
            break;

        if (got_SIGHUP)
        {
            got_SIGHUP = false;
            ProcessConfigFile(PGC_SIGHUP);
        }

#if PG_VERSION_NUM < 100000
        if (wait_result & WL_POSTMASTER_DEATH)
            proc_exit(1);
#endif

        should_cleanup = should_perform_cleanup(wait_result);
        
        if (should_cleanup && can_perform_cleanup())
        {
            perform_ttl_cleanup();
        }
    }

    proc_exit(0);
}


static void
initialize_worker_signals(void)
{
    pqsignal(SIGTERM, ttl_sigterm_handler);
    pqsignal(SIGHUP, ttl_sighup_handler);
    BackgroundWorkerUnblockSignals();
}

static void
initialize_worker_database_connection(Oid database_id)
{
    if (database_id == InvalidOid)
        elog(ERROR, "TTL background worker: invalid database OID");

    BackgroundWorkerInitializeConnectionByOid(database_id, InvalidOid, 0);
}

static void
set_worker_application_name(Oid database_id)
{
    char appname[BGW_MAXLEN];
    snprintf(appname, sizeof(appname), TTL_WORKER_NAME_PREFIX "%u", database_id);
    pgstat_report_appname(appname);
}

static bool
should_perform_cleanup(int wait_result)
{
    if (wait_result & WL_TIMEOUT)
        return true;
    else if (wait_result & WL_LATCH_SET)
        return false; /* Only cleanup on timeout, not on signals */
    else
        return true; /* Be safe and run cleanup */
}

static bool
can_perform_cleanup(void)
{
    return ttl_worker_enabled && !RecoveryInProgress();
}

static void
perform_ttl_cleanup(void)
{
    PG_TRY();
    {
        int ret;
        
        StartTransactionCommand();
        
        if (SPI_connect() != SPI_OK_CONNECT)
            ereport(ERROR, (errmsg("TTL worker: SPI_connect failed")));
        
        PushActiveSnapshot(GetTransactionSnapshot());

        ret = SPI_exec("SELECT 1 FROM pg_extension WHERE extname = '" TTL_EXTENSION_NAME "'", TTL_QUERY_LIMIT);
        if (ret == SPI_OK_SELECT && SPI_processed > 0)
        {
            SPI_exec("SELECT ttl_runner()", TTL_QUERY_LIMIT);
        }

        PopActiveSnapshot();
        SPI_finish();
        CommitTransactionCommand();
    }
    PG_CATCH();
    {
        handle_cleanup_error();
    }
    PG_END_TRY();
}

static void
handle_cleanup_error(void)
{
    ErrorData *edata;
    
    edata = CopyErrorData();
    FlushErrorState();
    FreeErrorData(edata);

    PG_TRY();
    {
        if (SPI_tuptable != NULL)
            SPI_finish();
    }
    PG_CATCH();
    {
        FlushErrorState();
    }
    PG_END_TRY();

    AbortCurrentTransaction();
}


static bool
execute_spi_query(const char *query, int limit)
{
    int ret = SPI_exec(query, limit);
    return (ret == SPI_OK_SELECT && SPI_processed > 0);
}

static void
cleanup_spi_resources(StringInfoData *query)
{
    if (query && query->data)
        pfree(query->data);
    SPI_finish();
}

static bool
validate_date_column(const char *table_name, const char *column_name)
{
    StringInfoData query;
    bool is_valid = false;

    if (SPI_connect() != SPI_OK_CONNECT)
        ereport(ERROR, (errmsg("SPI_connect failed")));

    initStringInfo(&query);
    appendStringInfo(&query,
        "SELECT 1 FROM information_schema.columns "
        "WHERE table_name = %s AND column_name = %s "
        "AND data_type IN ('timestamp without time zone','timestamp with time zone','date')",
        quote_literal_cstr(table_name), quote_literal_cstr(column_name));

    is_valid = execute_spi_query(query.data, TTL_QUERY_LIMIT);
    cleanup_spi_resources(&query);
    
    return is_valid;
}

static bool
is_ttl_worker_running(void)
{
    StringInfoData query;
    bool is_running = false;

    if (SPI_connect() != SPI_OK_CONNECT)
        return false;

    initStringInfo(&query);
    appendStringInfo(&query,
        "SELECT 1 FROM pg_stat_activity "
        "WHERE datname = current_database() "
        "AND application_name LIKE '" TTL_WORKER_NAME_PREFIX "%%'");

    is_running = execute_spi_query(query.data, TTL_QUERY_LIMIT);
    cleanup_spi_resources(&query);
    
    return is_running;
}

static void
configure_background_worker(BackgroundWorker *worker)
{
    memset(worker, 0, sizeof(BackgroundWorker));

    worker->bgw_flags        = BGWORKER_SHMEM_ACCESS | BGWORKER_BACKEND_DATABASE_CONNECTION;
    worker->bgw_start_time   = BgWorkerStart_RecoveryFinished;
    worker->bgw_restart_time = BGW_NEVER_RESTART;
    worker->bgw_notify_pid   = MyProcPid;
    worker->bgw_main_arg     = ObjectIdGetDatum(MyDatabaseId);

    snprintf(worker->bgw_library_name,  BGW_MAXLEN, TTL_LIBRARY_NAME);
    snprintf(worker->bgw_function_name, BGW_MAXLEN, TTL_MAIN_FUNCTION_NAME);
    snprintf(worker->bgw_name,          BGW_MAXLEN, TTL_WORKER_NAME_PREFIX "%u", MyDatabaseId);
    snprintf(worker->bgw_type,          BGW_MAXLEN, TTL_WORKER_TYPE);
}
        

Datum
ttl_create_index(PG_FUNCTION_ARGS)
{
    text *table_name_text   = PG_GETARG_TEXT_PP(0);
    text *column_name_text  = PG_GETARG_TEXT_PP(1);
    int32 expire_after_sec  = PG_GETARG_INT32(2);

    char *table_name  = text_to_cstring(table_name_text);
    char *column_name = text_to_cstring(column_name_text);

    StringInfoData query;
    int ret;
    bool success = false;

    if (!validate_date_column(table_name, column_name))
        ereport(ERROR, (errmsg("column %s.%s must be date/timestamp",
                               table_name, column_name)));

    if (SPI_connect() != SPI_OK_CONNECT)
        ereport(ERROR, (errmsg("SPI_connect failed")));

    initStringInfo(&query);
    appendStringInfo(&query,
        "INSERT INTO ttl_index_table (table_name, column_name, expire_after_seconds, active, created_at) "
        "VALUES (%s, %s, %d, true, NOW()) "
        "ON CONFLICT (table_name, column_name) DO UPDATE SET "
        "expire_after_seconds = EXCLUDED.expire_after_seconds, "
        "active = true, "
        "updated_at = NOW()",
        quote_literal_cstr(table_name), quote_literal_cstr(column_name), expire_after_sec);

    ret = SPI_exec(query.data, 0);
    success = (ret == SPI_OK_INSERT || ret == SPI_OK_UPDATE || ret == SPI_OK_UTILITY);

    cleanup_spi_resources(&query);

    PG_RETURN_BOOL(success);
}

Datum
ttl_drop_index(PG_FUNCTION_ARGS)
{
    text *table_name_text  = PG_GETARG_TEXT_PP(0);
    text *column_name_text = PG_GETARG_TEXT_PP(1);
    char *table_name  = text_to_cstring(table_name_text);
    char *column_name = text_to_cstring(column_name_text);

    StringInfoData query;
    int ret;
    bool success = false;

    if (SPI_connect() != SPI_OK_CONNECT)
        ereport(ERROR, (errmsg("SPI_connect failed")));

    initStringInfo(&query);
    appendStringInfo(&query,
        "DELETE FROM ttl_index_table WHERE table_name = %s AND column_name = %s",
        quote_literal_cstr(table_name), quote_literal_cstr(column_name));

    ret = SPI_exec(query.data, 0);
    success = (ret == SPI_OK_DELETE && SPI_processed > 0);

    cleanup_spi_resources(&query);

    PG_RETURN_BOOL(success);
}

Datum
ttl_start_worker(PG_FUNCTION_ARGS)
{
    BackgroundWorker worker;
    BackgroundWorkerHandle *handle;
    pid_t pid;

    if (RecoveryInProgress())
        ereport(ERROR,
                (errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
                 errmsg("cannot start TTL worker during recovery")));

    if (is_ttl_worker_running())
        PG_RETURN_BOOL(true);

    configure_background_worker(&worker);

    if (!RegisterDynamicBackgroundWorker(&worker, &handle))
        PG_RETURN_BOOL(false);

    switch (WaitForBackgroundWorkerStartup(handle, &pid))
    {
        case BGWH_STARTED:
            PG_RETURN_BOOL(true);
        case BGWH_STOPPED:
            PG_RETURN_BOOL(false);
        case BGWH_POSTMASTER_DIED:
            elog(ERROR, "postmaster died while starting TTL background worker");
            PG_RETURN_BOOL(false);
        default:
            elog(ERROR, "unknown background worker startup result");
            PG_RETURN_BOOL(false);
    }
}

Datum
ttl_stop_worker(PG_FUNCTION_ARGS)
{
    StringInfoData query;
    int ret;
    bool stopped = false;

    if (SPI_connect() != SPI_OK_CONNECT)
        ereport(ERROR, (errmsg("SPI_connect failed")));

    initStringInfo(&query);
    appendStringInfo(&query,
        "SELECT pg_terminate_backend(pid) "
        "FROM pg_stat_activity "
        "WHERE datname = current_database() "
        "AND application_name LIKE '" TTL_WORKER_NAME_PREFIX "%%'");

    ret = SPI_exec(query.data, 0);
    stopped = (ret == SPI_OK_SELECT && SPI_processed > 0);

    cleanup_spi_resources(&query);

    PG_RETURN_BOOL(stopped);
}
