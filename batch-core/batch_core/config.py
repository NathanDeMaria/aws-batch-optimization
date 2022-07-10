import json
import os
from dataclasses import dataclass
from dataclasses_json import DataClassJsonMixin


_CONFIG_FILE_PATH_ENV_VAR = "BATCH_CONFIG_FILE_PATH"


@dataclass
class Config(DataClassJsonMixin):
    """
    Configuration for this package.
    Load this from the terraform output created in the other half of this repo
    """

    bucket: str
    temp_bucket: str
    job_queue_name: str
    job_role_arn: str

    @classmethod
    def load(cls, file_path: str = None):
        """
        Read the config file from terraform output.
        """
        if file_path is None:
            file_path = os.environ[_CONFIG_FILE_PATH_ENV_VAR]
        with open(file_path, encoding="utf-8") as file:
            raw = json.load(file)
        return cls(**{key: raw[key]["value"] for key in cls.schema().fields.keys()})
