"""Check a Bedrock API key works: list available models, then send a test prompt.

Calls the OpenAI-compatible bedrock-mantle endpoint with the OpenAI Python client:

  1. GET /models, to list the models available to you in the region
  2. POST /chat/completions, to send a short prompt to the selected model

Uses only a few tokens of inference. No AWS resources are created.

  PowerShell:  $ENV:BEDROCK_API_KEY = python get_bedrock_api_key.py
               python check_bedrock_model.py
"""

import argparse
import logging
import os
import sys

from openai import APIStatusError, OpenAI

log = logging.getLogger(__name__)

HINTS = {
    401: "The key is invalid or expired. Generate a new one with get_bedrock_api_key.py.",
    403: "Your role lacks bedrock-mantle:CreateInference / bedrock-mantle:CallWithBearerToken. "
    "Ask the account owner to add them.",
}


def explain(error: APIStatusError) -> str:
    message = f"HTTP {error.status_code}: {error.message}"
    if "isn't supported on this route" in str(error.message):
        return f"{message}\nThis model is served under /openai/v1; re-run with --base-url .../openai/v1."
    hint = HINTS.get(error.status_code)
    return f"{message}\n{hint}" if hint else message


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--region",
        default=os.environ.get("AWS_REGION", "ap-southeast-2"),
        help="AWS region to call (default: AWS_REGION or ap-southeast-2)",
    )
    parser.add_argument(
        "--model",
        default=os.environ.get("DEPLOY_MODEL_ID", "openai.gpt-oss-120b"),
        help="model id for the test prompt (default: DEPLOY_MODEL_ID or openai.gpt-oss-120b)",
    )
    parser.add_argument(
        "--base-url",
        default=os.environ.get("DEPLOY_BEDROCK_BASE_URL"),
        help="OpenAI-compatible base URL (default: https://bedrock-mantle.<region>.api.aws/v1)",
    )
    parser.add_argument(
        "--api-key",
        default=os.environ.get("BEDROCK_API_KEY"),
        help="Bedrock API key (default: BEDROCK_API_KEY)",
    )
    parser.add_argument("--skip-list", action="store_true", help="skip listing models")
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="log progress to stderr"
    )
    args = parser.parse_args()

    logging.basicConfig(
        stream=sys.stderr,
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(message)s",
    )

    if not args.api_key:
        sys.exit(
            "No API key. Set BEDROCK_API_KEY from get_bedrock_api_key.py, or pass --api-key."
        )

    base_url = args.base_url or f"https://bedrock-mantle.{args.region}.api.aws/v1"
    client = OpenAI(base_url=base_url, api_key=args.api_key)

    try:
        if not args.skip_list:
            log.info("Listing models from %s/models", base_url)
            for model in sorted(client.models.list(), key=lambda m: m.id):
                print(f"{model.id:50} {model.owned_by}")
            print()

        log.info("Sending test prompt to %s", args.model)
        response = client.chat.completions.create(
            model=args.model,
            messages=[{"role": "user", "content": "Say hello in five words."}],
        )
    except APIStatusError as error:
        sys.exit(explain(error))

    if response.usage:
        log.info(
            "Usage: %s prompt, %s completion tokens",
            response.usage.prompt_tokens,
            response.usage.completion_tokens,
        )
    print(f"{args.model}: {response.choices[0].message.content}")


if __name__ == "__main__":
    main()
