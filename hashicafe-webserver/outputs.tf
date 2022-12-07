output "hashiapp_url" {
  description = "URL of the provisioned webapp."
  value       = "http://${azurerm_public_ip.hashicafe.fqdn}"
}

output "image_name" {
  description = "Source image used for the VM."
  value       = data.hcp_packer_image.ubuntu-webserver.labels["managed_image_name"]
}

output "product" {
  description = "The product which was randomly selected."
  value       = var.hashi_products[random_integer.product.result].name
}
