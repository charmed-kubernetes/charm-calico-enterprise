#!/bin/bash

function install_tools() {
    sudo snap install terraform --channel=latest/stable --classic
    sudo snap install yq --classic
}

function generate_ssh_keys() {
    ssh-keygen -b 2048 -t rsa -N "" -f ${HOME}/.ssh/id_rsa
    PRIVATE_KEY=${HOME}/.ssh/id_rsa
    PUBLIC_KEY=${HOME}/.ssh/id_rsa.pub

    echo "PRIVATE_KEY"="${PRIVATE_KEY}" >> "$GITHUB_ENV"
    echo "PUBLIC_KEY"="${PUBLIC_KEY}" >> "$GITHUB_ENV"
}

function apply_cloud_credentials() {
    CLOUD_CREDS=${HOME}/cloud-creds
    CREDENTIALS_YAML=$CLOUD_CREDS/credentials.yaml
    CLOUDS_YAML=$CLOUD_CREDS/clouds.yaml
    TF_SECRETS=$CLOUD_CREDS/tf_secrets.sh
    mkdir -p $CLOUD_CREDS
    if [ -z "$CREDENTIALS_YAML_CONTENT" ]; then
    >&2 echo "No cloud credentials available"
    exit -1
    fi
    if [ -z "$CLOUDS_YAML_CONTENT" ]; then
    >&2 echo "No cloud yaml available"
    exit -1
    fi

    echo "${CREDENTIALS_YAML_CONTENT}" | base64 -d > $CREDENTIALS_YAML
    echo "${CLOUDS_YAML_CONTENT}" | base64 -d > $CLOUDS_YAML
    VSPHERE_USER=$(cat $CREDENTIALS_YAML | yq -r .credentials.vsphere.vsphere-ci.user)
    VSPHERE_ENDPOINT=$(cat $CLOUDS_YAML | yq -r .clouds.vsphere.endpoint)
    VSPHERE_PASS=$(cat $CREDENTIALS_YAML | yq -r .credentials.vsphere.vsphere-ci.password)
    VSPHERE_FOLDER=$(cat $CREDENTIALS_YAML | yq -r .credentials.vsphere.vsphere-ci.vmfolder)
    VSPHERE_FOLDER="${VSPHERE_FOLDER}/Calico Enterprise ($GITHUB_SHA)"

    if [ "$VSPHERE_ENDPOINT" == "null" ]; then
    >&2 echo "No vsphere endpoint detected"
    exit -1
    fi
    if [ "$VSPHERE_USER" == "null" ]; then
    >&2 echo "No vsphere user detected"
    exit -1
    fi
    if [ "$VSPHERE_PASS" == "null" ]; then
    >&2 echo "No vsphere password detected"
    exit -1
    fi

    cp .github/data/proxy_config.yaml $CLOUD_CREDS/proxy_config.yaml

    echo "VSPHERE_FOLDER"="$VSPHERE_FOLDER" >> "$GITHUB_ENV"
    echo "TF_SECRETS"="$TF_SECRETS" >> "$GITHUB_ENV"
    echo "MODEL_CONFIG"="$CLOUD_CREDS/proxy_config.yaml" >> "$GITHUB_ENV"
    echo "TF_VAR_vsphere_server"="$VSPHERE_ENDPOINT" >> $TF_SECRETS
    echo "TF_VAR_vsphere_user"="$VSPHERE_USER" >> $TF_SECRETS
    echo "TF_VAR_vsphere_password"="$VSPHERE_PASS" >> $TF_SECRETS
    echo "TF_VAR_tigera_registry_secret"="$CHARM_TIGERA_EE_REG_SECRET" >> $TF_SECRETS
}

function terraform_cloud() {
    set -a
    source "${TF_SECRETS}"
    set +a
    terraform -chdir=tests/testing-environment/vmware init
    terraform -chdir=tests/testing-environment/vmware apply \
    -var="vsphere_folder=${VSPHERE_FOLDER}" \
    -var="juju_authorized_key=$(cat ${PUBLIC_KEY})" \
    -auto-approve
    TOR1_IP=$(terraform -chdir=tests/testing-environment/vmware output -json | yq '.tor1.value')
    TOR2_IP=$(terraform -chdir=tests/testing-environment/vmware output -json | yq '.tor2.value')
    K8S_IPS=$(terraform -chdir=tests/testing-environment/vmware output -json | yq '.k8s_addresses.value | to_entries | .[].value')
    CONTROLLER_IP=$(terraform -chdir=tests/testing-environment/vmware output -json | yq '.controller.value')
    MANUAL_CLOUD_YAML=$(cat << EOF | base64 -w0
clouds:
    manual-cloud:
        type: manual
        endpoint: ubuntu@${CONTROLLER_IP}
EOF
)
    echo ---manual-cloud---
    echo ${MANUAL_CLOUD_YAML} | base64 -d
    echo ------------------

    ssh ubuntu@$CONTROLLER_IP -o "StrictHostKeyChecking no" -- 'cloud-init status --wait'

    echo "TOR1_IP"="$TOR1_IP" >> "$GITHUB_ENV"
    echo "TOR2_IP"="$TOR2_IP" >> "$GITHUB_ENV"
    echo "K8S_IPS"=${K8S_IPS//$'\n'/,} >> "$GITHUB_ENV"        # replace all newlines with commas
    echo "CONTROLLER_IP"="$CONTROLLER_IP" >> "$GITHUB_ENV"
    echo "MANUAL_CLOUD_YAML"="$MANUAL_CLOUD_YAML" >> "$GITHUB_ENV"
}

function juju_create_manual_model() {
    juju add-model ${JUJU_MODEL} --config="${MODEL_CONFIG}"
    juju add-space bgp
    juju add-space mgmt
    juju add-space tor-network
    juju model-config default-space=mgmt
    for addr in ${K8S_IPS//,/ }; do
        echo "Enlisting machine at $addr"
        ssh ubuntu@$addr -o "StrictHostKeyChecking no" -- 'hostname; cloud-init status --wait'
        juju add-machine ssh:ubuntu@$addr
    done
    juju wait-for model ${JUJU_MODEL} --query='forEach(machines, mac => mac.status == "started")' --timeout=5m
    juju move-to-space mgmt 10.246.153.0/24
    juju move-to-space tor-network 10.246.154.0/24 10.246.155.0/24
    juju move-to-space bgp 10.30.30.12/32 10.30.30.13/32 10.30.30.14/32 10.30.30.15/32 10.30.30.16/32
}

function juju_status() {
    juju spaces 2>&1 | tee tmp/juju-spaces.txt
    juju status 2>&1 | tee tmp/juju-status.txt
    juju-crashdump -s -m controller -a debug-layer -a config -o tmp/
    mv juju-crashdump-* tmp/ | true
}

function terraform_teardown() {
    set -a
    source "${TF_SECRETS}"
    set +a
    terraform -chdir=tests/testing-environment/vmware destroy \
    -var="vsphere_folder=${VSPHERE_FOLDER}" \
    -var="juju_authorized_key=$(cat ${PUBLIC_KEY})" \
    -auto-approve

    # Prevent the actions-operator from trying to clean up the controller
    echo "CONTROLLER_NAME"="" >> "$GITHUB_ENV"
}

function test_method() {
    echo last call - \'test_method ${TEST_METHOD_LAST_ARGS}\'
    echo this call - \'test_method $@\'
    echo "TEST_METHOD_LAST_ARGS"=\"$@\" >> "$GITHUB_ENV"
}

# Call a bash function with the remaining arguments
if [ -z ${GITHUB_ENV+x} ]; then
    # Not under a github env, create a mock env file
    GITHUB_ENV=.integration_local_env
    touch $GITHUB_ENV
    set -a
    . $GITHUB_ENV
    set +a
fi

$1 "${@:2}"