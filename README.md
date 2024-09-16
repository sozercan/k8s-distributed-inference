# k8s-distributed-inference

# Command to deploy WebAPI Server on GPU
kubectl patch deployment localai-main \
    --type='json' \
    -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args/2", "value": "--p2ptoken=<new-token>"}, {"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "localai/localai:latest-aio-gpu-nvidia-cuda-12"}]'


# Command to deploy Workers with GPU 
kubectl patch deployment localai-workers \
    --type='json' \
    -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args/2", "value": "--p2ptoken=<new-token>"}, {"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "localai/localai:latest-aio-gpu-nvidia-cuda-12"}]'
