#include "postgres.h"

#include "executor/spi.h"
#include "fmgr.h"
#include "postmaster/bgworker.h"

#include "pg_ttl_index.h"
#include "utils.h"

/* V1 Function Definitions - Worker management only */
PG_FUNCTION_INFO_V1(ttl_start_worker);
PG_FUNCTION_INFO_V1(ttl_stop_worker);

Datum ttl_start_worker(PG_FUNCTION_ARGS)
{
    BackgroundWorker worker;
    BackgroundWorkerHandle *handle;
    pid_t pid;

    if (RecoveryInProgress())
        ereport(ERROR, (errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
                        errmsg("cannot start TTL worker during recovery")));

    if (is_ttl_worker_running())
        PG_RETURN_BOOL(true);

    configure_background_worker(&worker);

    if (!RegisterDynamicBackgroundWorker(&worker, &handle))
        PG_RETURN_BOOL(false);

    switch (WaitForBackgroundWorkerStartup(handle, &pid)) {
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

Datum ttl_stop_worker(PG_FUNCTION_ARGS)
{
    StringInfoData query;
    int ret;
    bool stopped = false;

    if (SPI_connect() != SPI_OK_CONNECT)
        ereport(ERROR, (errmsg("SPI_connect failed")));

    initStringInfo(&query);
    appendStringInfo(
        &query, "SELECT pg_terminate_backend(pid) "
                "FROM pg_stat_activity "
                "WHERE datname = current_database() "
                "AND application_name LIKE '" TTL_WORKER_NAME_PREFIX "%%'");

    ret = SPI_exec(query.data, 0);
    stopped = (ret == SPI_OK_SELECT && SPI_processed > 0);

    cleanup_spi_resources(&query);

    PG_RETURN_BOOL(stopped);
}
