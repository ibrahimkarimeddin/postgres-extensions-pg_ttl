#include "postgres.h"
#include "fmgr.h"
#include "executor/spi.h"
#include "utils/builtins.h"
#include "miscadmin.h"
#include "postmaster/bgworker.h"

#include "pg_ttl_index.h"
#include "utils.h"

/* V1 Function Definitions */
PG_FUNCTION_INFO_V1(ttl_create_index);
PG_FUNCTION_INFO_V1(ttl_drop_index);
PG_FUNCTION_INFO_V1(ttl_start_worker);
PG_FUNCTION_INFO_V1(ttl_stop_worker);

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
