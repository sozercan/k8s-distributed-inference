Deploying AKS with GPU operator

```bash
az group create \
    --name "${AZURE_RESOURCE_GROUP}" \
    --location "${AZURE_REGION}"

az aks create \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --location "${AZURE_REGION}" \
    --node-count 1 \
    --ssh-key-value "${SSH_KEY}" \
    --admin-username "${AKS_WORKER_USER_NAME}" \
    --enable-oidc-issuer \
    --enable-workload-identity

az aks nodepool add \
    --name mignode \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --cluster-name "${CLUSTER_NAME}" \
    --node-count 1 \
    --node-vm-size "${GPU_NODE_SIZE}" \
    --skip-gpu-driver-install

az aks get-credentials \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}"

# ---------------------------------------------------------

mkdir -p artifacts
pushd artifacts
curl -LO https://github.com/prometheus-operator/kube-prometheus/archive/main.zip
unzip main.zip

pushd kube-prometheus-main
# Create the namespace and CRDs, and then wait for them to be available before creating the remaining resources
kubectl create -f manifests/setup

# Wait until the "servicemonitors" CRD is created. The message "No resources found" means success in this context.
until kubectl get servicemonitors --all-namespaces; do
    date
    sleep 1
    echo ""
done

kubectl create -f manifests/
popd
popd

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-service-list-role
rules:
- apiGroups: [""]
  resources: ["services", "endpoints", "pods"]
  verbs: ["list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-service-list-binding
subjects:
- kind: ServiceAccount
  name: prometheus-k8s
  namespace: monitoring
roleRef:
  kind: ClusterRole
  name: prometheus-service-list-role
  apiGroup: rbac.authorization.k8s.io
EOF

# ---------------------------------------------------------

kubectl create ns gpu-operator
kubectl label --overwrite ns gpu-operator pod-security.kubernetes.io/enforce=privileged

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia &&
    helm repo update

helm install --wait --generate-name \
    -n gpu-operator --create-namespace \
    nvidia/gpu-operator \
    --set mig.strategy=single \
    --set "migManager.env[0].name=WITH_REBOOT" \
    --set-string "migManager.env[0].value=true" \
    --set dcgmExporter.serviceMonitor.enabled="true"

# ---------------------------------------------------------
kubectl patch clusterpolicies.nvidia.com/cluster-policy \
    --type='json' \
    -p='[{"op":"replace", "path":"/spec/mig/strategy", "value":"single"}]'

kubectl label $(kubectl get nodes -l agentpool=mignode -o name) nvidia.com/mig.config=all-1g.10gb --overwrite
kubectl logs -n gpu-operator -l app=nvidia-mig-manager -c nvidia-mig-manager
kubectl get nodes -l agentpool=mignode -o jsonpath='{range .items[*]}{.metadata.name}: nvidia.com/mig.config={.metadata.labels.nvidia\.com/mig\.config} nvidia.com/mig.config.state={.metadata.labels.nvidia\.com/mig\.config\.state}{"\n"}{end}'

kubectl exec -it -n gpu-operator ds/nvidia-driver-daemonset -- nvidia-smi -L

# ---------------------------------------------------------

curl http://localhost:8080/v1/chat/completions \
    -H "Content-Type: application/json" -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "whats the meaning of life? explain in 5000 chars"}]
  }'

# Stress testing the model
counter=0
while true; do
    counter=$((counter + 1))
    echo "No of process: $counter"
    curl http://localai:8080/v1/chat/completions \
        -H "Content-Type: application/json" -d '{
        "model": "meta-llama-3.1-8b-instruct",
        "messages": [{"role": "user", "content": "whats the meaning of life? explain in 5000 chars"}]
    }' && echo " Got output for $counter" &
    echo "Sleeping for 1 second"
    sleep 1
done

# Added following to the Grafana
# https://grafana.com/grafana/dashboards/12239-nvidia-dcgm-exporter-dashboard/
# https://grafana.com/grafana/dashboards/15117-nvidia-dcgm-exporter/
```
