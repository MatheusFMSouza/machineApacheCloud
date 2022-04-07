terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {

}

resource "azurerm_resource_group" "rg-apache" {
  name     = "classActivityApache"
  location = var.location
}

resource "azurerm_virtual_network" "network" {
  name                = "network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg-apache.location
  resource_group_name = azurerm_resource_group.rg-apache.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet"
  resource_group_name  = azurerm_resource_group.rg-apache.name
  virtual_network_name = azurerm_virtual_network.network.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "ip-public" {
  name                = "publicIP"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg-apache.name
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "firewall" {
  name                = "networkSecurityGroup"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg-apache.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Web"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}


resource "azurerm_network_interface" "nt-interface" {
  name                = "nt-interface"
  location            = azurerm_resource_group.rg-apache.location
  resource_group_name = azurerm_resource_group.rg-apache.name

  ip_configuration {
    name                          = "nt-ip"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip-public.id
  }
}


resource "azurerm_network_interface_security_group_association" "network-firewall" {
  network_interface_id      = azurerm_network_interface.nt-interface.id
  network_security_group_id = azurerm_network_security_group.firewall.id
}

resource "azurerm_storage_account" "storage-apache" {
  name                     = "stapache"
  resource_group_name      = azurerm_resource_group.rg-apache.name
  location                 = azurerm_resource_group.rg-apache.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

variable "user" {
  description = "usuario"
  type        = string
}

variable "password" {

}


resource "azurerm_linux_virtual_machine" "vm_apache" {
  name                = "vmApache"
  resource_group_name = azurerm_resource_group.rg-apache.name
  location            = azurerm_resource_group.rg-apache.location
  size                = "Standard_D2s_v3"

  network_interface_ids = [
    azurerm_network_interface.nt-interface.id
  ]

  admin_username                  = var.user
  admin_password                  = var.password
  disable_password_authentication = false

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  os_disk {
    name                 = "disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.storage-apache.primary_blob_endpoint
  }

}

data "azurerm_public_ip" "ip-public-value" {
  name                = azurerm_public_ip.ip-public.name
  resource_group_name = azurerm_resource_group.rg-apache.name
}

resource "null_resource" "installApache" {

  connection {
    type     = "ssh"
    user     = var.user
    password = var.password
    host     = data.azurerm_public_ip.ip-public-value.ip_address
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y apache2",
    ]
  }

  depends_on = [
    azurerm_linux_virtual_machine.vm_apache
  ]

}
