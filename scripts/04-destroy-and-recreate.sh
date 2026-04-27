#!/bin/bash
# ============================================================
#   DEMO FINAL: Destruir y recrear toda la infraestructura
#   Ejecutar en la SHELL DE PROXMOX como root
#
#   Objetivo: Demostrar que la empresa entera se recrea
#   desde cero en menos de 20 minutos con un solo comando.
#
#   ADVERTENCIA: Este script DESTRUYE VMs. Solo actúa sobre
#   IDs 101-104. Nunca toca vmbr0, VMs personales ni IDs fuera
#   del rango 100-199.
# ============================================================

set -euo pipefail

TFG_VMS=(101 102 103 104)
TEMPLATE_ID=9000
BRIDGE="TFG1"
GW="10.0.100.1"
ANSIBLE_DIR="/root/secureops-tfg/ansible"

echo "================================================="
echo "  SecureOps — Demo: Destruir y Recrear"
echo "================================================="
echo ""
echo "VMs que se van a DESTRUIR y recrear: ${TFG_VMS[*]}"
echo "Plantilla: $TEMPLATE_ID | Bridge: $BRIDGE"
echo ""
echo "IMPORTANTE: Este script NO toca:"
echo "  - vmbr0 ni VMs personales"
echo "  - pfSense (VM 100)"
echo "  - srv-control (VM 110)"
echo ""
read -rp "Escribe 'DEMO' para confirmar: " confirm
if [ "$confirm" != "DEMO" ]; then
    echo "Cancelado."
    exit 0
fi

START_TIME=$(date +%s)

echo ""
echo "--- [1/6] Apagando VMs del TFG ---"
for vmid in "${TFG_VMS[@]}"; do
    echo "  Apagando VM $vmid..."
    qm stop "$vmid" --timeout 30 2>/dev/null || echo "  (ya estaba apagada)"
done
sleep 5

echo ""
echo "--- [2/6] Destruyendo VMs ---"
for vmid in "${TFG_VMS[@]}"; do
    if qm status "$vmid" &>/dev/null; then
        qm destroy "$vmid" --purge
        echo "  VM $vmid destruida"
    fi
done

echo ""
echo "--- [3/6] Recreando desde plantilla ---"

clone_vm() {
    local id=$1 name=$2 mem=$3 ip=$4 extra=${5:-}
    echo "  Creando $name (ID: $id)..."
    qm clone $TEMPLATE_ID $id --name "$name" --full
    qm set $id --memory $mem --cores 2
    qm set $id --ipconfig0 ip=${ip}/24,gw=${GW}
    if [ -n "$extra" ]; then eval "$extra"; fi
}

clone_vm 101 "srv-linux"      2048 "10.0.100.10"
clone_vm 102 "srv-wazuh"      4096 "10.0.100.20" "qm resize 102 scsi0 +30G"
clone_vm 103 "srv-monitoring" 2048 "10.0.100.30"
clone_vm 104 "srv-suricata"   2048 "10.0.100.40"

echo ""
echo "--- [4/6] Arrancando VMs ---"
for vmid in "${TFG_VMS[@]}"; do
    qm start "$vmid"
    echo "  VM $vmid arrancada"
done

echo ""
echo "--- [5/6] Esperando que arranquen (60s) ---"
sleep 60

echo ""
echo "--- [6/6] DESPLEGANDO TODA LA INFRAESTRUCTURA ---"
echo "    Comando: ansible-playbook deploy-all.yml"
echo ""

if [ -d "$ANSIBLE_DIR" ]; then
    cd "$ANSIBLE_DIR"
    ansible-playbook -i inventory/hosts.yml playbooks/deploy-all.yml
else
    echo "AVISO: No se encontró $ANSIBLE_DIR"
    echo "Ejecuta manualmente:"
    echo "  cd /ruta/secureops-tfg/ansible"
    echo "  ansible-playbook -i inventory/hosts.yml playbooks/deploy-all.yml"
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS_REM=$((ELAPSED % 60))

echo ""
echo "================================================="
echo "  DEMO COMPLETADA"
echo "  Tiempo total: ${MINUTES}m ${SECONDS_REM}s"
echo ""
echo "  Servicios:"
echo "  - Web:     http://10.0.100.10"
echo "  - DNS:     10.0.100.10:53"
echo "  - Proxy:   10.0.100.10:3128"
echo "  - Wazuh:   https://10.0.100.20"
echo "  - Grafana: http://10.0.100.30:3000"
echo "================================================="
