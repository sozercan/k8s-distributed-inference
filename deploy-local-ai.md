# Deploy Local AI on Kubernetes

Deploy the following in the default namesapce
```bash
kubectl apply -f configs/k8s/resource-claim-template.yaml # deploy ResourceClaimTemplate for mig devices
kubectl apply -f configs/k8s/localai-main.yaml # deploy localai main component with p2p
kubectl apply -f configs/k8s/localai-svc.yaml # deploy localai svc to access dashboard
#confirm localai-deployment pod is running
kubectl port-forward service/localai-loadbalancer 8080:80 # port-forward to launch localai dashboard
```

Launch the localai dashboard and get token for psp: http://localhost:8080/p2p/
Copy the token and replace the following in configs/k8s/localai-workers.yaml before deployment
> value: "REPLACEME"

```bash
kubectl apply -f configs/k8s/localai-workers.yaml # deploy localai workers
```

Verify all localai workers are now part of the same localai swarm cluster
From http://localhost:8080/p2p/, ensure there are 3/3 running workers.

Verify resourceclaims have been created for all localai components

```console
kubectl get resourceclaims
NAME                                                   STATE                AGE
localai-deployment-bcd8c9dcc-klhmr-mig-devices-kpb7l   allocated,reserved   1m
localai-worker-69785c7775-8rqgl-mig-devices-8xj5l      allocated,reserved   1m
localai-worker-69785c7775-c2smf-mig-devices-5jtpb      allocated,reserved   1m
localai-worker-69785c7775-pmfn2-mig-devices-5z6bx      allocated,reserved   1m
```

Verify all localai components are using the mig devices

> nvidia-smi

Example output. Note: `processes` section below shows MIG device (GIID) used and memory consumed by each local ai component.

```bash       
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 560.35.03              Driver Version: 560.35.03      CUDA Version: 12.6     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA A100 80GB PCIe          On  |   00000001:00:00.0 Off |                   On |
| N/A   43C    P0             66W /  300W |    8530MiB /  81920MiB |     N/A      Default |
|                                         |                        |              Enabled |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| MIG devices:                                                                            |
+------------------+----------------------------------+-----------+-----------------------+
| GPU  GI  CI  MIG |                     Memory-Usage |        Vol|        Shared         |
|      ID  ID  Dev |                       BAR1-Usage | SM     Unc| CE ENC  DEC  OFA  JPG |
|                  |                                  |        ECC|                       |
|==================+==================================+===========+=======================|
|  0    7   0   0  |              13MiB /  9728MiB    | 14      0 |  1   0    0    0    0 |
|                  |                 0MiB / 16383MiB  |           |                       |
+------------------+----------------------------------+-----------+-----------------------+
|  0    8   0   1  |              13MiB /  9728MiB    | 14      0 |  1   0    0    0    0 |
|                  |                 0MiB / 16383MiB  |           |                       |
+------------------+----------------------------------+-----------+-----------------------+
|  0    9   0   2  |            2296MiB /  9728MiB    | 14      0 |  1   0    0    0    0 |
|                  |                 2MiB / 16383MiB  |           |                       |
+------------------+----------------------------------+-----------+-----------------------+
|  0   10   0   3  |            2188MiB /  9728MiB    | 14      0 |  1   0    0    0    0 |
|                  |                 2MiB / 16383MiB  |           |                       |
+------------------+----------------------------------+-----------+-----------------------+
|  0   11   0   4  |            2004MiB /  9728MiB    | 14      0 |  1   0    0    0    0 |
|                  |                 2MiB / 16383MiB  |           |                       |
+------------------+----------------------------------+-----------+-----------------------+
|  0   12   0   5  |            2004MiB /  9728MiB    | 14      0 |  1   0    0    0    0 |
|                  |                 2MiB / 16383MiB  |           |                       |
+------------------+----------------------------------+-----------+-----------------------+
|  0   13   0   6  |              13MiB /  9728MiB    | 14      0 |  1   0    0    0    0 |
|                  |                 0MiB / 16383MiB  |           |                       |
+------------------+----------------------------------+-----------+-----------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI        PID   Type   Process name                              GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|    0    8    0      16798      C   ...nd-assets/util/llama-cpp-rpc-server         74MiB |
|    0   10    0      16808      C   ...nd-assets/util/llama-cpp-rpc-server         74MiB |
|    0   11    0      16804      C   ...nd-assets/util/llama-cpp-rpc-server         74MiB 
+-----------------------------------------------------------------------------------------+
```

Verify all localai workers are serving inference requests
From http://localhost:8080/browse/, choose a model then click `INSTALL` e.g. meta-llama-3.1-8b-instruct
Once the model is done installing, go to http://localhost:8080/chat and select your model from the dropdown.
Or navigate to the chat with the model directly. e.g http://localhost:8080/chat/meta-llama-3.1-8b-instruct

Start a chat, first one will take sometime as it initilizes.
After few chats

> nvidia-smi

```console                                                                             
+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI        PID   Type   Process name                              GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|    0    8    0      16798      C   ...nd-assets/util/llama-cpp-rpc-server       1978MiB |
|    0    9    0      17630      C   .../backend-assets/grpc/llama-cpp-grpc       2162MiB |
|    0   10    0      16808      C   ...nd-assets/util/llama-cpp-rpc-server       1978MiB |
|    0   11    0      16804      C   ...nd-assets/util/llama-cpp-rpc-server       2270MiB |
+-----------------------------------------------------------------------------------------+
```