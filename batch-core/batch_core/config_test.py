import json
from pathlib import Path

from .config import Config

_OUTPUT = {
    "bucket": {"value": "results"},
    "temp_bucket": {"value": "scratch"},
    "job_queue_name": {"value": "queue"},
    "job_role_arn": {"value": "arn:aws:iam::1:role/job"},
    "repo_urls": {"value": {"app": "1.dkr.ecr.us-east-2.amazonaws.com/app"}},
    # terraform outputs more than Config reads
    "something_else": {"value": 1},
}


def test_load_reads_terraform_output(tmp_path: Path) -> None:
    path = tmp_path / "config.json"
    path.write_text(json.dumps(_OUTPUT))

    config = Config.load(str(path))

    assert config.bucket == "results"
    assert config.repo_urls == {"app": "1.dkr.ecr.us-east-2.amazonaws.com/app"}


def test_load_defaults_to_the_env_var(tmp_path: Path, monkeypatch) -> None:
    path = tmp_path / "config.json"
    path.write_text(json.dumps(_OUTPUT))
    monkeypatch.setenv("BATCH_CONFIG_FILE_PATH", str(path))

    assert Config.load().job_queue_name == "queue"
