# tf-azure-webapp

A sample web application for Terraform demonstrations.

Uses an image sourced from HCP Packer, specified by the packer_bucket and packer_channel input variables. See the [HCP provider docs](https://registry.terraform.io/providers/hashicorp/hcp/latest/docs) for full usage instructions. The image is expected to have Nginx (or Apache HTTPD) already installed.
