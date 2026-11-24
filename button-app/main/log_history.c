
#include "log_history.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "sdkconfig.h"
#include "freertos/FreeRTOS.h"
#include "freertos/ringbuf.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_partition.h"
#include "esp_littlefs.h"

static const char *LOG_TAG = "log-hist";

#define MAX_LEN 160
#define MAX_ITEMS 32

static RingbufHandle_t s_history = NULL;
static vprintf_like_t s_forward = NULL;

#define LOG_PARTITION "logs"
#define LOG_MOUNT "/logs"
#define LOG_FILE LOG_MOUNT "/history.log"

static int history_vprintf(const char *format, va_list args);
static void history_store(const char *line, size_t len);
static void history_append(const char *text, size_t len);
static void history_save(void);

esp_err_t LogHistory_init(void)
{
    if (s_history != NULL)
    {
        return ESP_OK;
    }

    s_history = xRingbufferCreateNoSplit(MAX_LEN, MAX_ITEMS);

    if (s_history == NULL)
    {
        ESP_LOGE(LOG_TAG, "No memory for log history");
        return ESP_ERR_NO_MEM;
    }

    s_forward = esp_log_set_vprintf(history_vprintf);

    return ESP_OK;
}

esp_err_t LogHistory_flash_init(void)
{
    const esp_vfs_littlefs_conf_t conf = {
        .base_path = LOG_MOUNT,
        .partition_label = LOG_PARTITION,
        .format_if_mount_failed = true,
    };

    esp_err_t err = esp_vfs_littlefs_register(&conf);
    if (err != ESP_OK)
    {
        ESP_LOGE(LOG_TAG, "Mounting %s failed: %s", LOG_PARTITION, esp_err_to_name(err));
        return err;
    }

    return esp_register_shutdown_handler(history_save);
}

void LogHistory_disable(void)
{
    if (s_history != NULL)
    {
        esp_log_set_vprintf(s_forward);
        vRingbufferDelete(s_history);
        s_history = NULL;
    }
}

static int history_vprintf(const char *format, va_list args)
{
    char line[MAX_LEN] = {0};
    va_list forward_args;

    va_copy(forward_args, args);

    int written = vsnprintf(line, sizeof(line), format, args);
    size_t len = (written > 0) ? strnlen(line, sizeof(line)) : 0;
    if (len > 0)
    {
        history_append(line, len);
    }

    int forwarded = s_forward ? s_forward(format, forward_args) : 0;
    va_end(forward_args);

    return forwarded;
}

void LogHistory_dump(void)
{
    if (s_history == NULL)
    {
        ESP_LOGE(LOG_TAG, "History not initialized");
        return;
    }

    size_t waiting = 0;
    void *item = NULL;
    size_t item_size = 0;

    printf("\n=== log history ===\n");

    vRingbufferGetInfo(s_history, NULL, NULL, NULL, NULL, &waiting);
    while (waiting > 0)
    {
        item = xRingbufferReceive(s_history, &item_size, 0);
        if (item != NULL)
        {
            printf("%.*s\n", (int)item_size, (const char *)item);
            vRingbufferReturnItem(s_history, item);
        }
        vRingbufferGetInfo(s_history, NULL, NULL, NULL, NULL, &waiting);
    }

    printf("=== end of log history ===\n\n");
    fflush(stdout);
}

void LogHistory_flash_print(void)
{
    FILE *file = fopen(LOG_FILE, "r");

    printf("\n=== stored log ===\n");
    if (file == NULL)
    {
        printf("No stored log\n");
    }
    else
    {
        char line[MAX_LEN];

        while (fgets(line, sizeof(line), file) != NULL)
        {
            printf("%s", line);
        }
        fclose(file);
    }
    printf("=== end of stored log ===\n\n");
}

static void history_store(const char *line, size_t len)
{
    if (xRingbufferSend(s_history, line, len, 0) == pdTRUE)
    {
        return;
    }

    void *oldest = NULL;
    size_t oldest_size = 0;

    oldest = xRingbufferReceive(s_history, &oldest_size, 0);
    if (oldest != NULL)
    {
        vRingbufferReturnItem(s_history, oldest);
    }

    xRingbufferSend(s_history, line, len, 0);
}

static void history_append(const char *text, size_t len)
{
    static char s_pending[MAX_LEN];
    static size_t s_pending_len;
    size_t start = 0;

    for (size_t i = 0; i < len; i++)
    {
        if (text[i] == '\n' || text[i] == '\r')
        {
            size_t part_len = i - start;
            size_t available = sizeof(s_pending) - s_pending_len - 1;
            part_len = part_len < available ? part_len : available;
            memcpy(s_pending + s_pending_len, text + start, part_len);
            s_pending_len += part_len;

            if (s_pending_len > 0)
            {
                history_store(s_pending, s_pending_len);
            }
            s_pending_len = 0;
            start = i + 1;

            if (text[i] == '\r' && i + 1 < len && text[i + 1] == '\n')
            {
                i++;
                start++;
            }
        }
    }

    size_t part_len = len - start;
    size_t available = sizeof(s_pending) - s_pending_len - 1;
    part_len = part_len < available ? part_len : available;
    memcpy(s_pending + s_pending_len, text + start, part_len);
    s_pending_len += part_len;
}

static void history_save(void)
{
    FILE *file = fopen(LOG_FILE, "w");

    size_t waiting = 0;
    void *item = NULL;
    size_t item_size = 0;

    vRingbufferGetInfo(s_history, NULL, NULL, NULL, NULL, &waiting);
    while (waiting > 0)
    {
        item = xRingbufferReceive(s_history, &item_size, 0);
        if (item != NULL)
        {
            fwrite(item, 1, item_size, file);
            fputc('\n', file);

            vRingbufferReturnItem(s_history, item);
        }
        vRingbufferGetInfo(s_history, NULL, NULL, NULL, NULL, &waiting);
    }

    fflush(file);
    fsync(fileno(file));
    fclose(file);
}