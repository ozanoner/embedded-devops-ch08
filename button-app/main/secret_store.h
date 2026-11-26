#pragma once

#include <stddef.h>
#include "esp_err.h"

#define STORE_SIZE 128

esp_err_t SecretStore_get_wifi(char *ssid, char *password);
esp_err_t SecretStore_get_spotflow(char *device_id, char *ingest_key);
