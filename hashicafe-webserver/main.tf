terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.46"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

provider "azurerm" {
  features {}
}

data "hcp_packer_image" "ubuntu-webserver" {
  bucket_name    = var.packer_bucket
  channel        = var.packer_channel
  cloud_provider = "azure"
  region         = var.location
}

locals {
  timestamp = timestamp()
  tags = {
    environment = var.env
    department  = var.department
    owner       = var.owner
    application = "HashiCafe website"
  }
}

resource "azurerm_resource_group" "hashicafe" {
  name     = "${var.prefix}-hashicafe-webapp"
  location = var.location

  tags = local.tags
}

resource "azurerm_virtual_network" "hashicafe" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.hashicafe.location
  address_space       = [var.address_space]
  resource_group_name = azurerm_resource_group.hashicafe.name
}

resource "azurerm_subnet" "hashicafe" {
  name                 = "${var.prefix}-subnet"
  virtual_network_name = azurerm_virtual_network.hashicafe.name
  resource_group_name  = azurerm_resource_group.hashicafe.name
  address_prefixes     = [var.subnet_prefix]
}

resource "azurerm_network_security_group" "hashicafe" {
  name                = "${var.prefix}-sg"
  location            = var.location
  resource_group_name = azurerm_resource_group.hashicafe.name

  security_rule {
    name                       = "HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "hashicafe" {
  name                = "${var.prefix}-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.hashicafe.name

  ip_configuration {
    name                          = "${var.prefix}ipconfig"
    subnet_id                     = azurerm_subnet.hashicafe.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.hashicafe.id
  }
}

resource "azurerm_network_interface_security_group_association" "hashicafe" {
  network_interface_id      = azurerm_network_interface.hashicafe.id
  network_security_group_id = azurerm_network_security_group.hashicafe.id
}

resource "azurerm_public_ip" "hashicafe" {
  name                = "${var.prefix}-ip"
  location            = var.location
  resource_group_name = azurerm_resource_group.hashicafe.name
  allocation_method   = "Dynamic"
  domain_name_label   = "${var.prefix}-app"
}

resource "azurerm_linux_virtual_machine" "hashicafe" {
  name                = "${var.prefix}-hashicafe-webapp"
  location            = var.location
  resource_group_name = azurerm_resource_group.hashicafe.name
  size                = var.vm_size

  network_interface_ids = [azurerm_network_interface.hashicafe.id]

  source_image_id = data.hcp_packer_image.ubuntu-webserver.cloud_image_id

  os_disk {
    name                 = "${var.prefix}-osdisk"
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  computer_name  = var.prefix
  admin_username = var.admin_username
  admin_password = var.admin_password

  disable_password_authentication = false

  tags = local.tags

  # Added to allow destroy to work correctly.
  depends_on = [azurerm_network_interface_security_group_association.hashicafe]
}

# We're using a little trick here so we can run the provisioner without
# destroying the VM. Do not do this in production.

resource "random_integer" "product" {
  min = 0
  max = length(var.hashi_products) - 1
  keepers = {
    "timestamp" = local.timestamp
  }
}

resource "null_resource" "configure-web-app" {
  depends_on = [azurerm_linux_virtual_machine.hashicafe]

  triggers = {
    build_number = local.timestamp
  }

  connection {
    type     = "ssh"
    user     = var.admin_username
    password = var.admin_password
    host     = azurerm_public_ip.hashicafe.fqdn
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir /var/www/html/img",
      "sudo chown -R ${var.admin_username} /var/www/html"
    ]
  }

  provisioner "file" {
    content = templatefile("files/index.html", {
      product_name  = var.hashi_products[random_integer.product.result].name
      product_color = var.hashi_products[random_integer.product.result].color
      product_image = var.hashi_products[random_integer.product.result].image_file
    })
    destination = "/var/www/html/index.html"
  }

  provisioner "file" {
    source      = "files/img/"
    destination = "/var/www/html/img"
  }
}
