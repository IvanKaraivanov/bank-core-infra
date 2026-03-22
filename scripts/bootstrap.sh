#!/bin/bash
RESOURCE_GROUP_NAME="rg-terraform-state-bank"
LOCATION="westeurope"
ACCOUNT_NAME="tfstatebankcoreinfra"

echo "Creating Resource Group: $RESOURCE_GROUP_NAME..."
az group create --name $RESOURCE_GROUP_NAME --location $LOCATION

echo "Creating Storage Account: $ACCOUNT_NAME..."
az storage account create --name $ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME --location $LOCATION --sku Standard_LRS --encryption-services blob

echo "Creating containers (dev, test, prod)..."
az storage container create --name tfstate-dev --account-name $ACCOUNT_NAME
az storage container create --name tfstate-test --account-name $ACCOUNT_NAME
az storage container create --name tfstate-prod --account-name $ACCOUNT_NAME
