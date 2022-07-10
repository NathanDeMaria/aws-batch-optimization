from datetime import datetime, timezone
from aiobotocore.session import AioBaseClient

from .config import Config
from .job import Job


class JobDefinition:
    def __init__(self, batch_client: AioBaseClient, arn: str, config: Config):
        self._batch_client = batch_client
        self._arn = arn
        self._config = config

    @classmethod
    async def create_from_image(
        cls,
        batch_client: AioBaseClient,
        image: str,
        config: Config = None,
    ):
        """
        Make a new job definition based on an image
        """
        if config is None:
            config = Config.load()
        response = await batch_client.register_job_definition(
            jobDefinitionName=image,
            type="container",
            containerProperties={
                "image": image,
                "jobRoleArn": config.job_role_arn,
                "vcpus": 1,
                "memory": 1000,  # MiB
                # do I need this? "executionRoleArn": "???",
            },
        )
        return cls(batch_client, response["jobDefinitionArn"], config)

    async def run(self) -> Job:
        """
        Run an instance of this job
        """
        name_base = self._arn.split("/")[-1].split(":")[0]
        job = await self._batch_client.submit_job(
            jobName=f"{name_base}-{int(datetime.now(timezone.utc).timestamp())}",
            jobQueue=self._config.job_queue_name,
            jobDefinition=self._arn,
            # containerOverrides=dict(command=command),
        )
        return Job(job["jobId"], self._batch_client)
