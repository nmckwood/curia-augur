"""Domain stack: reuse an existing (caller-supplied) Route53 hosted zone and mint ACM
certs for the curia-augur subdomains.

The hosted zone is looked up (NOT created) so we never create a second zone for a domain
you already own. Certs cover ``<sub>.<root>`` (web) and ``api.<sub>.<root>`` (API). For
CloudFront the web cert must be in us-east-1, so deploy this stack in us-east-1.
"""

from aws_cdk import (
    Stack,
    aws_certificatemanager as acm,
    aws_route53 as route53,
    CfnOutput,
)
from constructs import Construct


class DomainStack(Stack):
    def __init__(self, scope, construct_id, root_domain, subdomain, **kwargs):
        super().__init__(scope, construct_id, **kwargs)

        app_domain = f"{subdomain}.{root_domain}"          # e.g. curia-augur.example.com
        api_domain = f"api.{subdomain}.{root_domain}"      # e.g. api.curia-augur.example.com

        self.hosted_zone = route53.HostedZone.from_lookup(
            self, "HostedZone", domain_name=root_domain
        )

        self.api_certificate = acm.Certificate(
            self,
            "ApiCertificate",
            domain_name=api_domain,
            validation=acm.CertificateValidation.from_dns(self.hosted_zone),
        )

        self.web_certificate = acm.Certificate(
            self,
            "WebCertificate",
            domain_name=app_domain,
            validation=acm.CertificateValidation.from_dns(self.hosted_zone),
        )

        CfnOutput(self, "AppDomain", value=app_domain)
        CfnOutput(self, "ApiDomain", value=api_domain)
