#!/usr/bin/env bash

# shellcheck disable=SC1091
# loading script modules into current shell
source "$SHARED_MODULE_DIR/config-module.sh"
source "$SHARED_MODULE_DIR/resource-module.sh"
source "$SHARED_MODULE_DIR/log-module.sh"

function certificate-exist() {
    local key_name="$1"

    key_vault_name="$(get-value ".deployment.keyVault.name")"

    state="$(
        az keyvault certificate list \
            --vault-name "${key_vault_name}" \
            --include-pending \
            --query \
            "[?name=='${key_name}'] \
            .{Name:name} \
            | [0]" \
            --output tsv ||
            false
        return
    )"

    if [[ "${state}" = "${key_name}" ]]; then
        true
        return
    else
        false
        return
    fi
}

function secret-exist() {
    local key_name="$1"
    local key_vault_name="$2"

    count="$(
        az keyvault secret list \
            --vault-name "${key_vault_name}" \
            --query \
            "[?name=='${key_name}']" |
            jq '. | length' ||
            false
        return
    )"

    if [[ "${count}" -gt 0 ]]; then
        true
        return
    else
        false
        return
    fi
}

function create-key-vault() {
    local key_vault_name="$1"
    local resource_group="$2"
    local key_vault_type_name="Microsoft.KeyVault/vaults"

    echo "Checking if the Key Vault have already been successfully created..." |
        log-output \
            --level info

    if ! resource-exist "${key_vault_type_name}" "${key_vault_name}"; then

        echo "No Key Vault found." |
            log-output \
                --level info

        echo "Deploying Key Vault using bicep..." |
            log-output \
                --level info

        user_principal_id="$(get-value ".initConfig.userPrincipalId")"

        az deployment group create \
            --resource-group "${resource_group}" \
            --name "KeyVaultDeployment" \
            --template-file "${BICEP_DIR}/deployKeyVault.bicep" \
            --parameters \
            keyVaultName="${key_vault_name}" \
            userObjectId="${user_principal_id}" |
            log-output \
                --level info ||
            echo "Failed to deploy Key Vault" |
            log-output \
                --level error \
                --header "Critical Error" ||
            exit 1

        echo "Key Vault Provisining successfully." |
            log-output \
                --level success
    else
        echo "Existing Key Vault found." |
            log-output \
                --level success
    fi
}

function create-key-vault-cli() {
    local key_vault_name="$1"
    local resource_group="$2"
    local key_vault_type_name="Microsoft.KeyVault/vaults"

    echo "Checking if the Key Vault have already been successfully created..." |
        log-output \
            --level info

    # Get location value early
    location="$(get-value ".initConfig.location")"

    # Always try to purge any existing deleted Key Vault first
    echo "Checking for any existing deleted Key Vault that needs purging..." |
        log-output \
            --level info
    
    az keyvault purge --name "${key_vault_name}" --location "${location}" 2>/dev/null || true
    
    if ! resource-exist "${key_vault_type_name}" "${key_vault_name}"; then
        echo "No Key Vault found." |
            log-output \
                --level info
    else
        echo "Existing Key Vault found. Checking if it has RBAC enabled..." |
            log-output \
                --level info

        # Check if the Key Vault has RBAC enabled
        rbac_enabled=$(az keyvault show --name "${key_vault_name}" --resource-group "${resource_group}" --query "properties.enableRbacAuthorization" -o tsv 2>/dev/null || echo "true")
        
        if [[ "${rbac_enabled}" == "true" ]]; then
            echo "Existing Key Vault has RBAC enabled. Deleting and recreating with access policies..." |
                log-output \
                    --level info
            
            az keyvault delete --name "${key_vault_name}" --resource-group "${resource_group}" |
                log-output \
                    --level info
            
            echo "Waiting for Key Vault deletion to complete..." |
                log-output \
                    --level info
            
            sleep 30
            
            echo "Purging deleted Key Vault..." |
                log-output \
                    --level info
            
            az keyvault purge --name "${key_vault_name}" --location "${location}" |
                log-output \
                    --level info
            
            echo "Waiting for Key Vault purge to complete..." |
                log-output \
                    --level info
            
            sleep 30
        else
            echo "Existing Key Vault uses access policies. Continuing..." |
                log-output \
                    --level success
            return
        fi
    fi

    echo "Deploying Key Vault using Azure CLI..." |
        log-output \
            --level info

    user_principal_id="$(get-value ".initConfig.userPrincipalId")"

    # Create Key Vault using Azure CLI with access policies (not RBAC)
    az keyvault create \
        --name "${key_vault_name}" \
        --resource-group "${resource_group}" \
        --location "${location}" \
        --enabled-for-deployment \
        --enabled-for-disk-encryption \
        --enabled-for-template-deployment \
        --enable-rbac-authorization false |
        log-output \
            --level info ||
        echo "Failed to create Key Vault" |
        log-output \
            --level error \
            --header "Critical Error" ||
        exit 1

    # Set access policy for the user
    az keyvault set-policy \
        --name "${key_vault_name}" \
        --resource-group "${resource_group}" \
        --object-id "${user_principal_id}" \
        --secret-permissions get list set delete \
        --certificate-permissions get list create delete |
        log-output \
            --level info ||
        echo "Warning: Failed to set access policy for Key Vault. This may be due to insufficient permissions." |
        log-output \
            --level warning \
            --header "Permission Warning"

    echo "Key Vault Provisioning successfully." |
        log-output \
            --level success
}

function init-key-vault-certificate-template() {
    local b2c_name="$1"

    # getting default certificate policy and saving it to json file
    az keyvault certificate get-default-policy \
        >"${CERTIFICATE_POLICY_FILE}" ||
        echo "Failed to get default certificate policy." |
        log-output \
            --level error \
            --header "Critical Error" ||
        exit 1

    # patching certificate policy to our liking, including making the certs none-exportable
    put-certificate-value '.keyProperties.exportable' "true"
    put-certificate-value '.keyProperties.keySize' "2048"
    put-certificate-value '.x509CertificateProperties.subject' "CN=${b2c_name}"
}

function create-certificate-in-vault() {
    local cert_name="$1"
    local key_vault_name="$2"
    local output_dir="$3"

    # check if certificate doesn't not exist and create it if not
    if ! certificate-exist "${cert_name}"; then
        echo "Creating a self-signing certificate called '${cert_name}'..." | log-output

        az keyvault certificate create \
            --name "${cert_name}" \
            --vault-name "${key_vault_name}" \
            --policy "@${CERTIFICATE_POLICY_FILE}" 1>/dev/null ||
            echo "Failed to create self-signing certificate for ${cert_name}." |
            log-output \
                --level error \
                --header "Critical Error" ||
            exit 1
    else
        echo "A self-signing certificate for ${cert_name} already exist and will be used." |
            log-output \
                --level success
    fi

    echo "${cert_name}"

    return
}

function get-certificate-public-key() {
    local key_name="$1"
    local key_vault_name="$2"
    local output_dir="$3"

    # check if output_dir is provided and not empty
    if [[ -z "${output_dir}" || "${output_dir}" == "null" ]]; then
        echo "Error: Output directory is not specified for certificate ${key_name}" |
            log-output \
                --level error \
                --header "Critical Error" ||
            exit 1
    fi

    # check if certificate already exist in and if so delete it
    if [[ -f "${output_dir}/${key_name}.crt" ]]; then
        sudo rm -f "${output_dir}/${key_name}"
    fi

    mkdir -p "${output_dir}"

    local download_path="${output_dir}/${key_name}.crt"

    echo "Downloading self-signing public key certificate for ${key_name}..." |
        log-output \
            --level info

    az keyvault certificate download \
        --name "${key_name}" \
        --vault-name "${key_vault_name}" \
        --encoding "PEM" \
        --file "${download_path}" \
        >/dev/null ||
        echo "Failed to download self-signing public key certificate for ${key_name}: $?" |
        log-output \
            --level error \
            --header "Critical Error" ||
        exit 1

    echo "${download_path}"
    return
}

function add-a-secret-to-vault() {
    local key_name="$1"
    local key_vault_name="$2"
    local output_path="$3"

    # check if output_path is provided and not empty
    if [[ -z "${output_path}" || "${output_path}" == "null" ]]; then
        echo "Error: Output path is not specified for secret ${key_name}" |
            log-output \
                --level error \
                --header "Critical Error" ||
            exit 1
    fi

    if secret-exist "${key_name}" "${key_vault_name}"; then

        echo "Downloading secret for ${key_name}..." |
            log-output \
                --level info

        secret="$(az keyvault secret show \
            --vault-name "${key_vault_name}" \
            --name "${key_name}" \
            --query "value" \
            --output tsv ||
            echo "Failed to download secret for ${key_name}: $?" |
            log-output \
                --level error \
                --header "Critical Error" ||
            exit 1)"
    else
        secret="$(openssl rand -base64 26)"

        echo "Uploading new secret for ${key_name}..." | log-output --level info

        az keyvault secret set \
            --name "${key_name}" \
            --vault-name "${key_vault_name}" \
            --value "${secret}" \
            >/dev/null ||
            echo "Failed to set new secret for ${key_name}: $?" |
            log-output \
                --level error \
                --header "Critical Error" ||
            exit 1
    fi

    mkdir -p "${output_path}"

    secret_path="${output_path}/${key_name}.secret"

    # write secret to file in user home directory
    echo "${secret}" | tee "${secret_path}" >/dev/null ||
        echo "Failed to write secret to file: $?" |
        log-output \
            --level error \
            --header "Critical Error" ||
        exit 1

    echo "${secret_path}"
    return
}
