#!/bin/bash

LOG_FILE="execution.log"

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

        # echo
        # echo "Command output:"
        # echo $output
        # echo

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

register_things(){
    az provider register -n Microsoft.Storage --subscription $SUBSCRIPTION_ID
    az provider register -n Microsoft.ContainerRegistry \
        --subscription $SUBSCRIPTION_ID
    az provider register -n microsoft.insights --subscription $SUBSCRIPTION_ID
    az provider register -n Microsoft.ContainerService \
        --subscription $SUBSCRIPTION_ID
}

echo 
echo "Floowing resources will be created on Azure in location ${LOCATION}:"
echo
echo "       Resource group: ${RESOURCE_GROUP}"
echo "     App registration: ${APP_REGISTRATION}"
echo "      Storage account: ${STORAGE_ACCOUNT}"
echo "   Container registry: ${CONTAINER_REGISTRY}"
echo "     App Service plan: ${APP_SERVICE_PLAN}"
echo "App Service / Web App: ${WEBAPP}"
echo
echo "Do you want to proceed? (y/n): "
read answer

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
        register_things
    fi

    OAUTH2_PROXY_AZURE_TENANT=$(get_env_var "OAUTH2_PROXY_AZURE_TENANT")
    if [ -z "$OAUTH2_PROXY_AZURE_TENANT" ]; then
        OAUTH2_PROXY_AZURE_TENANT=$(az account show --query tenantId --output tsv)
        get_or_add_env_var "OAUTH2_PROXY_AZURE_TENANT"
    fi
    
    run_command "az group create --name '$RESOURCE_GROUP' --location '$LOCATION'"
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

    run_command "az storage account create --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --location $LOCATION --sku Standard_LRS"

    STG_ACCESS_KEY=$(get_env_var "STG_ACCESS_KEY")
    if [ -z "$STG_ACCESS_KEY" ]; then
        STG_ACCESS_KEY=$(az storage account keys list --resource-group $RESOURCE_GROUP --account-name $STORAGE_ACCOUNT --query "[0].value" --output tsv)
        get_or_add_env_var "STG_ACCESS_KEY"
    fi
    
    run_command "az storage share-rm create --resource-group $RESOURCE_GROUP --storage-account $STORAGE_ACCOUNT --name essentialviewer"
    run_command "az acr create --resource-group $RESOURCE_GROUP --name $CONTAINER_REGISTRY --sku Basic --location $LOCATION"
    run_command "az acr update -n $CONTAINER_REGISTRY --admin-enabled true"

    # az acr login --name $CONTAINER_REGISTRY
    # docker compose build viewer
    # docker tag viewer $CONTAINER_REGISTRY.azurecr.io/essential-viewer:latest
    # docker push $CONTAINER_REGISTRY.azurecr.io/essential-viewer:latest

    run_command "az appservice plan create --name $APP_SERVICE_PLAN --resource-group $RESOURCE_GROUP --sku P0V3 --location $LOCATION --is-linux"
    run_command "az webapp create --resource-group $RESOURCE_GROUP --plan $APP_SERVICE_PLAN --name $WEBAPP --deployment-container-image-name $CONTAINER_REGISTRY.azurecr.io/essential-viewer:latest"
    # run_command "az webapp config storage-account add --resource-group $RESOURCE_GROUP --name $WEBAPP --custom-id Viewer --storage-type AzureFiles --account-name $STORAGE_ACCOUNT --share-name essentialviewer --access-key $STG_ACCESS_KEY --mount-path /usr/local/tomcat/webapps/essential_viewer"

    HOSTNAME_WEBAPP=$(get_env_var "HOSTNAME_WEBAPP")
    if [ -z "$HOSTNAME_WEBAPP" ]; then
        HOSTNAME_WEBAPP=$(az webapp show --resource-group $RESOURCE_GROUP --name $WEBAPP --query defaultHostName --output tsv)
        get_or_add_env_var "HOSTNAME_WEBAPP"
    fi

    run_command "az ad app update --id $OAUTH2_PROXY_CLIENT_ID --web-redirect-uris 'http://localhost/oauth2/callback' 'https://$HOSTNAME_WEBAPP/oauth2/callback'"

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
    OAUTH2_PROXY_OIDC_ISSUER_URL="https://login.microsoftonline.com/<OAUTH2_PROXY_AZURE_TENANT>/v2.0"
    OAUTH2_PROXY_SCOPE="openid"
    OAUTH2_PROXY_SKIP_AUTH_ROUTES='"GET=^/essential_viewer/reportService,POST=^/essential_viewer/reportService"'
    OAUTH2_PROXY_EMAIL_DOMAINS="*"
    OAUTH2_PROXY_REDIRECT_URL="http://localhost/oauth2/callback"
    OAUTH2_PROXY_PASS_ACCESS_TOKEN="true"
    OAUTH2_PROXY_PROVIDER_DISPLAY_NAME="Azure"
    OAUTH2_PROXY_UPSTREAMS="http://localhost:9090/"


    get_or_add_env_var "OAUTH2_PROXY_UPSTREAMS"
    get_or_add_env_var "OAUTH2_PROXY_PROVIDER_DISPLAY_NAME"
    get_or_add_env_var "OAUTH2_PROXY_PROVIDER"
    get_or_add_env_var "OAUTH2_PROXY_OIDC_ISSUER_URL"
    get_or_add_env_var "OAUTH2_PROXY_SCOPE"
    get_or_add_env_var "OAUTH2_PROXY_PASS_ACCESS_TOKEN"
    get_or_add_env_var "OAUTH2_PROXY_EMAIL_DOMAINS"
    get_or_add_env_var "OAUTH2_PROXY_REDIRECT_URL"
    get_or_add_env_var "OAUTH2_PROXY_SKIP_AUTH_ROUTES"

    run_command "az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $WEBAPP --settings OAUTH2_PROXY_UPSTREAMS=$OAUTH2_PROXY_UPSTREAMS"
    run_command "az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $WEBAPP --settings OAUTH2_PROXY_PROVIDER_DISPLAY_NAME=$OAUTH2_PROXY_PROVIDER_DISPLAY_NAME"
    run_command "az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $WEBAPP --settings OAUTH2_PROXY_PROVIDER=$OAUTH2_PROXY_PROVIDER"
    run_command "az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $WEBAPP --settings OAUTH2_PROXY_CLIENT_ID=$OAUTH2_PROXY_CLIENT_ID"
    run_command "az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $WEBAPP --settings OAUTH2_PROXY_CLIENT_SECRET=$OAUTH2_PROXY_CLIENT_SECRET"
    run_command "az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $WEBAPP --settings OAUTH2_PROXY_AZURE_TENANT=$OAUTH2_PROXY_AZURE_TENANT"
    run_command "az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $WEBAPP --settings OAUTH2_PROXY_OIDC_ISSUER_URL=$OAUTH2_PROXY_OIDC_ISSUER_URL"
    run_command "az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $WEBAPP --settings OAUTH2_PROXY_SCOPE=$OAUTH2_PROXY_SCOPE"
    run_command "az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $WEBAPP --settings OAUTH2_PROXY_PASS_ACCESS_TOKEN=$OAUTH2_PROXY_PASS_ACCESS_TOKEN"
    run_command "az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $WEBAPP --settings OAUTH2_PROXY_EMAIL_DOMAINS=$OAUTH2_PROXY_EMAIL_DOMAINS"
    run_command "az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $WEBAPP --settings OAUTH2_PROXY_REDIRECT_URL=https://$HOSTNAME_WEBAPP/oauth2/callback"
    run_command "az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $WEBAPP --settings OAUTH2_PROXY_COOKIE_SECRET=$OAUTH2_PROXY_COOKIE_SECRET"
    run_command "az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $WEBAPP --settings OAUTH2_PROXY_SKIP_AUTH_ROUTES=$OAUTH2_PROXY_SKIP_AUTH_ROUTES"
    run_command "az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $WEBAPP --settings WEBSITES_CONTAINER_START_TIME_LIMIT=600"
    run_command "az webapp restart --resource-group $RESOURCE_GROUP --name $WEBAPP"
fi

