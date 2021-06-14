# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import argparse
import json
import logging
import os
import argparse
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)
sm_client = boto3.client("sagemaker")
org_client = boto3.client("organizations")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--log-level", type=str, default=os.environ.get("LOGLEVEL", "INFO").upper())
    parser.add_argument("--sagemaker-project-id", type=str, required=True)
    parser.add_argument("--sagemaker-project-name", type=str, required=True)
    parser.add_argument("--model-package-group-name", type=str, required=True)
    parser.add_argument("--staging-accounts", type=str, default='')
    parser.add_argument("--prod-accounts", type=str, default='')
    parser.add_argument("--env-name", type=str, required=True)
    parser.add_argument("--env-type", type=str, required=True)
    parser.add_argument("--multi-account-deployment", type=str, required=True)

    args, _ = parser.parse_known_args()

    # Configure logging to output the line number and message
    log_format = "%(levelname)s: [%(filename)s:%(lineno)s] %(message)s"
    logging.basicConfig(format=log_format, level=args.log_level)
    model_package_group_arn = '' 

    # Create model package group if necessary
    try:
        # check if the model package group exists
        logger.info(f"Checking if the model package group {args.model_package_group_name} exists")

        model_package_group_arn = sm_client.describe_model_package_group(
            ModelPackageGroupName=args.model_package_group_name
            )['ModelPackageGroupArn']

        logger.info(f"Found an existing model package group: {model_package_group_arn}")

    except ClientError as e:
        if e.response['Error']['Code'] == 'ValidationException':
            # it doesn't exist, create a new one
            logger.info(f"The model package group {args.model_package_group_name} is not found, creating a new one...")

            model_package_group_arn = sm_client.create_model_package_group(
                ModelPackageGroupName=args.model_package_group_name,
                ModelPackageGroupDescription=f"Multi account model group for SageMaker project {args.sagemaker_project_name}",
                Tags=[
                    {'Key': 'sagemaker:project-name', 'Value': args.sagemaker_project_name},
                    {'Key': 'sagemaker:project-id', 'Value': args.sagemaker_project_id},
                    {'Key': 'EnvironmentName', 'Value':args.env_name},
                    {'Key': 'EnvironmentType', 'Value':args.env_type},
                ]
            )['ModelPackageGroupArn']

        else:
            raise e

    if args.multi_account_deployment == "YES":

        if not len(args.staging_accounts) or not len(args.prod_accounts):
            error_message = (
                f"Staging accounts {args.staging_accounts} or production accounts {args.prod_accounts.split} are not provided for multi-account-deployment"
            )
            logger.error(error_message)
            raise Exception(error_message)

        logger.info(f"Staging accounts: {args.staging_accounts} and production accounts: {args.prod_accounts} are provided. Setting up the permissions...")

        # Construct the principals for the account ids 
        principals = [f"arn:aws:iam::{acc}:root" for acc in
                        args.staging_accounts.split(",") + args.prod_accounts.split(",")]

        # create policy for cross-account access to the ModelPackageGroup
        sm_client.put_model_package_group_policy(
            ModelPackageGroupName=args.model_package_group_name,
            ResourcePolicy=json.dumps({
                'Version': '2012-10-17',
                'Statement': [{
                    'Sid': 'ModelPackageGroupPerm',
                    'Effect': 'Allow',
                    'Principal': {'AWS': principals},
                    'Action': ['sagemaker:DescribeModelPackageGroup'],
                    'Resource': model_package_group_arn
                },{
                    'Sid': 'ModelVersionPerm',
                    'Effect': 'Allow',
                    'Principal': {'AWS': principals },
                    'Action': [ 'sagemaker:DescribeModelPackage',
                                'sagemaker:ListModelPackages',
                                'sagemaker:UpdateModelPackage',
                                'sagemaker:CreateModel'],
                    'Resource': f"{model_package_group_arn.replace('model-package-group', 'model-package')}/*"
                }]
            })
        )
    else:
        logger.info(f"Multi-account deployment is set to NO for this project")
            
    
