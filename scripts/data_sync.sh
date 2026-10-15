#!/usr/bin/env bash
# ==============================================================================
# CineData Analytics / Monorepo -- Sincronizacao e Compressao de Dados (data_sync.sh)
# Suporta extracao/compressao (serialize) e descompressao/reconstrucao (deserialize)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
ARCHIVE_NAME="data.tar.xz"
ARCHIVE_PATH="$DATA_DIR/$ARCHIVE_NAME"
CHUNK_SIZE="45M"

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[36m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_RED="\033[31m"

ACTION="${1:-}"

# Localiza runtime Python disponivel
PYTHON_CMD=""
if [ -f "$ROOT_DIR/core-platform/backend/.venv/bin/python" ]; then
  PYTHON_CMD="$ROOT_DIR/core-platform/backend/.venv/bin/python"
elif [ -f "$ROOT_DIR/ai-assistant/backend/.venv/bin/python" ]; then
  PYTHON_CMD="$ROOT_DIR/ai-assistant/backend/.venv/bin/python"
elif command -v uv &> /dev/null; then
  PYTHON_CMD="uv run python"
elif command -v python3 &> /dev/null; then
  PYTHON_CMD="python3"
elif command -v python &> /dev/null; then
  PYTHON_CMD="python"
fi

case "$ACTION" in
  serialize|compress|cp)
    echo -e "\n${C_CYAN}[>] Iniciando arquivamento e compressao de dados em $DATA_DIR...${C_RESET}"

    if [ ! -d "$DATA_DIR/landing" ] || [ ! -d "$DATA_DIR/gold" ]; then
      echo -e "${C_RED}[ERRO] Pastas 'data/landing' e 'data/gold' nao encontradas em: $DATA_DIR${C_RESET}"
      exit 1
    fi

    # Limpeza de chunks e arquivos antigos
    rm -f "$ARCHIVE_PATH" "${ARCHIVE_PATH}.part-"*

    echo -e "   [>] Comprimindo data/landing e data/gold para $ARCHIVE_NAME..."
    if command -v tar &> /dev/null && command -v xz &> /dev/null; then
      tar -c -C "$DATA_DIR" landing gold | xz -T0 -6 > "$ARCHIVE_PATH"
    elif [ -n "$PYTHON_CMD" ]; then
      $PYTHON_CMD -c "
import tarfile, lzma
with open('$ARCHIVE_PATH', 'wb') as f_out:
    with lzma.open(f_out, 'wb', preset=6) as f_xz:
        with tarfile.open(fileobj=f_xz, mode='w') as tar:
            tar.add('$DATA_DIR/landing', arcname='landing')
            tar.add('$DATA_DIR/gold', arcname='gold')
"
    else
      echo -e "${C_RED}[ERRO] Nem 'tar+xz' nem 'python3' estao disponiveis para compressao.${C_RESET}"
      exit 1
    fi

    ARCH_SIZE=$(du -sh "$ARCHIVE_PATH" | cut -f1)
    echo -e "${C_GREEN}   [OK] Arquivo gerado: $ARCHIVE_PATH ($ARCH_SIZE)${C_RESET}"

    echo -e "   [>] Dividindo $ARCHIVE_NAME em partes de $CHUNK_SIZE..."
    if command -v split &> /dev/null; then
      split -b "$CHUNK_SIZE" -d -a 2 "$ARCHIVE_PATH" "${ARCHIVE_PATH}.part-"
    else
      $PYTHON_CMD -c "
chunk_size = 45 * 1024 * 1024
archive = '$ARCHIVE_PATH'
with open(archive, 'rb') as f:
    chunk_idx = 0
    while True:
        chunk = f.read(chunk_size)
        if not chunk:
            break
        part_name = f'{archive}.part-{chunk_idx:02d}'
        with open(part_name, 'wb') as p:
            p.write(chunk)
        chunk_idx += 1
"
    fi

    echo -e "${C_GREEN}   [OK] Partes geradas:${C_RESET}"
    ls -lh "${ARCHIVE_PATH}.part-"*

    echo -e "${C_GREEN}   [OK] Processo de serializacao concluido com sucesso!${C_RESET}"
    ;;

  deserialize|decompress|dc)
    echo -e "\n${C_CYAN}[>] Verificando e restaurando arquivos CSV a partir dos chunks...${C_RESET}"

    # Recombinacao das partes se o arquivo .tar.xz nao existir
    if [ ! -f "$ARCHIVE_PATH" ]; then
      if ls "${ARCHIVE_PATH}.part-"* 1> /dev/null 2>&1; then
        echo -e "   [>] Recombinando partes em $ARCHIVE_PATH..."
        cat "${ARCHIVE_PATH}.part-"* > "$ARCHIVE_PATH"
      else
        echo -e "${C_RED}[ERRO] Chunks '${ARCHIVE_PATH}.part-*' nao encontrados em: $DATA_DIR${C_RESET}"
        exit 1
      fi
    fi

    echo -e "   [>] Descomprimindo $ARCHIVE_NAME para $DATA_DIR..."
    if command -v tar &> /dev/null && command -v xz &> /dev/null; then
      tar -xf "$ARCHIVE_PATH" -C "$DATA_DIR"
    elif [ -n "$PYTHON_CMD" ]; then
      $PYTHON_CMD -c "
import tarfile, lzma
with lzma.open('$ARCHIVE_PATH', 'rb') as f_xz:
    with tarfile.open(fileobj=f_xz, mode='r') as tar:
        tar.extractall('$DATA_DIR')
"
    else
      echo -e "${C_RED}[ERRO] Nem 'tar+xz' nem 'python3' estao disponiveis para descompressao.${C_RESET}"
      exit 1
    fi

    echo -e "${C_GREEN}   [OK] Arquivos CSV restaurados com sucesso em $DATA_DIR/landing e $DATA_DIR/gold!${C_RESET}"
    ;;

  *)
    echo -e "${C_YELLOW}Uso: ./scripts/data_sync.sh {serialize|deserialize}${C_RESET}"
    echo -e "  serialize   (ou cp) -> Compacta data/landing e data/gold em partes de 45MB"
    echo -e "  deserialize (ou dc) -> Recombina as partes e extrai os CSVs para data/"
    exit 1
    ;;
esac
