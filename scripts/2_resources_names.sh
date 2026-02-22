#!/bin/bash

codename=""

# Get the name of the script
script_name=$(basename "$0")

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo 
    echo "   ###############################################################"
    echo "   # YOU MUST RUN THIS SCRIPT WITH source $script_name!! #"
    echo "   ###############################################################"
    echo 
    exit 1
fi

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --codename) codename="$2"; shift ;; # Set the codename value
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# If codename is empty, call get_nome() to set it
if [[ -z "$codename" ]]; then
    random_word=$(curl -s "https://random-word-api.herokuapp.com/word?number=1")
    word=$(echo $random_word | tr -d '["]')
    codename="essential-$word"
fi

second_part_codename="${codename#*-}"

# Explanation at the beginning of the script
echo
echo "This script will export variables with resource names that will be used"
echo "in the next scripts."
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

if [[ "$answer" =~ ^[Yy]$ ]]; then
    export LOCATION="eastus2"
    export RESOURCE_GROUP="rg-$codename"
    export APP_REGISTRATION=app-$codename
    export STORAGE_ACCOUNT="${second_part_codename:0:18}stg001"
    export CONTAINER_REGISTRY="${second_part_codename:0:18}acr001"
    export APP_SERVICE_PLAN="asp-$codename"
    export WEBAPP=$codename
    export CONTAINER_INSTANCE=protege-$codename

    echo "Floowing resources will be created on Azure in location ${LOCATION}:"
    echo
    echo "       Resource group: ${RESOURCE_GROUP}"
    echo "     App registration: ${APP_REGISTRATION}"
    echo "      Storage account: ${STORAGE_ACCOUNT}"
    echo "   Container registry: ${CONTAINER_REGISTRY}"
    echo "     App Service plan: ${APP_SERVICE_PLAN}"
    echo "App Service / Web App: ${WEBAPP}"
    echo "   Container instance: ${CONTAINER_INSTANCE}"
    echo

fi
