
#include "crash_info.h"
#include <stdint.h>
#include "esp_attr.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_core_dump.h"

static const char *LOG_TAG = "crash";

#define BOOT_MAGIC 0xB007

RTC_NOINIT_ATTR static uint32_t s_boot_magic;
RTC_NOINIT_ATTR static uint32_t s_boot_count;
RTC_NOINIT_ATTR static uint32_t s_panic_count;

void CrashInfo_report(void)
{
    if (s_boot_magic != BOOT_MAGIC)
    {
        s_boot_magic = BOOT_MAGIC;
        s_boot_count = 0;
        s_panic_count = 0;
    }

    s_boot_count++;

    esp_reset_reason_t reason = esp_reset_reason();
    if (reason == ESP_RST_PANIC)
    {
        s_panic_count++;
        ESP_LOGW(LOG_TAG, "Reset reason: ESP_RST_PANIC");
    }

    ESP_LOGI(LOG_TAG, "Boot %u, reset reason %d, panics %u",
             (unsigned)s_boot_count, (int)reason, (unsigned)s_panic_count);

    size_t addr = 0;
    size_t size = 0;

    if (esp_core_dump_image_get(&addr, &size) == ESP_OK)
    {
        ESP_LOGW(LOG_TAG, "Core dump at 0x%x, %u bytes", (unsigned)addr, (unsigned)size);
    }
}
