"""Curia Augur resource stack: buckets, container-image data lambdas, S3-event ML
trigger, Cognito-secured files API, and the CloudFront/S3 web hosting.

Single environment, cost-optimized: pay-per-use S3 + DynamoDB-free (outputs are files),
container-image lambdas (pay per invoke), debug-only log retention kept short.
"""

from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_s3_notifications as s3n,
    aws_lambda as lambda_,
    aws_apigateway as apigw,
    aws_cognito as cognito,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_route53 as route53,
    aws_route53_targets as targets,
    aws_logs as logs,
)
from constructs import Construct

NAME = "curia-augur"


class CuriaAugurStack(Stack):
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        root_domain,
        subdomain,
        hosted_zone,
        api_certificate,
        web_certificate,
        **kwargs,
    ):
        super().__init__(scope, construct_id, **kwargs)

        app_domain = f"{subdomain}.{root_domain}"
        api_domain = f"api.{subdomain}.{root_domain}"

        # --- Buckets ----------------------------------------------------------
        input_bucket = s3.Bucket(
            self,
            "InputBucket",
            bucket_name=f"{NAME}-input-{self.account}",
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        output_bucket = s3.Bucket(
            self,
            "OutputBucket",
            bucket_name=f"{NAME}-output-{self.account}",
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            cors=[
                s3.CorsRule(
                    allowed_methods=[
                        s3.HttpMethods.GET,
                        s3.HttpMethods.HEAD
                    ],
                    allowed_origins=["*"],
                    allowed_headers=["*"],
                    max_age=3000
                ),
            ]
        )

        # --- Data lambdas (container images) ---------------------------------
        ingestion_fn = lambda_.DockerImageFunction(
            self,
            "DataIngestionFn",
            function_name=f"{NAME}-data-ingestion",
            code=lambda_.DockerImageCode.from_image_asset(
                directory=".", file="apps/data_ingestion/Dockerfile"
            ),
            memory_size=2048,
            timeout=Duration.minutes(5),
            environment={
                "INPUT_BUCKET": input_bucket.bucket_name,
                "OUTPUT_BUCKET": output_bucket.bucket_name,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        input_bucket.grant_read(ingestion_fn)
        output_bucket.grant_read_write(ingestion_fn)

        ml_fn = lambda_.DockerImageFunction(
            self,
            "MlPipelineFn",
            function_name=f"{NAME}-ml-pipeline",
            code=lambda_.DockerImageCode.from_image_asset(
                directory=".", file="apps/ml_pipeline/Dockerfile"
            ),
            memory_size=3008,
            timeout=Duration.minutes(5),
            environment={"OUTPUT_BUCKET": output_bucket.bucket_name},
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        output_bucket.grant_read_write(ml_fn)

        # ML pipeline fires when ingestion writes output/<...>.json (not analysis/).
        output_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(ml_fn),
            s3.NotificationKeyFilter(prefix="output/", suffix=".json"),
        )

        # Cross-analysis prediction (REQUIREMENTS_3): fires when ML writes analysis/<...>.json.
        # Its own writes re-fire this event; the handler no-ops once all analyses are
        # predicted (see apps/prediction/app.py loop guard).
        prediction_fn = lambda_.DockerImageFunction(
            self,
            "PredictionFn",
            function_name=f"{NAME}-prediction",
            code=lambda_.DockerImageCode.from_image_asset(
                directory=".", file="apps/prediction/Dockerfile"
            ),
            memory_size=3008,
            timeout=Duration.minutes(5),
            environment={"OUTPUT_BUCKET": output_bucket.bucket_name},
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        output_bucket.grant_read_write(prediction_fn)
        output_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(prediction_fn),
            s3.NotificationKeyFilter(prefix="analysis/", suffix=".json"),
        )

        # --- Files API lambda (zip, boto3 only) ------------------------------
        files_fn = lambda_.Function(
            self,
            "FilesApiFn",
            function_name=f"{NAME}-files-api",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="app.lambda_handler",
            code=lambda_.Code.from_asset("apps/files_api"),
            memory_size=256,
            timeout=Duration.seconds(30),
            environment={
                "OUTPUT_BUCKET": output_bucket.bucket_name,
                "ANALYSIS_PREFIX": "analysis/",
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        output_bucket.grant_read(files_fn)

        # --- Cognito ----------------------------------------------------------
        user_pool = cognito.UserPool(
            self,
            "UserPool",
            user_pool_name=f"{NAME}-users",
            # Self sign-up is disabled: anyone could otherwise register (email is
            # auto-verified) and obtain a token that passes the API authorizer.
            # Accounts are provisioned by an admin via admin-create-user instead.
            self_sign_up_enabled=False,
            sign_in_aliases=cognito.SignInAliases(email=True),
            auto_verify=cognito.AutoVerifiedAttrs(email=True),
            password_policy=cognito.PasswordPolicy(
                min_length=8,
                require_lowercase=True,
                require_digits=True,
                require_uppercase=True,
            ),
            removal_policy=RemovalPolicy.DESTROY,
        )
        user_pool_client = user_pool.add_client(
            "WebClient",
            user_pool_client_name=f"{NAME}-web",
            generate_secret=False,
            auth_flows=cognito.AuthFlow(user_password=True, user_srp=True),
        )

        # --- REST API + Cognito authorizer -----------------------------------
        api = apigw.RestApi(
            self,
            "FilesApi",
            rest_api_name=f"{NAME}-api",
            domain_name=apigw.DomainNameOptions(
                domain_name=api_domain,
                certificate=api_certificate,
                security_policy=apigw.SecurityPolicy.TLS_1_2,
            ),
            default_cors_preflight_options=apigw.CorsOptions(
                allow_origins=apigw.Cors.ALL_ORIGINS,
                allow_methods=["GET", "OPTIONS"],
                allow_headers=apigw.Cors.DEFAULT_HEADERS,
            ),
            deploy_options=apigw.StageOptions(throttling_rate_limit=20, throttling_burst_limit=10),
        )
        authorizer = apigw.CognitoUserPoolsAuthorizer(
            self, "Authorizer", cognito_user_pools=[user_pool]
        )
        files_resource = api.root.add_resource("files")
        files_resource.add_method(
            "GET",
            apigw.LambdaIntegration(files_fn),
            authorizer=authorizer,
            authorization_type=apigw.AuthorizationType.COGNITO,
        )

        route53.ARecord(
            self,
            "ApiAliasRecord",
            zone=hosted_zone,
            record_name=api_domain,
            target=route53.RecordTarget.from_alias(targets.ApiGateway(api)),
        )

        # --- Web hosting (private S3 + CloudFront OAI) -----------------------
        web_bucket = s3.Bucket(
            self,
            "WebBucket",
            bucket_name=f"{NAME}-web-{self.account}",
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            cors=[
                s3.CorsRule(
                    allowed_methods=[
                        s3.HttpMethods.GET,
                        s3.HttpMethods.HEAD
                    ],
                    allowed_origins=["*"],
                    allowed_headers=["*"],
                    max_age=3000
                ),
            ]
        )
        oai = cloudfront.OriginAccessIdentity(self, "WebOAI")
        web_bucket.grant_read(oai)

        distribution = cloudfront.Distribution(
            self,
            "WebDistribution",
            default_root_object="index.html",
            domain_names=[app_domain],
            certificate=web_certificate,
            default_behavior=cloudfront.BehaviorOptions(
                origin=origins.S3Origin(web_bucket, origin_access_identity=oai),
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
            ),
            error_responses=[
                cloudfront.ErrorResponse(
                    http_status=403,
                    response_http_status=200,
                    response_page_path="/index.html",
                ),
                cloudfront.ErrorResponse(
                    http_status=404,
                    response_http_status=200,
                    response_page_path="/index.html",
                ),
            ],
        )

        route53.ARecord(
            self,
            "WebAliasRecord",
            zone=hosted_zone,
            record_name=app_domain,
            target=route53.RecordTarget.from_alias(
                targets.CloudFrontTarget(distribution)
            ),
        )

        # --- Outputs ----------------------------------------------------------
        CfnOutput(self, "InputBucketName", value=input_bucket.bucket_name)
        CfnOutput(self, "OutputBucketName", value=output_bucket.bucket_name)
        CfnOutput(self, "WebBucketName", value=web_bucket.bucket_name)
        CfnOutput(self, "ApiUrl", value=f"https://{api_domain}")
        CfnOutput(self, "WebUrl", value=f"https://{app_domain}")
        CfnOutput(self, "UserPoolId", value=user_pool.user_pool_id)
        CfnOutput(self, "UserPoolClientId", value=user_pool_client.user_pool_client_id)
        CfnOutput(self, "CloudFrontDomain", value=distribution.distribution_domain_name)
