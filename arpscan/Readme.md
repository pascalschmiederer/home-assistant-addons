📡 ARP-Scan MQTT Network Discovery
Home Assistant Add-on – automatische Netzwerkgeräte-Erkennung über ARP & MQTT

Dieses Add-on scannt dein lokales Netzwerk in regelmäßigen Abständen mit arp-scan und veröffentlicht alle gefundenen Geräte als MQTT-Entities per Home-Assistant-Discovery.
Für jedes Gerät erzeugt das Add-on ein vollständiges „Netzwerkgerät“ mit folgenden Eigenschaften:

IP-Adresse

MAC-Adresse

Hostname (automatische Reverse-DNS Abfrage, inkl. Domain-Trim)

First seen

Last seen

Ping (ms)

Online / Offline Status

Automatisch generiertes Home Assistant Gerät (via MQTT Discovery)

Persistente Speicherung in /data/devices/*.json (damit first_seen dauerhaft bleibt)

Das Add-on funktioniert vollständig autonom und benötigt keine zusätzliche Integration in Home Assistant außer MQTT.

🚀 Features

🔍 ARP-basierter Netzwerkscan (findet wirklich alle Geräte – auch solche, die nicht pingbar sind)

🔁 Automatischer Intervall-Scan (z. B. alle 60 Sekunden)

📡 MQTT Discovery für Home Assistant

🏷️ Automatische Geräte-Erstellung pro MAC-Adresse

🖧 Hostname-Erkennung per Reverse DNS

🎯 Intelligente Namensverkürzung:

home-server.home.internal → home-server

10.10.1.223 bleibt 10.10.1.223

💓 Online-Status pro Gerät

🕒 First Seen bleibt erhalten – selbst nach Neustarts

📁 Lokale Device-Datenbank: /data/devices/<mac>.json

🔌 Host-Networking + NET_RAW für zuverlässige ARP-Erkennung

🐳 Leichtgewichtiges Docker-Image auf Alpine Linux

📦 Installation

Repository zum Home Assistant hinzufügen:

https://github.com/pascalschmiederer/ha-addons


Im Add-on Store → „ARP-Scan MQTT Network Discovery“ installieren

Auf der Config Seite die Daten anpassen

MQTT in Home Assistant muss aktiviert sein

Add-on starten → fertig 🎉

⚙️ Konfiguration

Die Einstellungen werden über die Add-on-Optionsoberfläche gesetzt.

Beispiel-Konfiguration
{
  "interface": "auto",
  "host_ip": "",
  "scan_interval": 60,
  "online_timeout": 180,
  "mqtt_host": "10.10.1.248",
  "mqtt_port": 1883,
  "mqtt_user": "mqtt",
  "mqtt_password": "mqtt",
  "mqtt_base_topic": "arpscan/state",
  "mqtt_discovery_prefix": "homeassistant"
}

Parameter-Beschreibung
Parameter	Beschreibung
interface	Netzwerkschnittstelle, z. B. eth0 – oder auto für Autodetektion
host_ip	(Optional) IP des Hosts, um das Interface exakt zu bestimmen
scan_interval	Zeit zwischen ARP-Scans in Sekunden
online_timeout	Zeit bis ein Gerät offline gesetzt wird
mqtt_host	MQTT-Broker Host
mqtt_port	Port des Brokers
mqtt_user / mqtt_password	MQTT-Zugangsdaten
mqtt_base_topic	Basistopic für Statusupdates
mqtt_discovery_prefix	Discovery-Prefix (normalerweise homeassistant)
🏠 Home Assistant Integration (automatisch)

Für jedes Gerät erzeugt das Add-on:

Ein Home-Assistant Gerät

Name: Kurzhostname oder IP
Modell: ARP Network Device
Hersteller: Custom ARP Scanner

Binary Sensor: Online / Offline

Per MQTT-Discovery:

homeassistant/binary_sensor/arp_scan_<mac_norm>/config

Diagnose-Sensoren (entity registry)

First seen

Last seen

Hostname

IP

MAC

Ping (ms)

Alle werden als Attribute automatisch an das Gerät gehängt.

📂 Dateistruktur im Add-on
addon/
├── Dockerfile
├── config.json
├── run.sh
└── rootfs/
    └── etc/
        └── services.d/
            └── arpscan/
                └── run


Persistente Gerätedaten:

/data/devices/<mac_norm>.json


Beispiel:

{
  "ip": "10.10.1.10",
  "mac": "56:f8:c7:cb:af:fd",
  "hostname": "home-server",
  "first_seen": "2025-11-16T10:51:49+00:00",
  "last_seen": "2025-11-16T11:14:45+00:00",
  "online": true,
  "ping_ms": 0.209
}

🔧 MQTT Themenstruktur
Statusupdates eines Geräts:
arpscan/state/<mac_norm>


Beispiel:

arpscan/state/56_f8_c7_cb_af_fd

Discovery Topics:
homeassistant/binary_sensor/arp_scan_<mac_norm>/config


Payload enthält:

State Topic

Attribute Topic

Geräte-Metadaten

Einzigartige IDs

Device Infos

🔨 Entwicklung / Reset
Discovery neu erzeugen

Bestehende MQTT-Discovery löschen:

mosquitto_pub -h <broker> -u <user> -P <pass> \
  -t "homeassistant/binary_sensor/+/config" -n -r


Discovery im Add-on zurücksetzen:

docker exec -it addon_local_arpscan sh -c 'rm -f /data/devices/discovery_*.done'


Add-on neu starten:

ha addons restart local_arpscan

🛠️ Build

Dockerfile basiert auf:

BUILD_FROM (Home Assistant Base Image)

Alpine Linux

arp-scan

jq

mosquitto-clients

📜 Lizenz

MIT License – frei zur Nutzung, Anpassung und Weitergabe.
