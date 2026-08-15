variable "job_name" {
  description = "Name of the Batch job definition"
  type        = string
}

variable "image" {
  description = "Full image URL, e.g. <repo_url>:<tag>"
  type        = string
}

variable "command" {
  description = "Default command. Callers routinely override this per submission."
  type        = list(string)
  default     = []
}

variable "execution_role_arn" {
  description = "IAM role the Batch agent uses, e.g. to pull from ECR"
  type        = string
}

variable "job_role_arn" {
  description = "IAM role the container's own code runs as"
  type        = string
}

variable "vcpu" {
  description = "vCPUs to reserve. The shared compute environment is all .large instances, so 2 is the whole box."
  type        = number
  default     = 2
}

variable "memory" {
  description = "MiB to reserve. Must leave room for the ECS agent: an m6i.large has 8192 MiB total but cannot place a job asking for all of it."
  type        = number
  default     = 4096
}

variable "environment_variables" {
  description = "Environment baked into the definition. Per-run values belong in containerOverrides instead."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "retry_attempts" {
  description = "Total attempts. Above 1, only host failures (spot reclaims) are retried; application failures still exit on the first attempt."
  type        = number
  default     = 1
}

variable "timeout_seconds" {
  description = "Wall-clock limit per attempt, or null for none"
  type        = number
  default     = null
}
