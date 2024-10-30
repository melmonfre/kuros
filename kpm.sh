#!/bin/bash

set -euo pipefail

# Configurações
BASE_DIR="$HOME/.local/packages"
APPLICATIONS_DIR="$HOME/.local/share/applications"
REPO_URL="https://ftp.debian.org/debian/dists/testing"

# Função para exibir mensagens de erro
error_msg() {
    echo -e "\e[31m$1\e[0m"
}

# Função para exibir mensagens informativas
info_msg() {
    echo -e "\e[32m$1\e[0m"
}

# Função para resolver dependências
resolve_dependencies() {
    local package="$1"
    local dependencies=""

    info_msg "🔍 Resolvendo dependências para $package..."
    local pkg_info=$(wget -qO- "$REPO_URL/main/binary-amd64/Packages.gz" | gunzip | grep -A1000 "Package: $package" | grep -E "Package:|Depends:")

    while IFS= read -r line; do
        if [[ "$line" == Depends:* ]]; then
            dependencies+="${line:8}\n"
        fi
    done <<< "$pkg_info"

    echo -e "$dependencies" | tr -d ' ' | tr ',' '\n'
}

# Função para buscar pacotes semelhantes
find_similar_packages() {
    local package="$1"
    local available_packages=$(wget -qO- "$REPO_URL/main/binary-amd64/Packages.gz" | gunzip | grep "Package:" | awk '{print $2}')

    local similar_packages=$(echo "$available_packages" | grep -E "$package" | head -n 10)

    if [ -z "$similar_packages" ]; then
        error_msg "⚠️ Nenhum pacote correspondente encontrado para $package."
        exit 1
    fi

    echo "$similar_packages"
}

# Função para baixar um pacote
download_package() {
    local package="$1"
    local package_dir="$BASE_DIR/$package"

    local similar_packages=$(find_similar_packages "$package")
    local selected_package=""

    if [[ $(echo "$similar_packages" | wc -l) -eq 1 ]]; then
        selected_package="$similar_packages"
    else
        info_msg "🔍 Pacotes semelhantes encontrados:"
        echo "$similar_packages" | nl
        read -p "Escolha o número do pacote que deseja instalar: " choice
        selected_package=$(echo "$similar_packages" | sed -n "${choice}p")
    fi

    info_msg "🔍 Baixando pacote: $selected_package"
    mkdir -p "$package_dir"

    local pkg_info=$(wget -qO- "$REPO_URL/main/binary-amd64/Packages.gz" | gunzip | grep -A10 "Package: $selected_package")

    local deb_url=$(echo "$pkg_info" | grep "Filename:" | awk '{print $2}')
    deb_url="https://ftp.debian.org/debian/$deb_url"

    wget -P "$package_dir" "$deb_url"

    local dependencies=$(resolve_dependencies "$selected_package")
    while IFS= read -r dep; do
        download_package "$dep"
    done <<< "$dependencies"

    info_msg "🔧 Instalando pacote $selected_package..."
    mkdir -p "$package_dir/usr/bin"
    dpkg-deb -x "$package_dir/${selected_package}_*.deb" "$package_dir"

    local desktop_file=$(find "$package_dir/usr/share/applications" -name "*.desktop" -print -quit)
    if [[ -f "$desktop_file" ]]; then
        cp "$desktop_file" "$APPLICATIONS_DIR/"
        info_msg "✅ Arquivo .desktop copiado para $APPLICATIONS_DIR."
    fi
}

# Função para atualizar um pacote
update_package() {
    local package="$1"
    info_msg "🔄 Atualizando pacote: $package"

    uninstall_package "$package"
    download_package "$package"
}

# Função para desinstalar um pacote
uninstall_package() {
    local package="$1"
    local package_dir="$BASE_DIR/$package"

    if [[ -d "$package_dir" ]]; then
        info_msg "🔍 Removendo pacote: $package"
        rm -rf "$package_dir"

        local desktop_file="$APPLICATIONS_DIR/${package}.desktop"
        if [[ -f "$desktop_file" ]]; then
            rm "$desktop_file"
            info_msg "✅ Arquivo .desktop removido de $APPLICATIONS_DIR."
        fi

        info_msg "🎉 Pacote $package removido com sucesso!"
    else
        error_msg "⚠️ Pacote $package não encontrado."
    fi
}

# Função para procurar um pacote
search_package() {
    local package="$1"
    local available_packages=$(wget -qO- "$REPO_URL/main/binary-amd64/Packages.gz" | gunzip | grep "Package:" | awk '{print $2}')

    info_msg "🔍 Procurando pacotes correspondentes a: $package"
    local results=$(echo "$available_packages" | grep -E "$package")

    if [ -z "$results" ]; then
        error_msg "⚠️ Nenhum pacote encontrado para: $package."
    else
        echo "$results" | nl
    fi
}

# Função para verificar a integridade dos pacotes instalados
check_integrity() {
    info_msg "🔍 Verificando integridade dos pacotes instalados..."
    local packages=$(ls "$BASE_DIR")

    for package in $packages; do
        if [[ ! -d "$BASE_DIR/$package" ]]; then
            error_msg "⚠️ O pacote $package está quebrado ou ausente."
            uninstall_package "$package"
        fi
    done

    info_msg "✅ Verificação de integridade concluída!"
}

# Função de ajuda
show_help() {
    cat << EOF
KurOS Package Manager (KPM)

Uso:
  kpm [comando] [pacote]

Comandos:
  instalar   Instala um pacote e suas dependências.
  atualizar   Atualiza um pacote já instalado.
  remover    Remove um pacote e suas dependências.
  procurar   Procura por pacotes disponíveis que correspondam ao nome fornecido.
  quebrado   Verifica a integridade dos pacotes instalados.

Exemplos:
  kpm instalar firefox
  kpm atualizar firefox
  kpm remover firefox
  kpm procurar firefox
  kpm quebrado

EOF
}

# Função principal
main() {
    if [[ $# -lt 2 ]]; then
        show_help
        exit 1
    fi

    local action="$1"
    local package="$2"

    case "$action" in
        instalar)
            download_package "$package"
            ;;
        atualizar)
            update_package "$package"
            ;;
        remover)
            uninstall_package "$package"
            ;;
        procurar)
            search_package "$package"
            ;;
        quebrado)
            check_integrity
            ;;
        *)
            error_msg "⚠️ Ação desconhecida: $action"
            show_help
            exit 1
            ;;
    esac
}

# Chamada à função principal
main "$@"
