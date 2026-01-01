#include "postgres.h"

#include "executor/spi.h"
#include "lib/stringinfo.h"

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
