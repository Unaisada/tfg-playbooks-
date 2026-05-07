#!/var/ossec/framework/python/bin/python3
import sys
import json
import requests

alert_file = open(sys.argv[1])
alert = json.load(alert_file)
alert_file.close()

WEBHOOK_URL = "https://discord.com/api/webhooks/1494284308872040478/U7DTLmbyqnRqZlWopddkJz_s8qsA57pk53DPF56JEXVd7ZNGCtdUZwd2tQJQluCkbpra"

alert_level = alert.get('rule', {}).get('level', 0)
description = alert.get('rule', {}).get('description', 'Sin descripcion')
agent_name = alert.get('agent', {}).get('name', 'Desconocido')
timestamp = alert.get('timestamp', '')

if alert_level >= 12:
    emoji = "ALERTA CRITICA"
    color = 16711680
elif alert_level >= 8:
    emoji = "ALERTA ALTA"
    color = 16776960
else:
    emoji = "Alerta"
    color = 65280

payload = {
    "embeds": [{
        "title": f"{emoji} - Nivel {alert_level}",
        "description": description,
        "color": color,
        "fields": [
            {"name": "Agente", "value": agent_name, "inline": True},
            {"name": "Nivel", "value": str(alert_level), "inline": True},
            {"name": "Hora", "value": timestamp, "inline": True}
        ],
        "footer": {"text": "SecureOps SOC - TFG ASIR2 2025"}
    }]
}

requests.post(WEBHOOK_URL, json=payload)
sys.exit(0)
