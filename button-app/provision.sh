#!/usr/bin/env bash
#
# Writes the unit's credential into the flash, the way a provisioning station does.
#
#   ./provision.sh /secure/credentials.csv [/dev/ttyUSB0]

set -euo pipefail

CSV=${1:?usage: provision.sh <credentials.csv> [port]}
PORT=${2:-/dev/ttyUSB0}
test -f "$CSV" || { echo "no credential file at $CSV"; exit 1; }
test -c "$PORT" || { echo "no device at $PORT"; exit 1; }

source /opt/esp/idf/export.sh
NVS_GEN="$IDF_PATH/components/nvs_flash/nvs_partition_generator/nvs_partition_gen.py"
PART_TOOL="$IDF_PATH/components/partition_table/parttool.py"
ESP_TOOL="esptool"

BUILD=${IDF_BUILD_DIR:-build}
TMP="./tmp"
mkdir -p $TMP
KEYSFILE="nvs_keys.bin"
# generate-key always writes into a keys/ directory under its output directory.
KEYS="$TMP/keys/$KEYSFILE"

PART_TABLE="$BUILD/partition_table/partition-table.bin"
test -f "$PART_TABLE" || { echo "run idf.py build first"; exit 1; }

# The size comes from the partition table, so the image cannot drift from it.
SIZE=$("$PART_TOOL" --partition-table-file "$PART_TABLE" \
    get_partition_info --partition-name nvs --info size)

# Generate the keys if they don't exist yet. The keys are stored 
# in a separate partition, so they can be updated without re-flashing the NVS image.
if [ ! -f "$KEYS" ]; then
    "$NVS_GEN" generate-key --keyfile "$KEYSFILE" --outdir "$TMP"
fi

# The key partition first, then the NVS image encrypted with the keys it holds.
"$NVS_GEN" encrypt "$CSV" nvs.bin "$SIZE" \
    --inputkey "$KEYS" --outdir "$BUILD"

# The table comes from the build, so the device does not have to hold one yet.
"$PART_TOOL" -p "$PORT" --partition-table-file "$PART_TABLE" \
    write_partition --partition-name nvs_keys --input "$KEYS"
"$PART_TOOL" -p "$PORT" --partition-table-file "$PART_TABLE" \
    write_partition --partition-name nvs --input "$BUILD/nvs.bin"
 
 # Flash the device with the partition table and the application. 
 # No reset after flashing.
 cd $BUILD
 "$ESP_TOOL" --chip esp32 -p "$PORT" -b 460800 --before default-reset --after no-reset write-flash "@flash_args"