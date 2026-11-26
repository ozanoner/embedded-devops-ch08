#include "secret_store.h"

#include "esp_log.h"
#include "nvs.h"
#include "nvs_flash.h"

#define SECRETS_NAMESPACE "secrets"
#define KEY_WIFI_SSID "wifi_ssid"
#define KEY_WIFI_PASS "wifi_pass"
#define KEY_SPOTFLOW_DEV_ID "sf_id"
#define KEY_SPOTFLOW_INGEST_KEY "sf_key"

esp_err_t SecretStore_get_wifi(char *ssid, char *password)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(SECRETS_NAMESPACE, NVS_READONLY, &handle);
    if (err != ESP_OK)
    {
        return err;
    }

    size_t length = STORE_SIZE;
    err = nvs_get_str(handle, KEY_WIFI_SSID, ssid, &length);
    if (err == ESP_OK)
    {
        length = STORE_SIZE;
        err = nvs_get_str(handle, KEY_WIFI_PASS, password, &length);
    }

    nvs_close(handle);
    return err;
}

esp_err_t SecretStore_get_spotflow(char *device_id, char *ingest_key)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(SECRETS_NAMESPACE, NVS_READONLY, &handle);
    if (err != ESP_OK)
    {
        return err;
    }

    size_t length = STORE_SIZE;
    err = nvs_get_str(handle, KEY_SPOTFLOW_DEV_ID, device_id, &length);
    if (err == ESP_OK)
    {
        length = STORE_SIZE;
        err = nvs_get_str(handle, KEY_SPOTFLOW_INGEST_KEY, ingest_key, &length);
    }

    nvs_close(handle);
    return err;
}
