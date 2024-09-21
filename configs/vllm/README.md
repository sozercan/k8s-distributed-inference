# Deploy vLLM Inference on AKS

This guide provides steps to deploy vLLM inference on an Azure Kubernetes Service (AKS) cluster. The vLLM deployment utilizes GPU nodes and supports model parallelism across multiple GPUs for serving large models like `microsoft/phi-2`.

## Prerequisites

- **AKS Cluster**: Ensure your AKS cluster has GPU nodes (N-series) enabled. For distributed inference, use a multi-GPU node (like certain A100/H100 instance types). 
- **NVIDIA GPU Operator**: Installed and managing the GPU resources.
- **kubectl**: Installed and configured to interact with your AKS cluster.
- **Huggingface/Meta model access**: Permission for the models you want to deploy, if necessary.

Note: vLLM does not seem to distribute weights with multi instance GPUs out of the box. There are may be workarounds, as described [here](https://docs.vllm.ai/en/latest/serving/distributed_serving.html#multi-node-inference-and-serving)

## Step 1: Create the Namespace

Create a dedicated namespace for the vLLM deployment:

```bash
kubectl create namespace vllm-ns
```

# Step 2: Deploy the vLLM Model

## Deploy the vLLM inference model using the provided Kubernetes deployment file.

Save the deployment configuration to vllm_med.yaml.
Apply the deployment:

```
kubectl apply -f vllm_med.yaml
```
This deployment will set up a vLLM model server that splits the model across two GPUs.

# Step 3: Expose the vLLM Service
Expose the deployment using the provided service configuration (like `vllm_med_svc.yaml` in this directory).

Apply the service:
```bash
kubectl apply -f vllm_med_svc.yaml
```

This will create a ClusterIP service that allows internal communication within the AKS cluster.

# Step 4: Verify Deployment
Check the status of the deployment and service:

```
kubectl get deployments -n vllm-ns
kubectl get svc -n vllm-ns
```

You should see the vLLM deployment running and the service exposing it on port 8000.

To interact with the vLLM service locally, you can set up port forwarding from your local machine to the Kubernetes service:

```
kubectl port-forward service/vllm-openai-svc 8000:8000 -n vllm-ns
```

This command will forward your local port 8000 to the service port 8000 inside the Kubernetes cluster.

Testing the API
Once the port forwarding is active, you can test the vLLM inference server locally. For example, you can send a request to the OpenAI-compatible API using curl:


```
curl http://127.0.0.1:8000/v1/completions \ 
-H "Content-Type: application/json" \
-d '{
  "model": "microsoft/phi-2",
  "prompt": "What is Kubernetes?",
  "temperature": 0.7,
  "max_tokens": 100
}'
```
This should return a generated text completion for the given prompt.


