#!/bin/bash

set -euo pipefail

error_msg() {
    echo -e "\e[31m$1\e[0m"
}

info_msg() {
    echo -e "\e[32m$1\e[0m"
}

DOWNLOAD_DIR="$HOME/downloads"
APPIMAGE_OUTPUT="$HOME/output"

mkdir -p "$DOWNLOAD_DIR" "$APPIMAGE_OUTPUT"

info_msg "🔄 Atualizando pacotes e instalando dependências..."
sudo apt update -y
sudo apt install -y apt-rdepends git gh

if [ $# -eq 1 ]; then
    PACKAGE_LIST="$1"
else
    PACKAGE_LIST=$(apt list --all-versions | grep -o '^[^/]*')
fi

setup_git_repo() {
    local package=$1
    local repo_name="${package}-repo"

    cd "$APPIMAGE_OUTPUT"
    if [ ! -d "$repo_name/.git" ]; then
        mkdir "$repo_name"
        cd "$repo_name"
        git init
        git config --global push.default current
        echo "# Repositório de AppImages para $package" > README.md
        git add README.md
        git commit -m "Commit inicial"
        if gh repo create "$repo_name" --public --source=. --remote=origin; then
            info_msg "📦 Repositório Git inicializado e criado no GitHub com o nome $repo_name."
        else
            info_msg "⚠️ O repositório $repo_name já existe. Continuando..."
        fi
    else
        cd "$repo_name"
        git checkout main || git checkout -b main
        git pull origin main || true
        info_msg "🔄 Repositório atualizado a partir do GitHub."
    fi
    cd - > /dev/null
}

upload_to_github() {
    local package=$1
    local repo_name="${package}-repo"
    local repo_path="$APPIMAGE_OUTPUT/$repo_name"

    mv "$APPIMAGE_OUTPUT/${package}.appimage" "$repo_path/" || {
        error_msg "❌ Erro ao mover o AppImage para o repositório."
    }

    cd "$repo_path"

    info_msg "🔄 Criando uma nova branch para $package..."
    git checkout -b "${package}-branch" || {
        git checkout main
        git pull origin main
        git checkout -b "${package}-branch"
    }

    info_msg "🔄 Adicionando o AppImage ao repositório Git..."
    git add "${package}.appimage"

    local commit_message="$(date '+%Y-%m-%d') - Adiciona AppImage para $package"
    info_msg "🔄 Fazendo o commit do AppImage com a mensagem: $commit_message"
    git commit --no-edit -m "$commit_message"

    gh pr create --title "Add $package AppImage" --body "AppImage do pacote $package." --head "${package}-branch" --base main

    git checkout main || true
    git branch -D "${package}-branch" || true
    cd - > /dev/null
}

process_package() {
    local package=$1
    local appdir="$DOWNLOAD_DIR/$package.AppDir"

    mkdir -p "$appdir"

    info_msg "🔍 Resolvendo dependências para $package..."
    local deps
    deps=$(apt-rdepends "$package" | grep -v "^ " | grep -v "<" || true)

    info_msg "⚠️ Tentando baixar o pacote $package do repositório..."
    apt download "$package" -o Dir::Cache::archives="$DOWNLOAD_DIR" || {
        error_msg "⚠️ Erro ao baixar o pacote $package. Pulando..."
        return
    }

    sleep 2

    info_msg "🔍 Verificando arquivos .deb em $DOWNLOAD_DIR..."
    local deb_file=$(ls "$DOWNLOAD_DIR"/*.deb 2>/dev/null || ls ~/*.deb 2>/dev/null | head -n 1)

    if [ -n "$deb_file" ]; then
        info_msg "📥 Extraindo $deb_file..."
        dpkg-deb -x "$deb_file" "$appdir" || {
            error_msg "❌ Erro ao extrair $deb_file. Pulando..."
            return
        }
    else
        error_msg "⚠️ Arquivo .deb não encontrado após download. Conteúdo do diretório:"
        ls "$DOWNLOAD_DIR" ~
        return
    fi

    local desktop_file=$(find "$appdir/usr/share/applications" -name '*.desktop' | head -n 1)

    if [ -n "$desktop_file" ]; then
        info_msg "🔄 Copiando $desktop_file para $appdir..."
        cp "$desktop_file" "$appdir" || {
            error_msg "❌ Erro ao copiar o arquivo .desktop. Pulando..."
            return
        }
    else
        error_msg "⚠️ Arquivo .desktop não encontrado. Não é possível criar o AppImage para $package."
	rm *.deb
        return
    fi

    local icon_name
    icon_name=$(grep -oP '^Icon=\K.*' "$desktop_file" | head -n 1)

    if [ -n "$icon_name" ]; then
        local icon_path=$(find /usr/share/icons /usr/share/pixmaps "$appdir" -name "$icon_name.*" 2>/dev/null | head -n 1)

        if [ -n "$icon_path" ]; then
            cp "$icon_path" "$appdir/" || {
                error_msg "❌ Erro ao copiar a imagem do ícone $icon_name. Pulando..."
                return
            }
            info_msg "🔄 Imagem do ícone encontrada e copiada."
        else
            error_msg "⚠️ Imagem do ícone $icon_name não encontrada. Tentando verificar outros diretórios..."
            local alternative_icon_path=$(find ~ -name "$icon_name.*" 2>/dev/null | head -n 1)
            if [ -n "$alternative_icon_path" ]; then
                cp "$alternative_icon_path" "$appdir/" || {
                    error_msg "❌ Erro ao copiar a imagem do ícone do diretório alternativo. Pulando..."
                    return
                }
                info_msg "🔄 Imagem do ícone encontrada e copiada do diretório alternativo."
            else
                error_msg "⚠️ Nenhuma imagem de ícone encontrada. Não é possível criar o AppImage para $package."
		rm *.deb
                return
            fi
        fi
    fi

    info_msg "🔧 Tentando criar AppImage para $package usando $desktop_file..."
    local appimage_name="${package}.appimage"
    if appimagetool "$appdir" "$APPIMAGE_OUTPUT/$appimage_name"; then
        info_msg "✅ AppImage para $package criado em $APPIMAGE_OUTPUT/$appimage_name"
        
        setup_git_repo "$package"

        upload_to_github "$package"
    else
        error_msg "❌ Erro ao criar AppImage para $package."
    fi
	rm *.deb

    info_msg "🗑️ Limpando arquivos temporários..."
    rm -rf "$appdir"
}

for package in $PACKAGE_LIST; do
    package=$(echo "$package" | tr '[:upper:]' '[:lower:]')
    info_msg "🔍 Processando o pacote: $package"
    process_package "$package" || {
        error_msg "⚠️ Falha ao processar o pacote $package."
        continue
    }
done

info_msg "🗑️ Limpando arquivos temporários finais..."
rm -rf "$DOWNLOAD_DIR" "$APPIMAGE_OUTPUT"*.deb
info_msg "🎉 Criação dos pacotes do Kuros concluída com sucesso!"
