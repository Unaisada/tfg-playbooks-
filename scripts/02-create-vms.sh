#!/bin/bash
# ============================================================
#   Crear todas las VMs del TFG desde la plantilla
#   Ejecutar en la SHELL DE PROXMOX como root
#
#   IMPORTANTE: Usa el bridge TFG1 (la guía PDF dice vmbr1 — está MAL)
# ============================================================

set -euo pipefail

TEMPLATE_ID=9000
BRIDGE="TFG1"       # <-- Correcto. NO usar vmbr1
STORAGE="local-lvm"
GW="10.0.100.1"

echo "=== Creando VMs del TFG SecureOps ==="
echo "  Plantilla: $TEMPLATE_ID | Bridge: $BRIDGE"
echo ""

clone_vm() {
    local id=$1 name=$2 mem=$3 cores=$4 ip=$5 extra=${6:-}
    echo "[+] Creando $name (ID: $id)..."
    qm clone $TEMPLATE_ID $id --name "$name" --full
    qm set $id --memory $mem --cores $cores
    qm set $id --ipconfig0 ip=${ip}/24,gw=${GW}
    if [ -n "$extra" ]; then eval "$extra"; fi
    echo "    OK"
}

# VM 101 — srv-linux: DNS + Web + Proxy
clone_vm 101 "srv-linux"     2048 2 "10.0.100.10"

# VM 102 — srv-wazuh: SIEM (más RAM y disco para Wazuh+Elastic)
clone_vm 102 "srv-wazuh"     4096 2 "10.0.100.20" \
    "qm resize 102 scsi0 +30G"

# VM 103 — srv-monitoring: Grafana + Prometheus + Loki
clone_vm 103 "srv-monitoring" 2048 2 "10.0.100.30"

# VM 104 — srv-suricata: Suricata IDS
clone_vm 104 "srv-suricata"  2048 2 "10.0.100.40"

# VM 110 — srv-control: Bastión + Tailscale + Ansible
# Esta VM tiene DOS interfaces:
#   net0 → vmbr0  (red personal, para acceso internet durante setup)
#   net1 → TFG1   (red del TFG, IP fija)
echo "[+] Creando srv-control (ID: 110)..."
qm clone $TEMPLATE_ID 110 --name "srv-control" --full
qm set 110 --memory 2048 --cores 2
qm set 110 --net0 virtio,bridge=vmbr0      # Temporal: internet para instalar Tailscale
qm set 110 --net1 virtio,bridge=$BRIDGE    # Red TFG permanente
qm set 110 --ipconfig0 ip=dhcp             # vmbr0: DHCP
qm set 110 --ipconfig1 ip=10.0.100.60/24,gw=$GW  # TFG1: IP fija
echo "    OK"

echo ""
echo "=== Arrancando VMs ==="
for vmid in 101 102 103 104 110; do
    qm start $vmid
    echo "  VM $vmid arrancada"
done

echo ""
echo "=== Espera ~90 segundos a que arranquen ==="
echo ""
echo "Verifica acceso SSH (desde la red TFG o srv-control):"
echo "  ssh admin@10.0.100.10  # srv-linux"
echo "  ssh admin@10.0.100.20  # srv-wazuh"
echo "  ssh admin@10.0.100.30  # srv-monitoring"
echo "  ssh admin@10.0.100.40  # srv-suricata"
echo ""
echo "Siguiente paso: Copia el repo a srv-control y ejecuta los playbooks"
echo "  scp -r secureops-tfg/ admin@<IP-srv-control>:~/"
echo "  ssh admin@<IP-srv-control>"
echo "  sudo apt install ansible -y"
echo "  cd secureops-tfg/ansible"
echo "  ansible all -m ping"
