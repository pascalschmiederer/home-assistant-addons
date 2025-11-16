#!/usr/bin/env bash
set -e

CONFIG_FILE="/data/options.json"

# Defaults
IFACE="auto"
HOST_IP=""
SCAN_INTERVAL=60
ONLINE_TIMEOUT=180
MQTT_HOST="127.0.0.1"
MQTT_PORT=1883
MQTT_USER=""
MQTT_PASS=""
MQTT_BASE_TOPIC="home/arp_scan/devices"
MQTT_DISC_PREFIX="homeassistant"

# Optionen aus /data/options.json lesen
if [ -f "$CONFIG_FILE" ]; then
  IFACE=$(jq -r '.interface // "auto"' "$CONFIG_FILE")
  HOST_IP=$(jq -r '.host_ip // ""' "$CONFIG_FILE")
  SCAN_INTERVAL=$(jq -r '.scan_interval // 60' "$CONFIG_FILE")
  ONLINE_TIMEOUT=$(jq -r '.online_timeout // 180' "$CONFIG_FILE")
  MQTT_HOST=$(jq -r '.mqtt_host // "127.0.0.1"' "$CONFIG_FILE")
  MQTT_PORT=$(jq -r '.mqtt_port // 1883' "$CONFIG_FILE")
  MQTT_USER=$(jq -r '.mqtt_user // ""' "$CONFIG_FILE")
  MQTT_PASS=$(jq -r '.mqtt_password // ""' "$CONFIG_FILE")
  MQTT_BASE_TOPIC=$(jq -r '.mqtt_base_topic // "home/arp_scan/devices"' "$CONFIG_FILE")
  MQTT_DISC_PREFIX=$(jq -r '.mqtt_discovery_prefix // "homeassistant"' "$CONFIG_FILE")
fi

DATA_DIR="/data/devices"
mkdir -p "$DATA_DIR"

log() {
  echo "[arpscan] $*" >&2
}

mqtt_pub() {
  local topic="$1"
  local payload="$2"
  if [ -n "$MQTT_USER" ]; then
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" -t "$topic" -r -m "$payload"
  else
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$topic" -r -m "$payload"
  fi
}

# MAC normalisieren (aa_bb_cc_dd_ee_ff)
normalize_mac() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/:/_/g'
}

resolve_hostname() {
  local ip="$1"
  local host
  host=$(getent hosts "$ip" | awk '{print $2}' | head -n1 || echo "")
  echo "$host"
}

shorten_hostname() {
  local name="$1"

  # leer -> leer zurück
  [ -z "$name" ] && { echo ""; return; }

  # Wenn es wie eine IPv4-Adresse aussieht -> NICHT kürzen
  if [[ "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$name"
  else
    # alles nach dem ersten Punkt abschneiden
    echo "${name%%.*}"
  fi
}

ping_ms() {
  local ip="$1"
  ping -c 1 -W 1 "$ip" 2>/dev/null | awk -F'time=' '/time=/{print $2}' | awk '{print $1}' | head -n1
}

detect_iface_by_host_ip() {
  local ip="$1"
  ip -o addr show | awk -v ip="$ip" '$4 ~ ip"/" {print $2; exit 0}'
}

detect_default_iface() {
  ip route show default 0.0.0.0/0 2>/dev/null | awk '/default/ {print $5; exit 0}'
}

# Automatische Interface-Erkennung
if [ "$IFACE" = "auto" ] || [ -z "$IFACE" ]; then
  log "Interface auf auto – versuche automatische Erkennung..."

  if [ -n "$HOST_IP" ]; then
    auto_iface=$(detect_iface_by_host_ip "$HOST_IP" || true)
    if [ -n "$auto_iface" ]; then
      IFACE="$auto_iface"
      log "Interface über HOST_IP (${HOST_IP}) erkannt: ${IFACE}"
    fi
  fi

  if [ "$IFACE" = "auto" ] || [ -z "$IFACE" ]; then
    auto_iface=$(detect_default_iface || true)
    if [ -n "$auto_iface" ]; then
      IFACE="$auto_iface"
      log "Interface über Default-Route erkannt: ${IFACE}"
    fi
  fi
fi

if [ -z "$IFACE" ] || [ "$IFACE" = "auto" ]; then
  log "Kein Interface ermittelt – bitte in Add-on-Config setzen."
  exit 1
fi

publish_discovery() {
  local mac="$1"
  local mac_norm="$2"
  local hostname="$3"

  local disc_file="${DATA_DIR}/discovery_${mac_norm}.done"
  if [ -f "$disc_file" ]; then
    return
  fi

  local name="$hostname"
  [ -z "$name" ] && name="$mac"

  local state_topic="${MQTT_BASE_TOPIC}/${mac_norm}"

  # Basis-Infos für das Device
  local device_id="arp_scan_${mac_norm}"
  local dev_name="$name"

  # Templates
  local value_tmpl_online='{{ "ON" if value_json.online else "OFF" }}'
  local attr_tmpl='{{ value_json | tojson }}'

  ###########################################################
  # 1) binary_sensor: online
  ###########################################################
  local unique_online="arp_scan_${mac_norm}_online"
  local payload_online
  payload_online=$(jq -n \
    --arg name "Netzgerät ${dev_name}" \
    --arg unique_id "$unique_online" \
    --arg state_topic "$state_topic" \
    --arg device_id "$device_id" \
    --arg dev_name "$dev_name" \
    --arg value_tmpl "$value_tmpl_online" \
    --arg attr_tmpl "$attr_tmpl" \
    '{
       name: $name,
       unique_id: $unique_id,
       state_topic: $state_topic,
       value_template: $value_tmpl,
       payload_on: "ON",
       payload_off: "OFF",
       device_class: "connectivity",
       json_attributes_topic: $state_topic,
       json_attributes_template: $attr_tmpl,
       device: {
         identifiers: [$device_id],
         name: $dev_name,
         model: "ARP Network Device",
         manufacturer: "Custom ARP Scanner"
       }
     }')
  mqtt_pub "${MQTT_DISC_PREFIX}/binary_sensor/${unique_online}/config" "$payload_online"

  ###########################################################
  # 2) sensor: Ping in ms
  ###########################################################
  local unique_ping="arp_scan_${mac_norm}_ping"
  local payload_ping
  payload_ping=$(jq -n \
    --arg name "Ping ${dev_name}" \
    --arg unique_id "$unique_ping" \
    --arg state_topic "$state_topic" \
    --arg device_id "$device_id" \
    --arg dev_name "$dev_name" \
    '{
       name: $name,
       unique_id: $unique_id,
       state_topic: $state_topic,
       value_template: "{{ value_json.ping_ms }}",
       unit_of_measurement: "ms",
       icon: "mdi:speedometer",
       entity_category: "diagnostic",
       device: {
         identifiers: [$device_id],
         name: $dev_name,
         model: "ARP Network Device",
         manufacturer: "Custom ARP Scanner"
       }
     }')
  mqtt_pub "${MQTT_DISC_PREFIX}/sensor/${unique_ping}/config" "$payload_ping"

  ###########################################################
  # 3) sensor: IP-Adresse
  ###########################################################
  local unique_ip="arp_scan_${mac_norm}_ip"
  local payload_ip
  payload_ip=$(jq -n \
    --arg name "IP ${dev_name}" \
    --arg unique_id "$unique_ip" \
    --arg state_topic "$state_topic" \
    --arg device_id "$device_id" \
    --arg dev_name "$dev_name" \
    '{
       name: $name,
       unique_id: $unique_id,
       state_topic: $state_topic,
       value_template: "{{ value_json.ip }}",
       icon: "mdi:ip-network-outline",
       entity_category: "diagnostic",
       device: {
         identifiers: [$device_id],
         name: $dev_name,
         model: "ARP Network Device",
         manufacturer: "Custom ARP Scanner"
       }
     }')
  mqtt_pub "${MQTT_DISC_PREFIX}/sensor/${unique_ip}/config" "$payload_ip"

  ###########################################################
  # 4) sensor: Hostname
  ###########################################################
  local unique_host="arp_scan_${mac_norm}_hostname"
  local payload_host
  payload_host=$(jq -n \
    --arg name "Hostname ${dev_name}" \
    --arg unique_id "$unique_host" \
    --arg state_topic "$state_topic" \
    --arg device_id "$device_id" \
    --arg dev_name "$dev_name" \
    '{
       name: $name,
       unique_id: $unique_id,
       state_topic: $state_topic,
       value_template: "{{ value_json.hostname }}",
       icon: "mdi:server-network",
       entity_category: "diagnostic",
       device: {
         identifiers: [$device_id],
         name: $dev_name,
         model: "ARP Network Device",
         manufacturer: "Custom ARP Scanner"
       }
     }')
  mqtt_pub "${MQTT_DISC_PREFIX}/sensor/${unique_host}/config" "$payload_host"

  ###########################################################
  # 5) sensor: MAC-Adresse
  ###########################################################
  local unique_mac="arp_scan_${mac_norm}_mac"
  local payload_mac
  payload_mac=$(jq -n \
    --arg name "MAC ${dev_name}" \
    --arg unique_id "$unique_mac" \
    --arg state_topic "$state_topic" \
    --arg device_id "$device_id" \
    --arg dev_name "$dev_name" \
    '{
       name: $name,
       unique_id: $unique_id,
       state_topic: $state_topic,
       value_template: "{{ value_json.mac }}",
       icon: "mdi:ethernet",
       entity_category: "diagnostic",
       device: {
         identifiers: [$device_id],
         name: $dev_name,
         model: "ARP Network Device",
         manufacturer: "Custom ARP Scanner"
       }
     }')
  mqtt_pub "${MQTT_DISC_PREFIX}/sensor/${unique_mac}/config" "$payload_mac"

  ###########################################################
  # 6) sensor: first_seen (Zeitstempel)
  ###########################################################
  local unique_first="arp_scan_${mac_norm}_first_seen"
  local payload_first
  payload_first=$(jq -n \
    --arg name "First seen ${dev_name}" \
    --arg unique_id "$unique_first" \
    --arg state_topic "$state_topic" \
    --arg device_id "$device_id" \
    --arg dev_name "$dev_name" \
    '{
       name: $name,
       unique_id: $unique_id,
       state_topic: $state_topic,
       value_template: "{{ value_json.first_seen }}",
       device_class: "timestamp",
       entity_category: "diagnostic",
       device: {
         identifiers: [$device_id],
         name: $dev_name,
         model: "ARP Network Device",
         manufacturer: "Custom ARP Scanner"
       }
     }')
  mqtt_pub "${MQTT_DISC_PREFIX}/sensor/${unique_first}/config" "$payload_first"

  ###########################################################
  # 7) sensor: last_seen (Zeitstempel)
  ###########################################################
  local unique_last="arp_scan_${mac_norm}_last_seen"
  local payload_last
  payload_last=$(jq -n \
    --arg name "Last seen ${dev_name}" \
    --arg unique_id "$unique_last" \
    --arg state_topic "$state_topic" \
    --arg device_id "$device_id" \
    --arg dev_name "$dev_name" \
    '{
       name: $name,
       unique_id: $unique_id,
       state_topic: $state_topic,
       value_template: "{{ value_json.last_seen }}",
       device_class: "timestamp",
       entity_category: "diagnostic",
       device: {
         identifiers: [$device_id],
         name: $dev_name,
         model: "ARP Network Device",
         manufacturer: "Custom ARP Scanner"
       }
     }')
  mqtt_pub "${MQTT_DISC_PREFIX}/sensor/${unique_last}/config" "$payload_last"

  # Discovery nur einmal pro Gerät
  touch "$disc_file"
}

update_device_state() {
  local ip="$1"
  local mac="$2"
  local now_iso="$3"

  local hostname_raw hostname

  hostname_raw=$(resolve_hostname "$ip")

  if [ -n "$hostname_raw" ]; then
    hostname=$(shorten_hostname "$hostname_raw")
  else
    # kein Hostname -> IP als "Hostname" benutzen, aber NICHT kürzen
    hostname=$(shorten_hostname "$ip")
  fi

  local mac_norm
  mac_norm=$(normalize_mac "$mac")

  local dev_file="${DATA_DIR}/${mac_norm}.json"

  local first_seen="$now_iso"
  if [ -f "$dev_file" ]; then
    local old_first
    old_first=$(jq -r '.first_seen // empty' "$dev_file")
    if [ -n "$old_first" ]; then
      first_seen="$old_first"
    fi
  fi

  local rtt
  rtt=$(ping_ms "$ip")
  [ -z "$rtt" ] && rtt=null

  local json
  json=$(jq -n \
    --arg ip "$ip" \
    --arg mac "$mac" \
    --arg hostname "$hostname" \
    --arg first_seen "$first_seen" \
    --arg last_seen "$now_iso" \
    --argjson ping_ms "$rtt" \
    '{
      ip: $ip,
      mac: $mac,
      hostname: $hostname,
      first_seen: $first_seen,
      last_seen: $last_seen,
      online: true,
      ping_ms: $ping_ms
    }')

  echo "$json" > "$dev_file"

  mqtt_pub "${MQTT_BASE_TOPIC}/${mac_norm}" "$json"
  publish_discovery "$mac" "$mac_norm" "$hostname"
}

mark_offline_devices() {
  local now_epoch
  now_epoch=$(date +%s)

  for dev_file in "$DATA_DIR"/*.json; do
    [ -e "$dev_file" ] || continue

    local mac
    mac=$(jq -r '.mac // empty' "$dev_file")

    local last_seen
    last_seen=$(jq -r '.last_seen // empty' "$dev_file")
    [ -z "$mac" ] || [ -z "$last_seen" ] && continue

    local last_epoch
    last_epoch=$(date -d "$last_seen" +%s 2>/dev/null || echo "$now_epoch")

    local diff=$((now_epoch - last_epoch))
    if [ "$diff" -gt "$ONLINE_TIMEOUT" ]; then
      local ip
      ip=$(jq -r '.ip // empty' "$dev_file")
      local hostname
      hostname=$(jq -r '.hostname // empty' "$dev_file")
      local first_seen
      first_seen=$(jq -r '.first_seen // empty' "$dev_file")
      local ping_ms
      ping_ms=$(jq -r '.ping_ms // null' "$dev_file")

      local mac_norm
      mac_norm=$(normalize_mac "$mac")

      local json
      json=$(jq -n \
        --arg ip "$ip" \
        --arg mac "$mac" \
        --arg hostname "$hostname" \
        --arg first_seen "$first_seen" \
        --arg last_seen "$last_seen" \
        --argjson ping_ms "$ping_ms" \
        '{
          ip: $ip,
          mac: $mac,
          hostname: $hostname,
          first_seen: $first_seen,
          last_seen: $last_seen,
          online: false,
          ping_ms: $ping_ms
        }')

      echo "$json" > "$dev_file"
      mqtt_pub "${MQTT_BASE_TOPIC}/${mac_norm}" "$json"
      log "OFFLINE: $mac"
    fi
  done
}

log "Interface: $IFACE, MQTT: $MQTT_HOST:$MQTT_PORT"

while true; do
  now_iso=$(date --iso-8601=seconds)
  log "Starte ARP-Scan…"

  SCAN=$(/usr/bin/arp-scan --localnet --interface="$IFACE" 2>/dev/null || true)

  echo "$SCAN" | while read -r line; do
    ip=$(echo "$line" | awk '{print $1}')
    mac=$(echo "$line" | awk '{print $2}')
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "$mac" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
      update_device_state "$ip" "$mac" "$now_iso"
    fi
  done

  mark_offline_devices

  log "Warte ${SCAN_INTERVAL}s…"
  sleep "$SCAN_INTERVAL"
done
