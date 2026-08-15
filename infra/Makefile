TF_ARGS = $(if $(wildcard terraform.tfvars),-var-file=terraform.tfvars,)

_init:
	terraform init

plan: _init
	terraform plan $(TF_ARGS)

apply: _init
	terraform apply $(TF_ARGS)

outputs: apply
	terraform output -json > ~/.aws-batch/config.json

# What CI runs. No credentials and no backend, so it works anywhere.
lint:
	terraform fmt -check -recursive
	terraform init -backend=false
	terraform validate

.PHONY: _init plan apply outputs lint
