# ==============================================================================
# CineData Analytics / Monorepo -- Sincronizacao e Compressao de Dados (data_sync.ps1)
# Compativel com Windows PowerShell 5.1+ e PowerShell Core (pwsh)
# Suporta extracao/compressao (serialize) e descompressao/reconstrucao (deserialize)
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Action = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$DataDir = Join-Path $RootDir "data"
$ArchiveName = "data.tar.xz"
$ArchivePath = Join-Path $DataDir $ArchiveName

function Test-CommandAvailable {
    param([string]$CommandName)
    return [bool](Get-Command $CommandName -ErrorAction SilentlyContinue)
}

# Localiza runtime Python disponivel
$PythonCmd = $null
$CoreVenvPy = Join-Path (Join-Path $RootDir "core-platform\backend") ".venv\Scripts\python.exe"
$AiVenvPy = Join-Path (Join-Path $RootDir "ai-assistant\backend") ".venv\Scripts\python.exe"

if (Test-Path $CoreVenvPy) {
    $PythonCmd = $CoreVenvPy
} elseif (Test-Path $AiVenvPy) {
    $PythonCmd = $AiVenvPy
} elseif (Test-CommandAvailable "uv") {
    $PythonCmd = "uv run python"
} elseif (Test-CommandAvailable "python") {
    $PythonCmd = "python"
} elseif (Test-CommandAvailable "python3") {
    $PythonCmd = "python3"
} elseif (Test-CommandAvailable "py") {
    $PythonCmd = "py"
}

switch ($Action.ToLower()) {
    { $_ -in @("cp", "serialize", "compress") } {
        Write-Host "`n[>] Iniciando arquivamento e compressao de dados em $DataDir..." -ForegroundColor Cyan

        $LandingDir = Join-Path $DataDir "landing"
        $GoldDir = Join-Path $DataDir "gold"
        if ((-not (Test-Path $LandingDir)) -or (-not (Test-Path $GoldDir))) {
            Write-Host "[ERRO] Pastas 'data/landing' e 'data/gold' nao encontradas em: $DataDir" -ForegroundColor Red
            exit 1
        }

        # Limpeza de arquivos existentes
        Remove-Item -Path $ArchivePath -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path "$ArchivePath.part-*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

        Write-Host "   [>] Comprimindo data/landing e data/gold para $ArchiveName..." -ForegroundColor Cyan

        if ($null -eq $PythonCmd) {
            Write-Host "[ERRO] Runtime Python nao encontrado para compressao tar.xz." -ForegroundColor Red
            exit 1
        }

        $CompressScript = @"
import tarfile, lzma
archive = r'$ArchivePath'
data_dir = r'$DataDir'
with open(archive, 'wb') as f_out:
    with lzma.open(f_out, 'wb', preset=6) as f_xz:
        with tarfile.open(fileobj=f_xz, mode='w') as tar:
            tar.add(f'{data_dir}/landing', arcname='landing')
            tar.add(f'{data_dir}/gold', arcname='gold')
"@
        & $PythonCmd -c $CompressScript
        if ($LASTEXITCODE -ne 0) { throw "Falha na compressao do arquivo $ArchiveName" }

        $ArchSizeMB = [math]::Round(((Get-Item $ArchivePath).Length / 1MB), 2)
        Write-Host "   [OK] Arquivo gerado: $ArchivePath ($ArchSizeMB MB)" -ForegroundColor Green

        Write-Host "   [>] Dividindo $ArchiveName em partes de 45MB..." -ForegroundColor Cyan
        $SplitScript = @"
import os
chunk_size = 45 * 1024 * 1024
archive = r'$ArchivePath'
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
"@
        & $PythonCmd -c $SplitScript
        if ($LASTEXITCODE -ne 0) { throw "Falha na divisao em chunks" }

        Write-Host "   [OK] Partes geradas com sucesso!" -ForegroundColor Green
        Get-ChildItem -Path "$ArchivePath.part-*" | ForEach-Object {
            $PartSizeMB = [math]::Round(($_.Length / 1MB), 2)
            Write-Host "   - $($_.Name) ($PartSizeMB MB)" -ForegroundColor Gray
        }
        break
    }

    { $_ -in @("dc", "deserialize", "decompress") } {
        Write-Host "`n[>] Verificando e restaurando arquivos CSV a partir dos chunks..." -ForegroundColor Cyan

        if (-not (Test-Path $ArchivePath)) {
            $parts = Get-ChildItem -Path "$ArchivePath.part-*" -ErrorAction SilentlyContinue
            if ($parts.Count -gt 0) {
                Write-Host "   [>] Recombinando partes de $ArchiveName..." -ForegroundColor Cyan
                $CombineScript = @"
import glob
parts = sorted(glob.glob(r'$ArchivePath.part-*'))
with open(r'$ArchivePath', 'wb') as outfile:
    for p in parts:
        with open(p, 'rb') as infile:
            outfile.write(infile.read())
"@
                if ($null -eq $PythonCmd) {
                    Write-Host "[ERRO] Runtime Python nao encontrado para recombinar chunks." -ForegroundColor Red
                    exit 1
                }
                & $PythonCmd -c $CombineScript
                if ($LASTEXITCODE -ne 0) { throw "Falha ao recombinar chunks" }
            } else {
                Write-Host "[ERRO] Nem '$ArchivePath' nem chunks '.part-*' foram encontrados em: $DataDir" -ForegroundColor Red
                exit 1
            }
        }

        Write-Host "   [>] Descomprimindo $ArchiveName para $DataDir..." -ForegroundColor Cyan
        $ExtractScript = @"
import tarfile, lzma
archive = r'$ArchivePath'
data_dir = r'$DataDir'
with lzma.open(archive, 'rb') as f_xz:
    with tarfile.open(fileobj=f_xz, mode='r') as tar:
        tar.extractall(data_dir)
"@
        & $PythonCmd -c $ExtractScript
        if ($LASTEXITCODE -ne 0) { throw "Falha ao descompactar $ArchiveName" }

        Write-Host "   [OK] Arquivos CSV restaurados com sucesso em $DataDir/landing e $DataDir/gold!" -ForegroundColor Green
        break
    }

    default {
        Write-Host "Uso: .\scripts\data_sync.ps1 {serialize|deserialize}" -ForegroundColor Yellow
        Write-Host "  serialize   (ou cp) -> Compacta data/landing e data/gold em partes de 45MB" -ForegroundColor Gray
        Write-Host "  deserialize (ou dc) -> Recombina as partes e extrai os CSVs para data/" -ForegroundColor Gray
        exit 1
    }
}
