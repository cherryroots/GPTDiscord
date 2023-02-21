ARG PY_VERSION=3.9



# Build container
FROM python:${PY_VERSION} as base
FROM base as builder
ARG PY_VERSION
ARG TARGETPLATFORM
ARG WITH_WHISPER

COPY . .

#Install rust
RUN apt-get update
RUN apt-get install -y \
    build-essential \
    gcc \
    curl
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y && apt-get install --reinstall libc6-dev -y
ENV PATH="/root/.cargo/bin:${PATH}"


RUN mkdir /install /src
WORKDIR /install

RUN pip install --target="/install" --upgrade pip setuptools wheel
RUN pip install --target="/install" --upgrade setuptools_rust
# if empty run as usual, if amd64 do the same, if arm64 load an arm version of torch
RUN if [ -z "{$TARGETPLATFORM}" ]; then pip install --target="/install" --upgrade torch==1.9.1+cpu torchvision==0.10.1+cpu -f https://download.pytorch.org/whl/torch_stable.html ; fi
RUN if [ "${TARGETPLATFORM}" = "linux/amd64" ]; then pip install --target="/install" --upgrade torch==1.9.1+cpu torchvision==0.10.1+cpu -f https://download.pytorch.org/whl/torch_stable.html ; fi
RUN if [ "${TARGETPLATFORM}" = "linux/arm64" ]; then pip install --target="/install" --upgrade torch==1.9.0 torchvision==0.10.0 -f https://torch.kmtea.eu/whl/stable.html -f https://ext.kmtea.eu/whl/stable.html ; fi

RUN if [ ! -z "$WITH_WHISPER" ] \
    ; then \
    pip install --target="/install" \
    -r requirements.txt \
    -r requirements_whisper.txt \
    && pip install --target"/install" \
    git+https://github.com/openai/whisper.git --no-deps \
    ; else \
    pip install --target="/install" \
    -r requirements.txt \
    ; fi

COPY requirements.txt /install
RUN pip install --target="/install" -r requirements.txt

COPY README.md /src
COPY cogs /src/cogs
COPY models /src/models
COPY services /src/services
COPY gpt3discord.py /src
COPY pyproject.toml /src

# For debugging + seeing that the modiles file layouts look correct ...
RUN find /src
RUN pip install --target="/install" /src

# Copy minimal to main image (to keep as small as possible)
FROM python:${PY_VERSION}-slim

ARG PY_VERSION
COPY . .
COPY --from=builder /install /usr/local/lib/python${PY_VERSION}/site-packages
RUN mkdir -p /opt/gpt3discord/etc
COPY gpt3discord.py /opt/gpt3discord/bin/
COPY image_optimizer_pretext.txt conversation_starter_pretext.txt conversation_starter_pretext_minimal.txt /opt/gpt3discord/share/
COPY openers /opt/gpt3discord/share/openers
CMD ["python3", "/opt/gpt3discord/bin/gpt3discord.py"]
