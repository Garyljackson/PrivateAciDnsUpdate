resource_suffix=$RANDOM
location=australiaeast
resource_group_name=ExampleResourceGroup$resource_suffix
vnet_name=ExampleVNet$resource_suffix
vnet_cidr=10.0.0.0/16
default_subnet_name=Default
default_subnet_cidr=10.0.1.0/24
aci_subnet_name=ExampleAciSubnet$resource_suffix
aci_subnet_cidr=10.0.2.0/24
aci_container_name=example-container-$resource_suffix
aci_sidecar_image_name=example-sidecar-$resource_suffix
acr_name=ExampleAcr$resource_suffix
dns_zone=private.internal$resource_suffix
dns_a_record=example$resource_suffix
ad_rbac_service_principal=AciAzureCliServicePrincipal$resource_suffix

# Create the resource group
az group create --name $resource_group_name --location $location

# Create a service principle
service_principal=$(az ad sp create-for-rbac \
    --name $ad_rbac_service_principal \
    --role "Private DNS Zone Contributor")

# Extract the details
service_principal_app_id="$(echo $service_principal | jq -r '.appId')"
service_principal_password="$(echo $service_principal | jq -r '.password')"
service_principal_tenant="$(echo $service_principal | jq -r '.tenant')"

# assign the reader role so that it can read the container instance ip address
az role assignment create --assignee $service_principal_app_id --role "Reader"

# Create the virtual network
az network vnet create \
    --name $vnet_name \
    --resource-group $resource_group_name \
    --location $location \
    --address-prefix $vnet_cidr \
    --subnet-name $default_subnet_name \
    --subnet-prefix $default_subnet_cidr

# Create the ACI subnet
az network vnet subnet create \
    --name $aci_subnet_name \
    --resource-group $resource_group_name \
    --vnet-name $vnet_name \
    --address-prefix $aci_subnet_cidr

# Create an azure container registry
az acr create \
    --resource-group $resource_group_name \
    --name $acr_name \
    --sku Basic

# Get the login server for the ACR instance
acr_login_server=$(az acr show \
    --name $acr_name \
    --query loginServer \
    --output tsv)

# Enable admin before you can retrieve the password
az acr update -n $acr_name --admin-enabled true

# Retrieve the credentials for the container registry
acr_credentials=$(az acr credential show --name $acr_name)
acr_username="$(echo $acr_credentials | jq -r '.username')"
acr_password="$(echo $acr_credentials | jq -r '.passwords[0].value')"

# Deploy the image to ACR
az acr build \
    --registry $acr_name \
    --image examples/$aci_sidecar_image_name:latest \
    https://github.com/Garyljackson/PrivateAciDnsUpdate.git

# Create a private dns
az network private-dns zone create \
    --resource-group $resource_group_name \
    --name $dns_zone

# Link the private dns to the virtual network
az network private-dns link vnet create \
    --resource-group $resource_group_name \
    --name $resource_group_name \
    --zone-name $dns_zone \
    --virtual-network $vnet_name \
    --registration-enabled false

# Add an initial placeholder A record
az network private-dns record-set a create \
    --name $dns_a_record \
    --resource-group $resource_group_name \
    --zone-name $dns_zone

# Deploy the ACI instance to the virtual network
az container create \
    --name $aci_container_name \
    --resource-group $resource_group_name \
    --image $acr_login_server/examples/$aci_sidecar_image_name:latest \
    --vnet $vnet_name \
    --subnet $aci_subnet_name \
    --registry-login-server $acr_login_server \
    --registry-username $acr_username \
    --registry-password $acr_password \
    --environment-variables \
    ACI_INSTANCE_NAME=$aci_container_name \
    RESOURCE_GROUP=$resource_group_name \
    A_RECORD_NAME=$dns_a_record \
    DNS_ZONE_NAME=$dns_zone \
    --secure-environment-variables \
    APP_ID=$service_principal_app_id \
    APP_PASSWORD=$service_principal_password \
    APP_TENANT_ID=$service_principal_tenant

# Get the ip address of the container instance
aci_ip=$(az container show \
    --name $aci_container_name \
    --resource-group $resource_group_name \
    --query ipAddress.ip --output tsv)

echo $aci_ip
