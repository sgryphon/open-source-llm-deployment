"""Print a short-term Amazon Bedrock API key (up to 12 hours) from your current AWS sign-in.

  $ENV:BEDROCK_API_KEY = python get_bedrock_api_key.py
"""

import argparse
import logging
import os

from aws_bedrock_token_generator import provide_token

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("--region", default=os.environ.get("AWS_REGION", "ap-southeast-2"),
                    help="region the key works in (default: AWS_REGION or ap-southeast-2)")
parser.add_argument("-v", "--verbose", action="store_true", help="log progress to stderr")
args = parser.parse_args()

logging.basicConfig(level=logging.INFO if args.verbose else logging.WARNING, format="%(message)s")
logging.info("Generating Bedrock API key for %s", args.region)
print(provide_token(region=args.region))
