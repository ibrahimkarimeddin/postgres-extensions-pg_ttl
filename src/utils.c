#include "postgres.h"
#include "executor/spi.h"
#include "lib/stringinfo.h"
#include "miscadmin.h"
#include "utils/builtins.h"
#include "utils/elog.h"

#include "pg_ttl_index.h"
#include "utils.h"

bool execute_spi_query(const char *query, int limit)
{
    int ret = SPI_exec(query, limit);
    return (ret == SPI_OK_SELECT && SPI_processed > 0);
}

void cleanup_spi_resources(StringInfoData *query)
{
    if (query && query->data)
        pfree(query->data);
    SPI_finish();
}

bool validate_date_column(const char *table_name, const char *column_name)
{
    StringInfoData query;
    bool is_valid = false;

    if (SPI_connect() != SPI_OK_CONNECT)
        ereport(ERROR, (errmsg("SPI_connect failed")));

    initStringInfo(&query);
    appendStringInfo(&query,
                     "SELECT 1 FROM information_schema.columns "
                     "WHERE table_name = %s AND column_name = %s "
                     "AND data_type IN ('timestamp without time "
                     "zone','timestamp with time zone','date')",
                     quote_literal_cstr(table_name),
                     quote_literal_cstr(column_name));

    is_valid = execute_spi_query(query.data, TTL_QUERY_LIMIT);
    cleanup_spi_resources(&query);

    return is_valid;
}

bool is_ttl_worker_running(void)
{
    StringInfoData query;
    bool is_running = false;

    if (SPI_connect() != SPI_OK_CONNECT)
        return false;

    initStringInfo(&query);
    appendStringInfo(
        &query, "SELECT 1 FROM pg_stat_activity "
                "WHERE datname = current_database() "
                "AND application_name LIKE '" TTL_WORKER_NAME_PREFIX "%%'");

    is_running = execute_spi_query(query.data, TTL_QUERY_LIMIT);
    cleanup_spi_resources(&query);

    return is_running;
}
