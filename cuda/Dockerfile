# from https://dev.to/yuesu/setting-up-vgpu-in-docker-container-with-specific-python-version-5ei6

# Use an official NVIDIA CUDA runtime as a parent image
FROM nvidia/cuda:12.8.1-base-ubuntu22.04


# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Helsinki

# Install Python and pip
RUN apt-get update && apt-get install -y \
  python3 \
  python3-pip \
  && rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip

RUN python3 --version
RUN pip3 --version

# Create symbolic links for Python
RUN ln -sf /usr/bin/python3 /usr/bin/python

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

