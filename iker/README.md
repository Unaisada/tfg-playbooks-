# Documentación — Iker
## Rol: Sistemas / Monitorización (NOC)
### TFG SecureOps ASIR2 2025

---

## Índice

1. [Servicios Configurados](#1-servicios-configurados)
   - 1.1 DNS con BIND9
   - 1.2 Active Directory (Windows Server 2022)
   - 1.3 DHCP
2. [Stack de Monitorización (NOC)](#2-stack-de-monitorización-noc)
   - 2.1 Arquitectura y flujo de datos
   - 2.2 Prometheus
   - 2.3 Grafana
   - 2.4 Loki + Promtail
   - 2.5 Node Exporter
   - 2.6 Uptime Kuma
3. [Dashboards de Grafana](#3-dashboards-de-grafana)
4. [Alertas](#4-alertas)
5. [Manual de Usuario del NOC](#5-manual-de-usuario-del-noc)

---

## 1. Servicios Configurados

### 1.1 DNS con BIND9

**¿Qué es?**  
BIND9 es el servidor DNS (Domain Name System) más utilizado en entornos Linux. Su función es resolver nombres de dominio a direcciones IP dentro de la red del proyecto.

**Servidor:** `srv-linux` — IP: `10.0.100.10`

**Dominio configurado:** `secureops.local`

**Zonas configuradas:**

| Tipo | Archivo | Descripción |
|------|---------|-------------|
| Zona directa | `db.secureops.local` | Resuelve nombres → IPs |
| Zona inversa | `db.secureops.local.inversa` | Resuelve IPs → nombres |

**Registros DNS configurados:**

| Nombre | Tipo | IP |
|--------|------|----|
| srv-linux | A | 10.0.100.10 |
| srv-wazuh | A | 10.0.100.20 |
| srv-monitoring | A | 10.0.100.30 |
| srv-suricata | A | 10.0.100.40 |
| srv-windows | A | 10.0.100.50 |
| fw-pfsense | A | 10.0.100.1 |
| grafana | CNAME | srv-monitoring.secureops.local |
| wazuh | CNAME | srv-wazuh.secureops.local |
| web | CNAME | srv-linux.secureops.local |
| proxy | CNAME | srv-linux.secureops.local |

**Verificación:**
```bash
nslookup srv-linux.secureops.local 127.0.0.1
nslookup grafana.secureops.local 127.0.0.1
nslookup 10.0.100.30 127.0.0.1
```

**Archivos de configuración:** `configs/dns/`

---

### 1.2 Active Directory (Windows Server 2022)

**¿Qué es?**  
Active Directory (AD) es el servicio de directorio de Microsoft. Centraliza la autenticación y gestión de usuarios, equipos y políticas de seguridad en una red Windows.

**Servidor:** `srv-windows` — IP: `10.0.100.50`  
**Dominio:** `secureops.local`  
**Nivel funcional:** Windows Server 2016

#### Estructura de Unidades Organizativas (OUs)

```
secureops.local/
├── Departamentos/
│   ├── IT/
│   │   ├── admin.it
│   │   └── tecnico1
│   ├── Administracion/
│   │   ├── admin.adm
│   │   └── contable1
│   └── Direccion/
│       ├── director
│       └── subdirector
├── Servidores/
└── Grupos/
```

#### GPOs de Seguridad Configuradas

| GPO | Configuración |
|-----|--------------|
| Política de contraseñas | Mínimo 8 caracteres, complejidad activada, vigencia 90 días |
| Bloqueo de cuenta | Bloqueo tras 5 intentos fallidos, duración 15 minutos |
| Auditoría de acceso | Auditar inicios de sesión exitosos y fallidos |
| Restricciones de software | Bloquear ejecución de .exe desde carpetas temporales (%TEMP%, %TMP%) |

---

### 1.3 DHCP

**¿Qué es?**  
El servidor DHCP (Dynamic Host Configuration Protocol) asigna automáticamente configuración de red a los dispositivos que se conectan a la red.

**Servidor:** `srv-windows` (Windows Server 2022)

**Configuración del ámbito:**

| Parámetro | Valor |
|-----------|-------|
| Nombre | Red-TFG |
| Rango de IPs | 10.0.100.100 — 10.0.100.200 |
| Máscara | 255.255.255.0 |
| Puerta de enlace | 10.0.100.1 |
| DNS | 10.0.100.10 |
| Dominio | secureops.local |
| Duración del alquiler | 8 horas |

> Las IPs estáticas de los servidores (10.0.100.1 — 10.0.100.99) quedan fuera del rango DHCP, evitando conflictos.

---

## 2. Stack de Monitorización (NOC)

### 2.1 Arquitectura y flujo de datos

```
┌─────────────────────────────────────────────────────────────┐
│                    srv-monitoring (10.0.100.30)             │
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐ │
│  │  Prometheus │←───│Node Exporter│    │  Loki           │ │
│  │  :9090      │    │  :9100      │    │  :3100          │ │
│  └──────┬──────┘    └─────────────┘    └────────┬────────┘ │
│         │                                        │          │
│         └──────────────┬─────────────────────────┘          │
│                        ↓                                    │
│                  ┌─────────────┐                            │
│                  │   Grafana   │                            │
│                  │   :3000     │                            │
│                  └─────────────┘                            │
│                                                             │
│  ┌──────────────┐    ┌─────────────────────────────────┐   │
│  │  Promtail    │───→│  Loki (recoge logs del sistema) │   │
│  └──────────────┘    └─────────────────────────────────┘   │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Uptime Kuma :3001 (monitoriza estado de servicios)  │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

         ↑ Node Exporter instalado también en:
         - srv-linux (10.0.100.10)
```

**Flujo de datos:**
1. **Node Exporter** recoge métricas del sistema (CPU, RAM, disco, red)
2. **Prometheus** hace scraping de Node Exporter cada 15 segundos
3. **Grafana** consulta Prometheus y visualiza los datos en dashboards
4. **Promtail** recoge logs del sistema y los envía a **Loki**
5. **Grafana** también consulta Loki para mostrar logs en tiempo real
6. **Uptime Kuma** monitoriza independientemente si los servicios están UP o DOWN

---

### 2.2 Prometheus

**¿Qué es?**  
Prometheus es un sistema de monitorización y alertas open source. Recoge métricas de los servidores a intervalos regulares y las almacena en una base de datos de series temporales.

**Puerto:** `9090`  
**Intervalo de scraping:** 15 segundos  
**Retención de datos:** 30 días

**Targets configurados:**

| Job | Target | Descripción |
|-----|--------|-------------|
| prometheus | localhost:9090 | Automonitorización |
| node-exporter-local | node-exporter:9100 | Métricas de srv-monitoring |
| node-exporters | 10.0.100.10:9100 | Métricas de srv-linux |
| node-exporters | 10.0.100.20:9100 | Métricas de srv-wazuh |
| node-exporters | 10.0.100.40:9100 | Métricas de srv-suricata |
| nginx | 10.0.100.10:9113 | Métricas de Nginx |

**Archivo de configuración:** `configs/grafana/prometheus/prometheus.yml`

---

### 2.3 Grafana

**¿Qué es?**  
Grafana es la plataforma de visualización de datos. Permite crear dashboards interactivos con gráficas, gauges y paneles de logs a partir de los datos de Prometheus y Loki.

**Puerto:** `3000`  
**Usuario:** `admin`  
**Datasources configurados:** Prometheus + Loki

**Acceso:** `http://10.0.100.30:3000`

---

### 2.4 Loki + Promtail

**¿Qué es Loki?**  
Loki es un sistema de agregación de logs desarrollado por Grafana Labs. Almacena los logs del sistema de forma eficiente y permite consultarlos desde Grafana.

**¿Qué es Promtail?**  
Promtail es el agente que recoge los logs del sistema y los envía a Loki.

**Puerto Loki:** `3100`

**Logs recogidos:**
- `/var/log/*.log` — todos los logs del sistema
- `/var/log/syslog` — log del sistema principal

---

### 2.5 Node Exporter

**¿Qué es?**  
Node Exporter es un agente de Prometheus que expone métricas del sistema operativo (CPU, RAM, disco, red, etc.) para que Prometheus pueda recogerlas.

**Puerto:** `9100`

**Instalado en:**
- `srv-monitoring` (10.0.100.30) — dentro de Docker
- `srv-linux` (10.0.100.10) — como servicio systemd

**Verificación:**
```bash
curl http://localhost:9100/metrics | head -20
```

---

### 2.6 Uptime Kuma

**¿Qué es?**  
Uptime Kuma es una herramienta de monitorización del estado de servicios. Muestra en tiempo real si cada servicio está UP (verde) o DOWN (rojo).

**Puerto:** `3001`  
**Acceso:** `http://10.0.100.30:3001`

**Servicios monitorizados:**

| Nombre | Tipo | Host/URL | Puerto | Intervalo |
|--------|------|----------|--------|-----------|
| pfSense | Ping | 10.0.100.1 | — | 60s |
| DNS Server | DNS | 10.0.100.10 | 53 | 60s |
| Web Server | HTTP | http://10.0.100.10 | 80 | 60s |
| Squid Proxy | TCP | 10.0.100.10 | 3128 | 60s |
| Wazuh Dashboard | HTTP | https://10.0.100.20 | 443 | 60s |
| Grafana | HTTP | http://10.0.100.30:3000 | 3000 | 60s |
| Prometheus | HTTP | http://10.0.100.30:9090 | 9090 | 60s |
| Suricata | Ping | 10.0.100.40 | — | 60s |
| Windows Server | Ping | 10.0.100.50 | — | 60s |

---

## 3. Dashboards de Grafana

### Dashboard 1: NOC Overview

Dashboard principal de monitorización en tiempo real de toda la infraestructura.

#### Panel 1 — CPU Usage %
- **Visualización:** Time series
- **Query:** `100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)`
- **Descripción:** Muestra el porcentaje de uso de CPU de cada servidor en tiempo real.

#### Panel 2 — RAM Usage %
- **Visualización:** Gauge
- **Query:** `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100`
- **Thresholds:** Verde (0-60%), Amarillo (60-80%), Rojo (80-100%)
- **Descripción:** Muestra el porcentaje de memoria RAM utilizada.

#### Panel 3 — Disk Usage %
- **Visualización:** Bar gauge
- **Query:** `(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100`
- **Descripción:** Muestra el porcentaje de disco utilizado en cada servidor.

#### Panel 4 — Network Traffic
- **Visualización:** Time series
- **Query:** `rate(node_network_receive_bytes_total{device!="lo"}[5m]) * 8`
- **Descripción:** Muestra el tráfico de red entrante en bits/segundo.

#### Panel 5 — Service Status
- **Visualización:** Stat (semáforo)
- **Query:** `up`
- **Value mappings:** `1` → UP (verde), `0` → DOWN (rojo)
- **Descripción:** Muestra el estado de cada servicio monitorizado por Prometheus.

#### Panel 6 — System Logs (Live)
- **Visualización:** Logs
- **Datasource:** Loki
- **Query:** `{job="syslog"}`
- **Descripción:** Muestra los logs del sistema en tiempo real.

---

## 4. Alertas

### Alertas en Grafana (Discord)

Configuradas para notificar al canal de Discord del equipo cuando un servicio cae.

**Condición:** `up == 0` durante más de 1 minuto  
**Canal:** Discord via webhook  
**Mensaje:** Incluye nombre del servicio, estado y timestamp

---

## 5. Manual de Usuario del NOC

### Acceso a los servicios

| Servicio | URL | Usuario | Contraseña |
|----------|-----|---------|------------|
| Grafana | http://10.0.100.30:3000 | admin | SecureOps2025! |
| Prometheus | http://10.0.100.30:9090 | — | — |
| Uptime Kuma | http://10.0.100.30:3001 | admin | SecureOps2025! |

### Cómo interpretar los dashboards

**CPU Usage:** Si una barra supera el 80% de forma sostenida, puede indicar un proceso problemático o ataque.

**RAM Usage:** El gauge en rojo (>80%) indica que el servidor puede quedarse sin memoria. Hay que revisar los procesos activos.

**Disk Usage:** Si el disco supera el 80%, hay que limpiar logs o ampliar almacenamiento.

**Network Traffic:** Picos anómalos de tráfico pueden indicar un ataque DDoS o transferencia de datos no autorizada.

**Service Status:** Cualquier servicio en rojo (DOWN) requiere atención inmediata. Se recibirá notificación en Discord.

**System Logs:** Buscar errores críticos, intentos de login fallidos o actividad sospechosa.

### Modo Kiosk (para la demo)

Para mostrar el dashboard en pantalla completa durante la presentación, añadir `?kiosk` a la URL:

```
http://10.0.100.30:3000/d/[dashboard-id]?kiosk
```

### Auto-refresh

El dashboard está configurado con auto-refresh de **10 segundos** para mostrar datos en tiempo real durante la presentación.

---

## Archivos de configuración

```
configs/
└── dns/
    ├── named.conf.options
    ├── named.conf.local
    ├── db.secureops.local
    └── db.secureops.local.inversa
configs/
└── grafana/
    ├── docker-compose.yml
    ├── prometheus/
    │   └── prometheus.yml
    ├── grafana/
    │   └── provisioning/
    │       └── datasources/
    │           └── datasources.yml
    ├── loki/
    │   └── loki-config.yml
    └── promtail/
        └── promtail-config.yml
```

---

*Documentación generada por Iker — TFG SecureOps ASIR2 2025*

