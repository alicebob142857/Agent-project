export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export HCCL_BUFFSIZE=512
export OMP_PROC_BIND=false
export OMP_NUM_THREADS=1
export TASK_QUEUE_ENABLE=1

vllm serve /data/models/Qwen3.5-9B \
  --host 0.0.0.0 \
  --port 8000 \
  --served-model-name qwen3.5-9b \
  --tensor-parallel-size 2 \
  --max-model-len 4096 \
  --max-num-seqs 8 \
  --max-num-batched-tokens 4096 \
  --trust-remote-code \
  --gpu-memory-utilization 0.85 \
  --additional-config '{"enable_cpu_binding":true}'