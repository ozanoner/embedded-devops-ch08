
#pragma once

#include <stddef.h>
#include "esp_err.h"

esp_err_t LogHistory_init(void);
void LogHistory_disable(void);
void LogHistory_dump(void);
esp_err_t LogHistory_flash_init(void);
void LogHistory_flash_print(void);