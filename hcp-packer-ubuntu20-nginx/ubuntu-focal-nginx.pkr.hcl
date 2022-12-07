packer {
  required_version = ">= 1.7.7"
  required_plugins {
    azure = {
      version = "~>1.0"
      source  = "github.com/hashicorp/azure"
    }
  }
}

data "hcp-packer-image" "ubuntu20-base" {
  bucket_name    = "ubuntu20-base"
  channel        = "development"
  cloud_provider = "azure"
  region         = var.az_region
}

locals {
  timestamp  = regex_replace(timestamp(), "[- TZ:]", "")
  image_name = "${var.prefix}-ubuntu20-nginx-${local.timestamp}"
}

source "azure-arm" "nginx" {
  os_type                   = "Linux"
  build_resource_group_name = var.az_resource_group
  vm_size                   = "Standard_B2s"

  # Source image
  custom_managed_image_name                = data.hcp-packer-image.ubuntu20-base.labels.managed_image_name
  custom_managed_image_resource_group_name = data.hcp-packer-image.ubuntu20-base.labels.managed_image_resourcegroup_name

  # Destination image
  managed_image_name                = local.image_name
  managed_image_resource_group_name = var.az_resource_group
  shared_image_gallery_destination {
    subscription         = var.az_subscription_id
    resource_group       = var.az_resource_group
    gallery_name         = var.az_image_gallery
    image_name           = "ubuntu20-nginx"
    image_version        = formatdate("YYYY.MMDD.hhmm", timestamp())
    replication_regions  = [var.az_region]
    storage_account_type = "Standard_LRS"
  }

  azure_tags = {
    owner      = var.owner
    department = var.department
    build-time = local.timestamp
  }
  use_azure_cli_auth = true
}

build {
  hcp_packer_registry {
    bucket_name = "ubuntu20-nginx"
    description = "Ubuntu 20.04 (focal) Nginx web server image."
    bucket_labels = {
      "owner"          = var.owner
      "department"     = var.department
      "os"             = "Ubuntu",
      "ubuntu-version" = "20.04",
      "app"            = "nginx",
    }
    build_labels = {
      "build-time" = local.timestamp
    }
  }

  sources = [
    "source.azure-arm.nginx"
  ]

  # Make sure cloud-init has finished
  provisioner "shell" {
    inline = ["echo 'Wait for cloud-init...' && /usr/bin/cloud-init status --wait"]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      "echo 'debconf debconf/frontend select Noninteractive' | sudo debconf-set-selections",
      "echo 'Installing nginx...' && sudo apt-get -qq -y update >/dev/null",
      "sudo apt-get -qq -y -o \"Dpkg::Options::=--force-confdef\" -o \"Dpkg::Options::=--force-confold\" install nginx >/dev/null",
      "echo 'Adding firewall rule...' && sudo ufw allow http >/dev/null"
    ]
  }
}
