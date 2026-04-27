#!/bin/bash
# ============================================================
#   Crear VM plantilla Ubuntu 22.04 con CloudInit
#   Ejecutar en la SHELL DE PROXMOX como root
#
#   IMPORTANTE: Usa el bridge TFG1 (la guía PDF dice vmbr1 — está MAL)
# ============================================================

set -euo pipefail

TEMPLATE_ID=9000
TEMPLATE_NAME="ubuntu-template"
BRIDGE="TFG1"           # <-- Correcto. NO usar vmbr1
STORAGE="local-lvm"
IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
IMAGE_FILE="/tmp/jammy-server-cloudimg-amd64.img"

echo "=== Creando plantilla Ubuntu 22.04 con CloudInit (ID: $TEMPLATE_ID) ==="

# Verificar que no existe ya
if qm status $TEMPLATE_ID &>/dev/null; then
    echo "ERROR: Ya existe una VM con ID $TEMPLATE_ID"
    echo "Elimínala primero con: qm destroy $TEMPLATE_ID"
    exit 1
fi

# Descargar imagen cloud si no existe
if [ ! -f "$IMAGE_FILE" ]; then
    echo "[1/6] Descargando imagen cloud Ubuntu 22.04..."
    wget -q --show-progress "$IMAGE_URL" -O "$IMAGE_FILE"
else
    echo "[1/6] Imagen ya descargada, reutilizando."
fi

echo "[2/6] Creando VM..."
qm create $TEMPLATE_ID \
    --name "$TEMPLATE_NAME" \
    --memory 2048 \
    --cores 2 \
    --net0 virtio,bridge=$BRIDGE \
    --ostype l26 \
    --agent enabled=1

echo "[3/6] Importando disco..."
qm importdisk $TEMPLATE_ID "$IMAGE_FILE" $STORAGE

echo "[4/6] Configurando disco y arranque..."
qm set $TEMPLATE_ID --scsihw virtio-scsi-pci --scsi0 $STORAGE:vm-${TEMPLATE_ID}-disk-0
qm set $TEMPLATE_ID --ide2 $STORAGE:cloudinit
qm set $TEMPLATE_ID --boot c --bootdisk scsi0
qm set $TEMPLATE_ID --serial0 socket --vga serial0

# Ampliar disco a 20G
qm resize $TEMPLATE_ID scsi0 20G

echo "[5/6] Configurando CloudInit..."
qm set $TEMPLATE_ID --ciuser admin
qm set $TEMPLATE_ID --cipassword 'TFG2025!'
qm set $TEMPLATE_ID --ipconfig0 ip=dhcp

# Generar clave SSH si no existe
if [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo "  Generando clave SSH..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -q
fi
qm set $TEMPLATE_ID --sshkeys ~/.ssh/id_rsa.pub

echo "[6/6] Convirtiendo a plantilla..."
qm template $TEMPLATE_ID

echo ""
echo "=== Plantilla creada correctamente ==="
echo "  ID: $TEMPLATE_ID | Nombre: $TEMPLATE_NAME | Bridge: $BRIDGE"
echo ""
echo "Siguiente paso: bash 02-create-vms.sh"
