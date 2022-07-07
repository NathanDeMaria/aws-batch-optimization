_init:
	terraform init

apply: _init
	terraform apply

outputs: apply
	terraform output -json > config.json
