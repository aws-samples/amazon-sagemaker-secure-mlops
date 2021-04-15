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
        # Get the latest approved model package
        response = sm_client.list_model_packages(
            ModelPackageGroupName=model_package_group_name,
            ModelApprovalStatus="Approved",
            SortBy="CreationTime",
            MaxResults=100,
        )
        approved_packages = response["ModelPackageSummaryList"]

        # Fetch more packages if none returned with continuation token
        while len(approved_packages) == 0 and "NextToken" in response:
            logger.debug("Getting more packages for token: {}".format(response["NextToken"]))
            response = sm_client.list_model_packages(
                ModelPackageGroupName=model_package_group_name,
                ModelApprovalStatus="Approved",
                SortBy="CreationTime",
                MaxResults=100,
                NextToken=response["NextToken"],
            )
            approved_packages.extend(response["ModelPackageSummaryList"])

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


def extend_config(args, model_package_arn, stage_config):
    """
    Extend the stage configuration with additional parameters and tags based.
    """
    # Verify that config has parameters and tags sections
    missing_param=True
    for param in stage_config:
        if param.get('ParameterKey') == 'StageName' and param.get('ParameterValue') is not None:
            missing_param=False
    if missing_param:
        raise Exception("Configuration file must include StageName parameter")

    # Create new params
    stage_config.append({ "ParameterKey": "SageMakerProjectName", "ParameterValue": args.sagemaker_project_name })
    stage_config.append({ "ParameterKey": "SageMakerProjectId", "ParameterValue": args.sagemaker_project_id })
    stage_config.append({ "ParameterKey": "ModelPackageName", "ParameterValue": model_package_arn })

    return stage_config

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--log-level", type=str, default=os.environ.get("LOGLEVEL", "INFO").upper())
    parser.add_argument("--model-package-group-name", type=str, required=True)
    parser.add_argument("--sagemaker-project-id", type=str, required=True)
    parser.add_argument("--sagemaker-project-name", type=str, required=True)
    parser.add_argument("--import-staging-config", type=str, default="staging-config.json")
    parser.add_argument("--import-prod-config", type=str, default="prod-config.json")
    parser.add_argument("--export-staging-config", type=str, default="staging-config-export.json")
    parser.add_argument("--export-prod-config", type=str, default="prod-config-export.json")
    parser.add_argument("--sagemaker-execution-role-staging-name", type=str, required=True)
    parser.add_argument("--sagemaker-execution-role-prod-name", type=str, required=True)
    args, _ = parser.parse_known_args()

    # Configure logging to output the line number and message
    log_format = "%(levelname)s: [%(filename)s:%(lineno)s] %(message)s"
    logging.basicConfig(format=log_format, level=args.log_level)

    # Get the latest approved package
    model_package_arn = get_approved_package(args.model_package_group_name)

    # Write the staging config
    with open(args.import_staging_config, "r") as f:
        staging_config = extend_config(args, model_package_arn, json.load(f))
        staging_config.append({"ParameterKey": "RoleName", "ParameterValue": args.sagemaker_execution_role_staging_name})

    logger.debug("Staging config: {}".format(json.dumps(staging_config, indent=4)))
    with open(args.export_staging_config, "w") as f:
        json.dump(staging_config, f, indent=4)

    # Write the prod config
    with open(args.import_prod_config, "r") as f:
        prod_config = extend_config(args, model_package_arn, json.load(f))
        prod_config.append({"ParameterKey": "RoleName", "ParameterValue": args.sagemaker_execution_role_prod_name})

    logger.debug("Prod config: {}".format(json.dumps(prod_config, indent=4)))
    with open(args.export_prod_config, "w") as f:
        json.dump(prod_config, f, indent=4)
