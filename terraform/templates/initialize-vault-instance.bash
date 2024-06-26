#!/bin/bash -l

set -euxo pipefail

sudo systemctl start vault
sudo systemctl status vault --no-pager 

export VAULT_ADDR="http://127.0.0.1:8200"

# Sleep 10 seconds to avoid race condition with Vault startup
sleep 10

# Unseal Vault 
vault operator init \
  -format=json \
  -key-shares=1 \
  -key-threshold=1 \
  > /home/vadmin/vault-unseal.json

export VAULT_UNSEAL=$(cat /home/vadmin/vault-unseal.json | jq -r '.unseal_keys_b64[0]')
export VAULT_TOKEN=$(cat /home/vadmin/vault-unseal.json | jq -r '.root_token')

echo "export VAULT_TOKEN=$VAULT_TOKEN" >> /home/vadmin/.bashrc

vault operator unseal $VAULT_UNSEAL

# Sleep 10 seconds to avoid race condition with Vault unseal due to Raft writing to disk
sleep 10

vault login $VAULT_TOKEN

cd /home/vadmin
vault secrets enable -path=vault-admin -version=2 kv
# Sleep 10 seconds to avoid race condition with Vault unseal due to Raft writing to disk
sleep 10
vault kv put vault-admin/vault-unseal @vault-unseal.json

vault policy write admins - <<EOF
path "*" { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
EOF


vault auth enable userpass
vault write auth/userpass/users/admin \
    password=correct-horse-battery-staple \
    policies=admins

%{ if namespace != "" ~}
vault namespace create ${namespace}
export VAULT_NAMESPACE=${namespace}
%{~ endif }

vault auth enable approle
vault write auth/approle/role/tde-role \
  token_ttl=15m max_token_ttl=30m token_policies=tde-policy

vault secrets enable transit
vault write -f transit/keys/ekm-encryption-key type=rsa-2048

vault policy write tde-policy - <<EOF
path "transit/keys/ekm-encryption-key" { capabilities = ["create", "read", "update", "delete"] }
path "transit/keys" { capabilities = ["list"] }
path "transit/encrypt/ekm-encryption-key" { capabilities = ["update"] }
path "transit/decrypt/ekm-encryption-key" { capabilities = ["update"] }
path "sys/license/status" { capabilities = ["read"] }
EOF


exit