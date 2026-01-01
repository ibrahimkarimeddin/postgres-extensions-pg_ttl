#include "postgres.h"
#include "access/xact.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "pgstat.h"
#include "postmaster/bgworker.h"
#include "storage/ipc.h"
#include "storage/latch.h"
#include "storage/proc.h"
#include "utils/elog.h"
#include "utils/guc.h"
#include "utils/snapmgr.h"

#include "pg_ttl_index.h"
#include "utils.h"

/* Externs needed by Postgres to find the function */
PGDLLEXPORT void ttl_worker_main(Datum main_arg);

static volatile sig_atomic_t got_SIGTERM = false;
static volatile sig_atomic_t got_SIGHUP = false;

/* Static function declarations */
static void ttl_sigterm_handler(SIGNAL_ARGS);
static void ttl_sighup_handler(SIGNAL_ARGS);
static void initialize_worker_signals(void);
static void initialize_worker_database_connection(Oid database_id);
static void set_worker_application_name(Oid database_id);
static bool should_perform_cleanup(int wait_result);
static bool can_perform_cleanup(void);
static void perform_ttl_cleanup(void);
static void handle_cleanup_error(void);

static void ttl_sigterm_handler(SIGNAL_ARGS)
{
    int save_errno = errno;
    got_SIGTERM = true;
    SetLatch(MyLatch);
    errno = save_errno;
}

static void ttl_sighup_handler(SIGNAL_ARGS)
{
    int save_errno = errno;
    got_SIGHUP = true;
    SetLatch(MyLatch);
    errno = save_errno;
}

void ttl_worker_main(Datum main_arg)
{
    Oid database_id = DatumGetObjectId(main_arg);

    initialize_worker_signals();
    initialize_worker_database_connection(database_id);
    set_worker_application_name(database_id);

    while (!got_SIGTERM) {
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
                                (long)ttl_naptime * TTL_MILLISECONDS_PER_SECOND,
                                PG_WAIT_EXTENSION);

        if (got_SIGTERM)
            break;

        if (got_SIGHUP) {
            got_SIGHUP = false;
            ProcessConfigFile(PGC_SIGHUP);
        }

#if PG_VERSION_NUM < 100000
        if (wait_result & WL_POSTMASTER_DEATH)
            proc_exit(1);
#endif

        should_cleanup = should_perform_cleanup(wait_result);

        if (should_cleanup && can_perform_cleanup()) {
            perform_ttl_cleanup();
        }
    }

    proc_exit(0);
}

static void initialize_worker_signals(void)
{
    pqsignal(SIGTERM, ttl_sigterm_handler);
    pqsignal(SIGHUP, ttl_sighup_handler);
    BackgroundWorkerUnblockSignals();
}

static void initialize_worker_database_connection(Oid database_id)
{
    if (database_id == InvalidOid)
        elog(ERROR, "TTL background worker: invalid database OID");

    BackgroundWorkerInitializeConnectionByOid(database_id, InvalidOid, 0);
}

static void set_worker_application_name(Oid database_id)
{
    char appname[BGW_MAXLEN];
    snprintf(appname, sizeof(appname), TTL_WORKER_NAME_PREFIX "%u",
             database_id);
    pgstat_report_appname(appname);
}

static bool should_perform_cleanup(int wait_result)
{
    if (wait_result & WL_TIMEOUT)
        return true;
    else if (wait_result & WL_LATCH_SET)
        return false; /* Only cleanup on timeout, not on signals */
    else
        return true; /* Be safe and run cleanup */
}

static bool can_perform_cleanup(void)
{
    return ttl_worker_enabled && !RecoveryInProgress();
}

static void perform_ttl_cleanup(void)
{
    PG_TRY();
    {
        int ret;

        StartTransactionCommand();

        if (SPI_connect() != SPI_OK_CONNECT)
            ereport(ERROR, (errmsg("TTL worker: SPI_connect failed")));

        PushActiveSnapshot(GetTransactionSnapshot());

        ret = SPI_exec(
            "SELECT 1 FROM pg_extension WHERE extname = '" TTL_EXTENSION_NAME
            "'",
            TTL_QUERY_LIMIT);
        if (ret == SPI_OK_SELECT && SPI_processed > 0) {
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

static void handle_cleanup_error(void)
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

void configure_background_worker(BackgroundWorker *worker)
{
    memset(worker, 0, sizeof(BackgroundWorker));

    worker->bgw_flags =
        BGWORKER_SHMEM_ACCESS | BGWORKER_BACKEND_DATABASE_CONNECTION;
    worker->bgw_start_time = BgWorkerStart_RecoveryFinished;
    worker->bgw_restart_time = BGW_NEVER_RESTART;
    worker->bgw_notify_pid = MyProcPid;
    worker->bgw_main_arg = ObjectIdGetDatum(MyDatabaseId);

    snprintf(worker->bgw_library_name, BGW_MAXLEN, TTL_LIBRARY_NAME);
    snprintf(worker->bgw_function_name, BGW_MAXLEN, TTL_MAIN_FUNCTION_NAME);
    snprintf(worker->bgw_name, BGW_MAXLEN, TTL_WORKER_NAME_PREFIX "%u",
             MyDatabaseId);
    snprintf(worker->bgw_type, BGW_MAXLEN, TTL_WORKER_TYPE);
}
