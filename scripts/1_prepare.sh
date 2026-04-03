#!/bin/bash

# Function to display error messages
function error_exit {
    echo "$1" 1>&2
    exit 1
}

# Function to generate a random password of 8 characters
generate_password() {
    openssl rand -base64 6
}

get_or_generate_password() {
    local key=$1
    local file="secret.txt"

    if [ ! -f "$file" ]; then
        touch "$file"
    fi

    if grep -q "^${key}=" "$file"; then
        awk -F'=' -v key="$key" '$1 == key {print substr($0, index($0,$2))}' "$file"
    else
        local password=$(generate_password)
        echo "${key}=${password}" >> "$file"
        echo "$password"
    fi
}

get_or_add_env_var() {
    local key=$1
    local file="env_file.env"
    local value=${!key}

    if [ ! -f "$file" ]; then
        touch "$file"
    fi

    if grep -q "^${key}=" "$file"; then
        current_value=$(awk -F'=' -v key="$key" '$1 == key {print substr($0, index($0,$2))}' "$file")
        if [ "$current_value" != "$value" ]; then
            perl -i -pe "s/^${key}=.*/${key}=${value}/" "$file"
        fi
    else
        echo "${key}=${!key}" >> "$file"
    fi
}

unzip_file() {
    local zip_file=$1
    local extract_dir=$2

    mkdir -p "$extract_dir"
    if [ -z "$(ls -A "$extract_dir")" ]; then
        echo "Unzipping $zip_file to $extract_dir..."
        unzip -o -q "$zip_file" -d "$extract_dir" || { echo "Failed to unzip $zip_file"; exit 1; }
        echo "File unzipped successfully."
    else
        echo "$extract_dir is not empty, skipping unzip."
    fi
}

echo

echo "1. Download files."
while IFS=' ' read -r DOWNLOAD_DIR URL; do
    FILENAME=$(basename "$URL")
    if [ ! -f "$DOWNLOAD_DIR/$FILENAME" ]; then
        echo "Downloading $FILENAME to $DOWNLOAD_DIR..."
        mkdir -p "$DOWNLOAD_DIR" # Cria o diretório se não existir
        curl -L -o "$DOWNLOAD_DIR/$FILENAME" "$URL" || error_exit "Failed to download $FILENAME"
    else
        echo "$FILENAME already exists in $DOWNLOAD_DIR, skipping download."
    fi
done < downloads.txt
echo

echo "2. Extract repository and server files."
REPO_FILE=$(cat downloads.txt| grep essential_baseline | cut -d ' ' -f 2 | xargs basename)
unzip_file "protege/downloads/$REPO_FILE" "EssentialAM/Repository"
echo

echo "3. Extract Viewer data"
VIEWER_FILE=$(cat downloads.txt| grep essential_viewer | cut -d ' ' -f 2 | xargs basename)
unzip_file "viewer/downloads/$VIEWER_FILE" "EssentialAM/essential_viewer"
PUBLISHER_PASSWORD=$(get_or_generate_password "PUBLISHER_PASSWORD")
VIEWER_PWD=$PUBLISHER_PASSWORD
get_or_add_env_var "VIEWER_PWD"
perl -pi -e "s|username=\"publisher\" password=\".*?\"|username=\"publisher\" password=\"$PUBLISHER_PASSWORD\"|g" viewer/tomcat-users.xml
cp viewer/web.xml EssentialAM/essential_viewer/WEB-INF/web.xml
cp viewer/core_header.xsl EssentialAM/essential_viewer/common/core_header.xsl
echo "PUBLISHER_PASSWORD=${PUBLISHER_PASSWORD}"
echo "You'll need this password to update viewer from Protégé or Web Admin"
echo
