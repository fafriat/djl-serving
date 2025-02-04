# -*- mode: dockerfile -*-
# Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You may not use this file
# except in compliance with the License. A copy of the License is located at
#
# http://aws.amazon.com/apache2.0/
#
# or in the "LICENSE.txt" file accompanying this file. This file is distributed on an "AS IS"
# BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or implied. See the License for
# the specific language governing permissions and limitations under the License.
ARG version=11.8.0-cudnn8-devel-ubuntu20.04
FROM nvidia/cuda:$version
ARG djl_version=0.24.0~SNAPSHOT
ARG python_version=3.9
ARG torch_version=2.0.1
ARG torch_vision_version=0.15.2
ARG deepspeed_wheel="https://publish.djl.ai/deepspeed/deepspeed-nightly-py2.py3-none-any.whl"
ARG flash_attn_wheel="https://publish.djl.ai/flash_attn/flash_attn-1.0.9-cp39-cp39-linux_x86_64.whl"
ARG dropout_layer_norm_wheel="https://publish.djl.ai/flash_attn/dropout_layer_norm-0.1-cp39-cp39-linux_x86_64.whl"
ARG rotary_emb_wheel="https://publish.djl.ai/flash_attn/rotary_emb-0.1-cp39-cp39-linux_x86_64.whl"
ARG flash_attn_2_wheel="https://publish.djl.ai/flash_attn/flash_attn_2-2.0.1-cp39-cp39-linux_x86_64.whl"
ARG vllm_wheel="https://publish.djl.ai/vllm/vllm-0.1.1-cp39-cp39-linux_x86_64.whl"
ARG lmi_dist_wheel="https://publish.djl.ai/lmi_dist/lmi_dist-nightly-py3-none-any.whl"
ARG protobuf_version=3.20.3
ARG transformers_version=4.32.1
ARG accelerate_version=0.22.0
ARG diffusers_version=0.16.0
ARG bitsandbytes_version=0.41.1
ARG peft_version=0.3.0

EXPOSE 8080

COPY dockerd-entrypoint.sh /usr/local/bin/dockerd-entrypoint.sh
RUN chmod +x /usr/local/bin/dockerd-entrypoint.sh
WORKDIR /opt/djl
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
# ENV NO_OMP_NUM_THREADS=true
ENV JAVA_OPTS="-Xmx1g -Xms1g -XX:+ExitOnOutOfMemoryError"
ENV MODEL_SERVER_HOME=/opt/djl
ENV MODEL_LOADING_TIMEOUT=1200
ENV PREDICT_TIMEOUT=240
ENV DJL_CACHE_DIR=/tmp/.djl.ai
ENV HUGGINGFACE_HUB_CACHE=/tmp/.cache/huggingface/hub
ENV TRANSFORMERS_CACHE=/tmp/.cache/huggingface/transformers
ENV PYTORCH_KERNEL_CACHE_PATH=/tmp/.cache
ENV BITSANDBYTES_NOWELCOME=1

ENTRYPOINT ["/usr/local/bin/dockerd-entrypoint.sh"]
CMD ["serve"]

COPY scripts scripts/
RUN mkdir -p /opt/djl/conf && \
    mkdir -p /opt/djl/deps && \
    mkdir -p /opt/djl/partition && \
    mkdir -p /opt/ml/model
COPY config.properties /opt/djl/conf/config.properties
COPY partition /opt/djl/partition

RUN apt-get update && \
    scripts/install_djl_serving.sh $djl_version && \
    mkdir -p /opt/djl/bin && cp scripts/telemetry.sh /opt/djl/bin && \
    echo "${djl_version} deepspeed" > /opt/djl/bin/telemetry && \
    scripts/install_python.sh ${python_version} && \
    scripts/install_s5cmd.sh x64 && \
    DEBIAN_FRONTEND=noninteractive apt-get install -yq libaio-dev libopenmpi-dev && \
    pip3 install torch==${torch_version} torchvision==${torch_vision_version} --extra-index-url https://download.pytorch.org/whl/cu118 \
    ${deepspeed_wheel} ${flash_attn_wheel} ${dropout_layer_norm_wheel} ${rotary_emb_wheel} ${flash_attn_2_wheel} \
    ${vllm_wheel} ${lmi_dist_wheel} protobuf==${protobuf_version} transformers==${transformers_version} \
    mpi4py sentencepiece einops accelerate==${accelerate_version} bitsandbytes==${bitsandbytes_version}\
    diffusers[torch]==${diffusers_version} peft==${peft_version} opencv-contrib-python-headless safetensors scipy && \
    scripts/install_aitemplate.sh && \
    scripts/patch_oss_dlc.sh python && \
    scripts/security_patch.sh deepspeed && \
    useradd -m -d /home/djl djl && \
    chown -R djl:djl /opt/djl && \
    rm -rf scripts && \
    pip3 cache purge && \
    apt-get clean -y && rm -rf /var/lib/apt/lists/*

LABEL maintainer="djl-dev@amazon.com"
LABEL dlc_major_version="1"
LABEL com.amazonaws.ml.engines.sagemaker.dlc.framework.djl.deepspeed="true"
LABEL com.amazonaws.ml.engines.sagemaker.dlc.framework.djl.v0-24-0.deepspeed="true"
LABEL com.amazonaws.sagemaker.capabilities.multi-models="true"
LABEL com.amazonaws.sagemaker.capabilities.accept-bind-to-port="true"
