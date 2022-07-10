import asyncio
from typing import Literal, FrozenSet
import aiobotocore


_Status = Literal[
    "SUBMITTED",
    "PENDING",
    "RUNNABLE",
    "STARTING",
    "RUNNING",
    "SUCCEEDED",
    "FAILED",
]
_FINISHED_STATUSES: FrozenSet[_Status] = frozenset(["SUCCEEDED", "FAILED"])


class Job:
    def __init__(self, job_id: str, batch_client: aiobotocore.session.AioBaseClient):
        self._job_id = job_id
        self._batch_client = batch_client

    async def wait(self, poll_duration_s: int = 5) -> bool:
        """
        Poll until the jobs done.
        Return true iff success
        """
        job = await self._get_job()
        while job["status"] not in _FINISHED_STATUSES:
            await asyncio.sleep(poll_duration_s)
            job = await self._get_job()
        return job["status"] == "SUCCEEDED"

    async def _get_job(self) -> dict:
        response = await self._batch_client.describe_jobs(jobs=[self._job_id])
        return [j for j in response["jobs"] if j["jobId"] == self._job_id][0]
