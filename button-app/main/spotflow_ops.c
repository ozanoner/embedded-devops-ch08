
#include "spotflow_ops.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_log.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "metrics/spotflow_metrics_backend.h"
#include "net/spotflow_mqtt.h"

static const char *LOG_TAG = "sf-ops";

static bool s_mqtt_connected = false;
static bool s_init_done = false;

static void spotflow_ops_event(void *arg, esp_event_base_t base, int32_t event_id, void *data)
{
    s_mqtt_connected = (event_id == MQTT_EVENT_CONNECTED);
}

void SpotflowOps_init(void)
{
    if (s_init_done)
    {
        return;
    }

    if (spotflow_client == NULL)
    {
        ESP_LOGE(LOG_TAG, "The Spotflow client is not running");
        return;
    }

    esp_mqtt_client_register_event(spotflow_client, MQTT_EVENT_CONNECTED, spotflow_ops_event, NULL);
    esp_mqtt_client_register_event(spotflow_client, MQTT_EVENT_DISCONNECTED, spotflow_ops_event, NULL);

    s_init_done = true;
}

void SpotflowOps_send_click(void)
{
    if (!s_init_done)
    {
        ESP_LOGE(LOG_TAG, "Spotflow operations not initialized");
        return;
    }

    ESP_LOGI(LOG_TAG, "Sending click event to Spotflow");
}