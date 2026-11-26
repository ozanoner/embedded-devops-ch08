#!/usr/bin/env bash

set -euo pipefail

PORT=${1:-/dev/ttyUSB0}
test -c "$PORT" || { echo "no device at $PORT"; exit 1; }

source /opt/esp/idf/export.sh
NVS_GEN="$IDF_PATH/components/nvs_flash/nvs_partition_generator/nvs_partition_gen.py"
PART_TOOL="$IDF_PATH/components/partition_table/parttool.py"
NVS_TOOL="$IDF_PATH/components/nvs_flash/nvs_partition_tool/nvs_tool.py"

# 1. Read encrypted NVS and NVS keys from the ESP32 into ./tmp/
python "$PART_TOOL" --port /dev/ttyUSB0 --partition-table-offset 0xa000 read_partition --partition-name nvs --output ./tmp/nvs_enc.bin

# 2. Decrypt NVS
python "$NVS_GEN" decrypt ./tmp/nvs_enc.bin ./tmp/keys/nvs_keys.bin ./tmp/nvs_dec.bin 

# 3. Print formatted entries
python "$NVS_TOOL" -d minimal ./tmp/nvs_dec.bin
