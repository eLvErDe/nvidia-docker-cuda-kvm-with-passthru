Edit top variables to suit your own setup


What's going to happen then

1. Unbind graphic card id from current kernel driver

2. Load PCI passthru drivers and attach the graphic card

3. Create a KVM disk image using virt-builder

4. Modify the image to deploy latest docker as well as nvidia-docker

5. Create a simple start script with VNC console and host TCP proxy for SSH


You can now verify CUDA is working inside the KVM:
docker pull nvidia/cuda
nvidia-docker run --rm nvidia/cuda nvidia-smi

If you see your graphic card information, you're ready to go.
