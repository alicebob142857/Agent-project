#!/usr/bin/env bash
IMAGE=m.daocloud.io/quay.io/ascend/vllm-ascend:v0.18.0-openeuler
NAME=qwen35_vllm

docker rm -f $NAME 2>/dev/null || true

DEVICE_ARGS=""
for d in /dev/davinci[0-9]*; do
  [ -e "$d" ] && DEVICE_ARGS="$DEVICE_ARGS --device $d"
done

docker run -it \
  --name $NAME \
  --net=host \
  --shm-size=20g \
  $DEVICE_ARGS \
  --device /dev/davinci_manager \
  --device /dev/devmm_svm \
  --device /dev/hisi_hdc \
  -v /usr/local/dcmi:/usr/local/dcmi \
  -v /usr/local/Ascend/driver/tools/hccn_tool:/usr/local/Ascend/driver/tools/hccn_tool \
  -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
  -v /usr/local/Ascend/driver/lib64/:/usr/local/Ascend/driver/lib64/ \
  -v /usr/local/Ascend/driver/version.info:/usr/local/Ascend/driver/version.info \
  -v /etc/ascend_install.info:/etc/ascend_install.info \
  -v /data:/data \
  -v /data/hf_cache:/root/.cache \
  $IMAGE bash