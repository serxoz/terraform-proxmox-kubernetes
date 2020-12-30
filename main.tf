# Requires export of PM_PASS
terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
      version = "2.6.6"
    }
  }
}

provider "proxmox" {
  pm_tls_insecure = true
  pm_api_url  = var.proxmox_url
  pm_user     = var.proxmox_user
  pm_parallel = "8"
}

# Generate Password
resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

# Masters
resource "proxmox_vm_qemu" "k8s-masters" {
  count       = var.master_count
  name        = "k8s-master-${count.index}"
  desc        = "k8s-master-${count.index}"
  target_node = var.proxmox_node_name
  clone       = var.clone_name
  agent       = 1
  full_clone  = true
  os_type     = "cloud-init"
  cores       = var.instance_cores
  sockets     = var.instance_sockets
  cpu         = "host"
  memory      = var.instance_memory
  bootdisk    = "scsi0"

  disk {
    size         = var.instance_disk_size
    type         = "scsi"
    storage      = var.instance_storage_name
    iothread     = true
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  lifecycle {
    ignore_changes = [
      network,
    ]
  }

  ipconfig0 = "ip=192.168.1.22${count.index}/24,gw=192.168.1.1"

  sshkeys = var.ssh_key
}

resource "null_resource" "keepalive_password" {
  provisioner "local-exec" {
    command = "echo ${random_password.password.result} >> scripts/password"
  }
}

resource "null_resource" "gather_info" {
  count = var.master_count

  provisioner "local-exec" {
    command = "echo ${element(proxmox_vm_qemu.k8s-masters.*.name, count.index)} ${element(proxmox_vm_qemu.k8s-masters.*.ssh_host, count.index)} >> scripts/serverlist"
  }
}

resource "null_resource" "deploy_master" {
  count = var.master_count

  provisioner "file" {
    source      = "scripts/password"
    destination = "/dev/shm/keepalive_password"
    connection {
      type        = "ssh"
      user        = "debian"
      host        = element(proxmox_vm_qemu.k8s-masters.*.ssh_host, count.index)
      private_key = file(var.private_key_path)
    }
  }

  provisioner "file" {
    source      = "scripts/master.sh"
    destination = "/dev/shm/master.sh"

    connection {
      type        = "ssh"
      user        = "debian"
      host        = element(proxmox_vm_qemu.k8s-masters.*.ssh_host, count.index)
      private_key = file(var.private_key_path)
    }
  }

  provisioner "file" {
    source      = "scripts/serverlist"
    destination = "/dev/shm/serverlist"

    connection {
      type        = "ssh"
      user        = "debian"
      host        = element(proxmox_vm_qemu.k8s-masters.*.ssh_host, count.index)
      private_key = file(var.private_key_path)
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /dev/shm/master.sh",
      "/bin/bash /dev/shm/master.sh"
    ]

    connection {
      type        = "ssh"
      user        = "debian"
      host        = element(proxmox_vm_qemu.k8s-masters.*.ssh_host, count.index)
      private_key = file(var.private_key_path)
    }
  }

  depends_on = [ null_resource.gather_info ]
}

# Workers
resource "proxmox_vm_qemu" "k8s-workers" {
  count       = var.worker_count
  name        = "k8s-worker-${count.index}"
  desc        = "k8s-worker-${count.index}"
  target_node = var.proxmox_node_name
  clone       = var.clone_name
  agent       = 1
  full_clone  = true
  os_type     = "cloud-init"
  cores       = var.instance_cores
  sockets     = var.instance_sockets
  cpu         = "host"
  memory      = var.instance_memory
  bootdisk    = "scsi0"

  disk {
    size         = var.instance_disk_size
    type         = "scsi"
    storage      = var.instance_storage_name
    iothread     = true
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  lifecycle {
    ignore_changes = [
      network,
    ]
  }

  ipconfig0 = "ip=192.168.1.23${count.index}/24,gw=192.168.1.1"

  sshkeys = var.ssh_key

  provisioner "file" {
    source      = "scripts/worker.sh"
    destination = "/dev/shm/worker.sh"

    connection {
      type        = "ssh"
      user        = "debian"
      host        = self.ssh_host
      private_key = file(var.private_key_path)
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /dev/shm/worker.sh",
      "/bin/bash /dev/shm/worker.sh"
    ]

    connection {
      type        = "ssh"
      user        = "debian"
      host        = self.ssh_host
      private_key = file(var.private_key_path)
    }
  }
}
