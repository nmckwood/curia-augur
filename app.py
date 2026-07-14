#!/usr/bin/env python3
"""Curia Augur CDK app entry point.

Single environment (no dev/prod). Deploy with env args passed as context, e.g.:

    cdk deploy --all \
        --context account=123456789012 \
        --context region=us-east-1

The web ACM certificate must live in us-east-1 for CloudFront, so deploying the whole
app to us-east-1 is the simplest supported configuration.
"""
import os

import aws_cdk as cdk

from infra.domain_stack import DomainStack
from infra.resources_stack import CuriaAugurStack

app = cdk.App()

account = app.node.try_get_context("account") or os.getenv("CDK_DEFAULT_ACCOUNT")
region = app.node.try_get_context("region") or os.getenv("CDK_DEFAULT_REGION") or "us-east-1"
root_domain = app.node.try_get_context("root_domain") or "howfhowfhowf.com"
subdomain = app.node.try_get_context("subdomain") or "curia-augur"

env = cdk.Environment(account=account, region=region)

domain_stack = DomainStack(
    app,
    "CuriaAugurDomainStack",
    root_domain=root_domain,
    subdomain=subdomain,
    env=env,
)

resources_stack = CuriaAugurStack(
    app,
    "CuriaAugurStack",
    root_domain=root_domain,
    subdomain=subdomain,
    hosted_zone=domain_stack.hosted_zone,
    api_certificate=domain_stack.api_certificate,
    web_certificate=domain_stack.web_certificate,
    env=env,
)
resources_stack.add_dependency(domain_stack)

app.synth()
