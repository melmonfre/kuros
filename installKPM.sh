#!/bin/bash

set -euo pipefail

KPM_SCRIPT="kpm.sh"
INSTALL_DIR="/usr/local/bin"  # Ou use "/scripts" se preferir
KPM_URL="https://raw.githubusercontent.com/melmonfre/kuros/refs/heads/main/$KPM_SCRIPT"  # Substitua pelo URL real do seu script

# Baixar o script KPM
info_msg() {
    echo -e "\e[32m$1\e[0m"
}

error_msg() {
    echo -e "\e[31m$1\e[0m"
}

# Verifica se o script já existe
if [ -f "$INSTALL_DIR/$KPM_SCRIPT" ]; then
    error_msg "⚠️ O KurOS Package Manager já está instalado em $INSTALL_DIR."
    exit 1
fi

# Baixa o script KPM
info_msg "🔄 Baixando o KurOS Package Manager..."
curl -s -o "$INSTALL_DIR/$KPM_SCRIPT" "$KPM_URL"

# Adiciona permissões de execução
chmod +x "$INSTALL_DIR/$KPM_SCRIPT"

# Adiciona o diretório ao PATH de todos os usuários
if ! grep -q "$INSTALL_DIR" /etc/profile; then
    echo "export PATH=\$PATH:$INSTALL_DIR" | sudo tee -a /etc/profile > /dev/null
    info_msg "✅ Diretório $INSTALL_DIR adicionado ao PATH de todos os usuários."
fi

info_msg "🎉 KurOS Package Manager instalado com sucesso em $INSTALL_DIR!"
info_msg "🔄 Para aplicar as mudanças de PATH, faça logout e login novamente ou execute 'source /etc/profile'."
