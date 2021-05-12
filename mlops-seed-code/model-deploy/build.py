# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import argparse
import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)
sm_client = boto3.client("sagemaker")

def get_approved_package(model_package_group_name):
    """Gets the latest approved model package for a model package group.

    Args:
        model_package_group_name: The model package group name.

    Returns:
        The SageMaker Model Package ARN.
    """
    try:
        approved_packages = []
        # Find the latest approved model package. 
        # If there are ceveral approved model packages, take the most recent one (by CreationTime)
        for p in sm_client.get_paginator('list_model_packages').paginate(
            ModelPackageGroupName=model_package_group_name,
            ModelApprovalStatus='Approved',
            SortBy="CreationTime",
            SortOrder="Descending",
            ):
            approved_packages.extend(p["ModelPackageSummaryList"])

        # Return error if no packages found
        if len(approved_packages) == 0:
            error_message = (
                f"No approved ModelPackage found for ModelPackageGroup: {model_package_group_name}"
            )
            logger.error(error_message)
            raise Exception(error_message)

        # Return the pmodel package arn
        model_package_arn = approved_packages[0]["ModelPackageArn"]
        logger.info(f"Identified the latest approved model package: {model_package_arn}")
        return model_package_arn
    except ClientError as e:
        error_message = e.response["Error"]["Message"]
        logger.error(error_message)
        raise Exception(error_message)


def prepare_config(args, model_package_arn, config_name, params):
    """
    Extend the stage configuration with additional parameters and tags based.
    """
    # Read the config template
    with open(f"{config_name}-template.json", "r") as f:
        config = json.load(f)

    # Optional: Add validation of config parameters if needed

    # Add deployment-time parameters
    config.append({ "ParameterKey": "OrgUnitId", "ParameterValue": params["OUId"] })
    config.append({ "ParameterKey": "ExecutionRoleName", "ParameterValue": params["ExecutionRoleName"] })
    config.append({ "ParameterKey": "SageMakerProjectName", "ParameterValue": args.sagemaker_project_name, })
    config.append({ "ParameterKey": "SageMakerProjectId", "ParameterValue": args.sagemaker_project_id })
    config.append({ "ParameterKey": "ModelPackageName", "ParameterValue": model_package_arn })
    config.append({ "ParameterKey": "EnvName", "ParameterValue": args.env_name })
    config.append({ "ParameterKey": "VolumeKmsKeyArn", "ParameterValue": args.ebs_kms_key_arn })
    config.append({ "ParameterKey": "SageMakerSecurityGroupIds", "ParameterValue": args.security_group_ids })
    config.append({ "ParameterKey": "SageMakerSubnetIds", "ParameterValue": args.subnets })

    logger.info(f"Saving CodePipeline CFN template configuration file ({config_name}.json): {json.dumps(config, indent=2)}")
    with open(f"{config_name}.json", "w") as f:
        json.dump(config, f, indent=2)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--log-level", type=str, default=os.environ.get("LOGLEVEL", "INFO").upper())
    parser.add_argument("--sagemaker-project-id", type=str, required=True)
    parser.add_argument("--sagemaker-project-name", type=str, required=True)
    parser.add_argument("--model-package-group-name", type=str, required=True)
    parser.add_argument("--staging-config-name", type=str, default="staging-config")
    parser.add_argument("--prod-config-name", type=str, default="prod-config")
    parser.add_argument("--sagemaker-execution-role-staging-name", type=str, required=True)
    parser.add_argument("--sagemaker-execution-role-prod-name", type=str, required=True)
    parser.add_argument("--organizational-unit-staging-id", type=str, required=True)
    parser.add_argument("--organizational-unit-prod-id", type=str, required=True)
    parser.add_argument("--env-name", type=str, required=True)
    parser.add_argument("--ebs-kms-key-arn", type=str, required=True)
    parser.add_argument("--security-group-ids", type=str, required=True)
    parser.add_argument("--subnets", type=str, required=True)

    args, _ = parser.parse_known_args()

    # Configure logging to output the line number and message
    log_format = "%(levelname)s: [%(filename)s:%(lineno)s] %(message)s"
    logging.basicConfig(format=log_format, level=args.log_level)

    # Get the latest approved package
    model_package_arn = get_approved_package(args.model_package_group_name)

    # Write the staging and prod template configuration files for CodePipeline
    for k, v in {
                args.staging_config_name:{
                    "ExecutionRoleName":args.sagemaker_execution_role_staging_name, 
                    "OUId":args.organizational_unit_staging_id
                    }, 
                 args.prod_config_name:{
                    "ExecutionRoleName":args.sagemaker_execution_role_prod_name, 
                    "OUId":args.organizational_unit_prod_id
                    }
                 }.items():
        prepare_config(args, model_package_arn, k, v)