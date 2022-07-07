import asyncio
from contextlib import asynccontextmanager
from typing import AsyncIterator
from uuid import uuid4
import aiobotocore
from botocore.exceptions import ClientError

from .config import Config


class TaskDefinition:
    """
    Run some task with parameters:
    - location to write a text file to on S3
    - float kwargs

    Assumes it writes a float output to that file
    """

    def __init__(
        self,
        arn: str,
        s3_client: aiobotocore.session.AioBaseClient,
        batch_client: aiobotocore.session.AioBaseClient,
        config: Config = None,
    ):
        self._arn = arn
        self._s3_client = s3_client
        self._batch_client = batch_client
        self._config = config or Config.load()

    async def run(self, **kwargs: float):
        """
        Run an instance of the job
        """
        run_id = str(uuid4())
        params = "--".join([f"{key}-{value:.0f}" for key, value in kwargs.items()])
        job_name = f"{run_id}--{params}"
        key = f"{job_name}.txt"

        command = [key]
        for param, value in kwargs.items():
            command.append(f"--{param.replace('_', '-')}")
            command.append(str(value))

        await self._batch_client.submit_job(
            jobName=job_name,
            jobQueue=self._config.job_queue_name,
            jobDefinition=self._arn,
            containerOverrides=dict(command=command),
        )

        response = await self._get_from_s3_eventually(key)
        stream = response["Body"]
        async with stream as opened_stream:
            body = await opened_stream.read()
        return float(body)

    async def _get_from_s3_eventually(self, key: str):
        while True:
            try:
                return await self._s3_client.get_object(
                    Bucket=self._config.temp_bucket, Key=key
                )
            except ClientError as error:
                if error.response["Error"]["Code"] != "NoSuchKey":
                    raise error
                await asyncio.sleep(5)


@asynccontextmanager
async def create_task_definition(arn: str) -> AsyncIterator[TaskDefinition]:
    """
    Create a task def that'll run batch tasks
    """
    session = aiobotocore.get_session()
    async with session.create_client("s3") as s3_client:
        async with session.create_client("batch") as batch_client:
            yield TaskDefinition(arn, s3_client, batch_client)
