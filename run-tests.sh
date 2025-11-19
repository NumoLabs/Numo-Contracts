#!/bin/bash
set -e

# Cambiar al directorio del script
cd "$(dirname "$0")"

# Cargar variables de entorno
if [ -f .env ]; then
    echo "Cargando variables de entorno desde .env..."
    export $(grep -v '^#' .env | xargs)
    echo "MAINNET_RPC_URL cargada: $MAINNET_RPC_URL"
else
    echo "Archivo .env no encontrado"
    exit 1
fi

# Ejecutar tests
echo "Ejecutando tests..."
scarb test
