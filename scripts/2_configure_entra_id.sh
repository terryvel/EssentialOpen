#!/bin/bash

codename=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --codename) codename="$2"; shift ;; # Set the codename value
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# If codename is empty, generate a random one
if [[ -z "$codename" ]]; then
    word=$(openssl rand -hex 4 2>/dev/null || echo $RANDOM$RANDOM)
    codename="essential-$word"
fi

# Explanation at the beginning of the script
echo
echo "This script will create App registration on Azure Entra ID"
echo "You can pass an argument to define the codename"
echo "like: source $script_name --codename <name>."
echo "sample: source scripts/2_resources_names.sh --codename essential-witchweeds"
echo "If no argument is passed, a suggestion of codename will be generated."
echo "If you continue now your project codename will be:" 
echo 
echo "--> $codename"
echo
echo "All resources in Azure will be created based on this codename."
echo
echo "Do you want to proceed? (y/n): "
read answer

LOG_FILE="execution.log"
APP_REGISTRATION=app-$codename

# Function to display error messages
function error_exit {
    echo "$1" 1>&2
    exit 1
}

# Function to check if the command has already been logged as successfully executed
check_log() {
    local command="$1"
    grep -Fxq "$command" "$LOG_FILE" 2>/dev/null
}

# Function to log the command after successful execution
log_command() {
    local command="$1"
    echo "$command" >> "$LOG_FILE"
}


# Function to validate the command output
# Function to validate the provisioningState and appId in the JSON output
validate_output() {
    local output="$1"
    local provisioningState1
    local provisioningState2
    local appId
    local ID
    local stgOk
    local required_names=("OAUTH2_PROXY_UPSTREAMS" \
        "OAUTH2_PROXY_PROVIDER_DISPLAY_NAME" "OAUTH2_PROXY_PROVIDER" \
        "OAUTH2_PROXY_CLIENT_ID" "OAUTH2_PROXY_CLIENT_SECRET" \
        "OAUTH2_PROXY_AZURE_TENANT" "OAUTH2_PROXY_OIDC_ISSUER_URL" \
        "OAUTH2_PROXY_PASS_ACCESS_TOKEN" "OAUTH2_PROXY_EMAIL_DOMAINS" \
        "OAUTH2_PROXY_REDIRECT_URL" "OAUTH2_PROXY_COOKIE_SECRET" \
        "OAUTH2_PROXY_SKIP_AUTH_ROUTES", "WEBSITES_CONTAINER_START_TIME_LIMIT")
    if echo "$output" | jq -e 'type == "object"' > /dev/null; then
        provisioningState1=$(echo "$output" | jq -r '.properties.provisioningState // empty')
        appId=$(echo "$output" | jq -r '.appId // empty')
        provisioningState2=$(echo "$output" | jq -r '.provisioningState // empty')
        ID=$(echo "$output" | jq -r '.id // empty')
        # Safer check for .state in nested objects or top level
        stgOk=$(echo "$output" | jq -r 'if type == "object" then (.state // (.[ ] | select(type == "object")? | .state?) // empty) else empty end' 2>/dev/null | head -n 1)
    elif echo "$output" | jq -e 'type == "array"' > /dev/null; then
        for name in "${required_names[@]}"; do
            if echo "$output" | jq -e --arg name "$name" '.[] | select(.name == $name)' > /dev/null; then
                return 0  # Success
            fi
        done
    else
        return 1  # Failure
    fi

    if [[ "$provisioningState1" == "Succeeded" ]]; then
        return 0  # Success
    elif [[ -n "$appId" && "$appId" != "null" ]]; then
        return 0  # Success
    elif [[ "$provisioningState2" == "Succeeded" ]]; then
        return 0  # Success
    elif [[ "$ID" != "null" ]]; then
        return 0  # Success
    elif [[ "$stgOk" == "Okx" ]]; then
        return 0  # Success
    elif [[ "$oauth2ProxyUpstreams" == "OAUTH2_PROXY_UPSTREAMS" ]]; then
        return 0  # Success
    elif [[ "$oauth2ProxyProviderDisplayName" == "OAUTH2_PROXY_PROVIDER_DISPLAY_NAME" ]]; then
        return 0  # Success
    else
        return 1  # Failure
    fi
}

# Function to execute the command, evaluate the output, and determine success
run_command() {
    local command="$1"
    
    if check_log "$command"; then
        echo "Skipping '$command'"
    else
        echo "Executing: $command"
        local output
        output=$(eval "$command" 2>/dev/null)  # Capture command output (stdout and stderr)

        if validate_output "$output"; then
            echo "Command '$command' validated successfully!"
            log_command "$command"
        else
            echo "Failed to execute: $command"
            exit 1
        fi
    fi
}

get_env_var(){
    local key=$1
    local file="env_file.env"
    local value=${!key}

    if [ ! -f "$file" ]; then
        touch "$file"
    fi

    if grep -q "^${key}=" "$file"; then
        current_value=$(awk -F'=' -v key="$key" '$1 == key {print substr($0, index($0,$2))}' "$file")
        echo $current_value
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
            perl -i -pe "s|^${key}=.*|${key}=${value}|" "$file"
        fi
    else
        echo "${key}=${!key}" >> "$file"
    fi
}


if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "Proceeding with the deployment..."
    # Check if az CLI is installed
    if ! command -v az &> /dev/null
    then
        echo "Azure CLI is not installed. Please install it to proceed."
        exit 1
    fi

    SUBSCRIPTION_ID=$(get_env_var "SUBSCRIPTION_ID")
    if [ -z "$SUBSCRIPTION_ID" ]; then
        az login
        SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        get_or_add_env_var "SUBSCRIPTION_ID"
    fi

    OAUTH2_PROXY_AZURE_TENANT=$(get_env_var "OAUTH2_PROXY_AZURE_TENANT")
    if [ -z "$OAUTH2_PROXY_AZURE_TENANT" ]; then
        OAUTH2_PROXY_AZURE_TENANT=$(az account show --query tenantId --output tsv)
        get_or_add_env_var "OAUTH2_PROXY_AZURE_TENANT"
    fi
    
    run_command "az ad app create --display-name $APP_REGISTRATION"

    OAUTH2_PROXY_CLIENT_ID=$(get_env_var "OAUTH2_PROXY_CLIENT_ID")
    if [ -z "$OAUTH2_PROXY_CLIENT_ID" ]; then
        OAUTH2_PROXY_CLIENT_ID=$(az ad app list --display-name $APP_REGISTRATION --query "[0].appId" --output tsv)
        get_or_add_env_var "OAUTH2_PROXY_CLIENT_ID"
    fi

    OAUTH2_PROXY_CLIENT_SECRET=$(get_env_var "OAUTH2_PROXY_CLIENT_SECRET")
    if [ -z "$OAUTH2_PROXY_CLIENT_SECRET" ]; then
        OAUTH2_PROXY_CLIENT_SECRET=$(az ad app credential reset --id $OAUTH2_PROXY_CLIENT_ID --query password --output tsv)
        get_or_add_env_var "OAUTH2_PROXY_CLIENT_SECRET"
    fi

    COMMAND_AD_UPDATE="az ad app update --id $OAUTH2_PROXY_CLIENT_ID --web-redirect-uris 'http://localhost/oauth2/callback'"
    if check_log "$COMMAND_AD_UPDATE"; then
        echo "Skipping '$COMMAND_AD_UPDATE'"
    else
        echo "Executing: $COMMAND_AD_UPDATE"
        eval "$COMMAND_AD_UPDATE"
        if [ $? -eq 0 ]; then
            echo "Command '$COMMAND_AD_UPDATE' executed successfully!"
            log_command "$COMMAND_AD_UPDATE"
        else
            echo "Failed to execute: $COMMAND_AD_UPDATE"
            exit 1
        fi
    fi

    OAUTH2_PROXY_COOKIE_SECRET=$(get_env_var "OAUTH2_PROXY_COOKIE_SECRET")
    if [ -z "$OAUTH2_PROXY_COOKIE_SECRET" ]; then
        OAUTH2_PROXY_COOKIE_SECRET=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 | tr -d -- '\n' | tr -- '+/' '-_')
        get_or_add_env_var "OAUTH2_PROXY_COOKIE_SECRET"
    fi

    # OAUTH2_PROXY_UPSTREAMS="http://localhost:9090/"
    # OAUTH2_PROXY_PROVIDER_DISPLAY_NAME="Azure"
    # OAUTH2_PROXY_PROVIDER="oidc"
    # OAUTH2_PROXY_OIDC_ISSUER_URL="https://login.microsoftonline.com/${OAUTH2_PROXY_AZURE_TENANT}/v2.0"
    # OAUTH2_PROXY_PASS_ACCESS_TOKEN="true"
    # OAUTH2_PROXY_EMAIL_DOMAINS="*"
    # OAUTH2_PROXY_REDIRECT_URL="http://localhost/oauth2/callback"
    # OAUTH2_PROXY_SKIP_AUTH_ROUTES='"GET=^/essential_viewer/reportService,POST=^/essential_viewer/reportService"'

    OAUTH2_PROXY_PROVIDER="entra-id"
    OAUTH2_PROXY_OIDC_ISSUER_URL="https://login.microsoftonline.com/${OAUTH2_PROXY_AZURE_TENANT}/v2.0"
    OAUTH2_PROXY_SCOPE="openid profile email"
    OAUTH2_PROXY_OIDC_EMAIL_CLAIM=preferred_username
    OAUTH2_PROXY_USER_ID_CLAIM=preferred_username
    OAUTH2_PROXY_INSECURE_OIDC_ALLOW_UNVERIFIED_EMAIL="true"
    OAUTH2_PROXY_SET_XAUTHREQUEST="true"
    OAUTH2_PROXY_PASS_USER_HEADERS="true"
    OAUTH2_PROXY_SKIP_AUTH_ROUTES='"GET=^/essential_viewer/reportService,POST=^/essential_viewer/reportService"'
    OAUTH2_PROXY_EMAIL_DOMAINS="*"
    OAUTH2_PROXY_REDIRECT_URL="http://localhost/oauth2/callback"
    OAUTH2_PROXY_PASS_ACCESS_TOKEN="true"
    OAUTH2_PROXY_PROVIDER_DISPLAY_NAME="Microsoft Entra ID"
    OAUTH2_PROXY_UPSTREAMS="http://localhost:80/"
    OAUTH2_PROXY_HTTP_ADDRESS="0.0.0.0:4180"
    OAUTH2_PROXY_CUSTOM_SIGN_IN_LOGO="https://raw.githubusercontent.com/terryvel/essential-open-admin/refs/heads/main/public/the-essential-project.png"


    get_or_add_env_var "OAUTH2_PROXY_UPSTREAMS"
    get_or_add_env_var "OAUTH2_PROXY_PROVIDER_DISPLAY_NAME"
    get_or_add_env_var "OAUTH2_PROXY_PROVIDER"
    get_or_add_env_var "OAUTH2_PROXY_OIDC_ISSUER_URL"
    get_or_add_env_var "OAUTH2_PROXY_SCOPE"
    get_or_add_env_var "OAUTH2_PROXY_PASS_ACCESS_TOKEN"
    get_or_add_env_var "OAUTH2_PROXY_EMAIL_DOMAINS"
    get_or_add_env_var "OAUTH2_PROXY_REDIRECT_URL"
    get_or_add_env_var "OAUTH2_PROXY_SKIP_AUTH_ROUTES"
    get_or_add_env_var "OAUTH2_PROXY_HTTP_ADDRESS"
    get_or_add_env_var "OAUTH2_PROXY_OIDC_EMAIL_CLAIM"
    get_or_add_env_var "OAUTH2_PROXY_USER_ID_CLAIM"
    get_or_add_env_var "OAUTH2_PROXY_INSECURE_OIDC_ALLOW_UNVERIFIED_EMAIL"
    get_or_add_env_var "OAUTH2_PROXY_SET_XAUTHREQUEST"
    get_or_add_env_var "OAUTH2_PROXY_PASS_USER_HEADERS"
    get_or_add_env_var "OAUTH2_PROXY_CUSTOM_SIGN_IN_LOGO"

fi

