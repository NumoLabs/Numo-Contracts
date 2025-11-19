#!/bin/bash
set -e

# Función para cargar .env
load_env() {
    if [ -f .env ]; then
        # Cargar variables del archivo .env
        while IFS= read -r line; do
            # Ignorar comentarios y líneas vacías
            if [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ -n "$line" ]]; then
                export "$line"
            fi
        done < .env
    fi
}

# Cargar variables de entorno
load_env

# Verificar que la variable esté cargada
if [ -z "$MAINNET_RPC_URL" ]; then
    echo "Error: MAINNET_RPC_URL no está definida"
    exit 1
fi

echo "Variables de entorno cargadas:"
echo "MAINNET_RPC_URL = $MAINNET_RPC_URL"

# Ejecutar snforge test
snforge test
