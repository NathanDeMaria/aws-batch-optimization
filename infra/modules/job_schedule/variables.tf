variable "schedule_name" {
  description = "Name of the schedule, also used as the submitted job's name"
  type        = string
}

variable "schedule_expression" {
  description = "EventBridge Scheduler expression, e.g. cron(0 8 ? * MON *)"
  type        = string
}

variable "schedule_timezone" {
  description = "Timezone the expression is evaluated in"
  type        = string
  default     = "America/Chicago"
}

variable "job_definition" {
  description = "Job definition name or ARN to submit"
  type        = string
}

variable "job_queue_arn" {
  description = "ARN of the queue to submit into"
  type        = string
}

variable "scheduler_role_arn" {
  description = "IAM role EventBridge Scheduler assumes to call SubmitJob"
  type        = string
}

variable "command" {
  description = "Command override for this schedule. Empty keeps the definition's own."
  type        = list(string)
  default     = []
}

variable "array_size" {
  description = "Submit as an array job of this size, or null for a plain job. Batch rejects a size below 2."
  type        = number
  default     = null
}
