# 3.13.4-bullseye on 2025-06-08
FROM python@sha256:0cfd98c036493924a8f80c343aeb1d14a23e8ef4c8c18c7932c36c80fa2e72aa

# For persisting bash history
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" && echo $SNIPPET >> "/root/.bashrc"

# Poetry
ENV POETRY_VERSION=2.1.3 \
    POETRY_HOME=/opt/poetry
RUN curl -sSL https://install.python-poetry.org | python3 -
ENV PATH="${POETRY_HOME}/bin:${PATH}"

# Is this a good way to add stuff on load?
# Not sure, but it's working
COPY profile.sh /root/profile.sh
RUN echo ". profile.sh" >> "/root/.bashrc"

COPY poetry.* ./
COPY pyproject.toml ./
COPY batch_core/__init__.py ./batch_core/
RUN poetry install
