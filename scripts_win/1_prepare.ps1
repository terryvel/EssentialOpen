# Função para exibir mensagens de erro e sair
function ErrorExit {
    param ([string]$message)
    Write-Host $message -ForegroundColor Red
    exit 1
}

# Função para gerar uma senha aleatória de 8 caracteres
function Generate-Password {
    param (
        [int]$length = 12  # Define o tamanho da senha
    )

    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+"
    $password = -join ((1..$length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return $password
}


# Função para obter ou gerar senha
function Get-OrGenerate-Password {
    param ([string]$key)
    $file = "secret.txt"

    if (!(Test-Path $file)) {
        New-Item -ItemType File -Path $file | Out-Null
    }

    $lines = Get-Content $file
    foreach ($line in $lines) {
        if ($line -match "^$key=(.*)") {
            return $matches[1]
        }
    }

    $password = Generate-Password
    "$key=$password" | Add-Content $file
    return $password
}

# Função para obter ou adicionar variável de ambiente
function Get-OrAdd-EnvVar {
    param ([string]$key, [string]$value)
    $file = "env_file.env"
    
    if (!(Test-Path $file)) {
        New-Item -ItemType File -Path $file | Out-Null
    }

    $lines = Get-Content $file
    $found = $false
    
    $newLines = @()
    foreach ($line in $lines) {
        if ($line -match "^$key=(.*)") {
            $newLines += "$key=$value"
            $found = $true
        } else {
            $newLines += $line
        }
    }

    if (!$found) {
        "$key=$value" | Add-Content $file
    } else {
        $newLines | Set-Content $file
    }
}

# Função para extrair arquivos ZIP
function Unzip-File {
    param ([string]$zipFile, [string]$extractDir)
    
    if (!(Test-Path $extractDir)) {
        New-Item -ItemType Directory -Path $extractDir | Out-Null
    }

    if ((Get-ChildItem -Path $extractDir).Count -eq 0) {
        Write-Host "Unzipping $zipFile to $extractDir..."
        Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force
    } else {
        Write-Host "$extractDir is not empty, skipping unzip."
    }
}

function Unzip-WarFile {
    param (
        [string]$warFile,
        [string]$extractDir
    )

    if (!(Test-Path $extractDir)) {
        New-Item -ItemType Directory -Path $extractDir | Out-Null
    }

    $zipFile = $warFile -replace "\.war$", ".zip"
    Copy-Item -Path $warFile -Destination $zipFile -Force

    Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force
}

# Configurar o Git para evitar problemas com CRLF
Write-Host "Configurando Git para usar LF..."
git config --global core.autocrlf input

# Remover arquivos do cache do Git para corrigir formatação de linha
Write-Host "Removendo arquivos do cache do Git..."
git rm --cached -r .

# Resetar o repositório para garantir a formatação correta dos arquivos
Write-Host "Resetando o repositório..."
git reset --hard

Write-Host "Configuração do Git concluída."

Write-Host "1. Download files."

Get-Content downloads.txt | ForEach-Object {
    $parts = $_ -split ' '
    $downloadDir = $parts[0]
    $url = $parts[1]
    $filename = [System.IO.Path]::GetFileName($url)
    $destFile = "$downloadDir\$filename"

    if (!(Test-Path $destFile)) {
        Write-Host "Downloading $filename to $downloadDir..."
        if (!(Test-Path $downloadDir)) {
            New-Item -ItemType Directory -Path $downloadDir | Out-Null
        }
        Invoke-WebRequest -Uri $url -OutFile $destFile
    } else {
        Write-Host "$filename already exists in $downloadDir, skipping download."
    }
}

Write-Host "2. Extract repository and server files."
Unzip-File "protege/downloads/essential_baseline_v6_19.zip" "EssentialAM/Repository"
Unzip-File "protege/downloads/metaproject.zip" "EssentialAM/server"

Write-Host "3. Define Database Passwords"
$MYSQL_USER="essential"
$MYSQL_DATABASE="essentialdb"
$MYSQL_PASSWORD=Get-OrGenerate-Password "MYSQL_PASSWORD"
$MYSQL_ROOT_PASSWORD=Get-OrGenerate-Password "MYSQL_ROOT_PASSWORD"

Get-OrAdd-EnvVar "MYSQL_USER" $MYSQL_USER
Get-OrAdd-EnvVar "MYSQL_DATABASE" $MYSQL_DATABASE
Get-OrAdd-EnvVar "MYSQL_PASSWORD" $MYSQL_PASSWORD
Get-OrAdd-EnvVar "MYSQL_ROOT_PASSWORD" $MYSQL_ROOT_PASSWORD

Write-Host "4. Extract Viewer data"
Unzip-WarFile "viewer/downloads/essential_viewer_6210.war" "EssentialAM/essential_viewer"

$PUBLISHER_PASSWORD = Get-OrGenerate-Password "PUBLISHER_PASSWORD"

# Atualiza o tomcat-users.xml com a nova senha
$updatedContent = (Get-Content viewer/tomcat-users.xml) -replace 'username="publisher" password=".*?"', ('username="publisher" password="{0}"' -f $PUBLISHER_PASSWORD)
$updatedContent | Set-Content viewer/tomcat-users.xml

Copy-Item viewer/web.xml EssentialAM/essential_viewer/WEB-INF/web.xml -Force
Copy-Item viewer/core_header.xsl EssentialAM/essential_viewer/common/core_header.xsl -Force

Write-Host "PUBLISHER_PASSWORD=$PUBLISHER_PASSWORD"
Write-Host "You'll need this password to update viewer from Protégé"
