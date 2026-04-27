#!/bin/bash
# ============================================================
#   Configurar Tailscale en srv-control para acceso remoto
#   Ejecutar DENTRO de srv-control (no en Proxmox host)
#
#   Tailscale sustituye a WireGuard porque el router no
#   permite port forwarding (la guía PDF dice WireGuard — está MAL)
#
#   Resultado: Iker y Hamza pueden llegar a 10.0.100.0/24
#   desde sus PCs sin necesidad de abrir puertos en el router
# ============================================================

set -euo pipefail

echo "=== Instalando Tailscale en srv-control ==="

# Instalar Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Habilitar IP forwarding (necesario para anunciar la subnet TFG)
echo "=== Habilitando IP forwarding ==="
cat > /etc/sysctl.d/99-tailscale.conf << 'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-tailscale.conf

# Arrancar Tailscale como subnet router
# Esto expone 10.0.100.0/24 a todos los miembros del tailnet
echo "=== Registrando en Tailscale ==="
echo "  (Abrirá una URL — accede desde cualquier navegador)"
tailscale up --advertise-routes=10.0.100.0/24 --accept-routes

echo ""
echo "=============================================="
echo "  PASOS SIGUIENTES (hacer UNA VEZ)"
echo "=============================================="
echo ""
echo "1. Entra a https://login.tailscale.com/admin/machines"
echo "2. Busca 'srv-control' y aprueba las rutas (10.0.100.0/24)"
echo "   -> Edit route settings -> Enable route"
echo ""
echo "3. Comparte el tailnet con Iker y Hamza:"
echo "   -> Settings -> Users -> Invite users"
echo "   O usa: tailscale share <nodo>"
echo ""
echo "4. Iker y Hamza instalan Tailscale en sus PCs:"
echo "   - Linux:   curl -fsSL https://tailscale.com/install.sh | sh"
echo "   - Windows: descarga de tailscale.com/download"
echo ""
echo "5. Se conectan con: tailscale up"
echo ""
echo "6. Verifican acceso:"
echo "   ping 10.0.100.10   # debe funcionar sin VPN ni port forwarding"
echo ""
echo "Tailscale IP de srv-control:"
tailscale ip -4
