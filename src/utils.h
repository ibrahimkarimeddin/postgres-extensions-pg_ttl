#ifndef UTILS_H
#define UTILS_H

#include <stdbool.h>
#include "lib/stringinfo.h"

/* SPI utility functions */
bool execute_spi_query(const char *query, int limit);
void cleanup_spi_resources(StringInfoData *query);

/* Worker status check */
bool is_ttl_worker_running(void);

#endif /* UTILS_H */
