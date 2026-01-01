#ifndef PG_TTL_INDEX_UTILS_H
#define PG_TTL_INDEX_UTILS_H

#include "lib/stringinfo.h"
#include "postgres.h"

/* SPI Helper functions */
bool execute_spi_query(const char *query, int limit);
void cleanup_spi_resources(StringInfoData *query);

/* Logic helpers */
bool validate_date_column(const char *table_name, const char *column_name);
bool is_ttl_worker_running(void);

#endif /* PG_TTL_INDEX_UTILS_H */
