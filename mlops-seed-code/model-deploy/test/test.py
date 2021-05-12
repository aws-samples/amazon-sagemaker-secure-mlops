# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import argparse
import json
import logging
import os
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)
org_client = boto3.client('organizations')

def invoke_endpoint(endpoint_name, sm_client):
    """
    Add custom logic here to invoke the endpoint and validate reponse
    """
    logger.info(f"invoking the endpoint {endpoint_name}")

    return {"EndpointName": endpoint_name, "Success": True}


def test_endpoint(endpoint_name, sm_client):
    """
    Describe the endpoint and ensure InSerivce, then invoke endpoint.  Raises exception on error.
    """
    error_message = None
    try:
        # Ensure endpoint is in service
        response = sm_client.describe_endpoint(EndpointName=endpoint_name)
        status = response["EndpointStatus"]
        if status != "InService":
            error_message = f"SageMaker endpoint: {endpoint_name} status: {status} not InService"
            logger.error(error_message)
            raise Exception(error_message)

        # Output if endpoint has data capture enbaled
        endpoint_config_name = response["EndpointConfigName"]
        response = sm_client.describe_endpoint_config(EndpointConfigName=endpoint_config_name)
        if "DataCaptureConfig" in response and response["DataCaptureConfig"]["EnableCapture"]:
            logger.info(f"data capture enabled for endpoint config {endpoint_config_name}")
        else:
            logger.info(f"data capture is not enabled for the endpoint config {endpoint_config_name}")

        # Do tests
        return invoke_endpoint(endpoint_name, sm_client)

    except ClientError as e:
        error_message = e.response["Error"]["Message"]
        logger.error(error_message)
        raise Exception(error_message)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--log-level", type=str, default=os.environ.get("LOGLEVEL", "INFO").upper())
    parser.add_argument("--build-config", type=str, required=True)
    parser.add_argument("--test-results-output", type=str, required=True)
    args, _ = parser.parse_known_args()

    # Configure logging to output the line number and message
    log_format = "%(levelname)s: [%(filename)s:%(lineno)s] %(message)s"
    logging.basicConfig(format=log_format, level=args.log_level)

    # Load the CFN template configuration file with stage parameters
    with open(args.build_config, "r") as f:
        config = {param['ParameterKey']:param['ParameterValue'] for param in json.load(f)}

    boto_sts=boto3.client('sts')

    # using the caller account if OU id is not specified - single-account deployment
    account_ids = [boto_sts.get_caller_identity()["Account"]]
    if config["OrgUnitId"]: 
        # Multi-account deployment to all accounts in the OU
        logger.info(f"Multi-account deployment enabled. Test endpoint for the accounts in {config['OrgUnitId']}")
        account_ids = [i['Id'] for i in org_client.list_accounts_for_parent(ParentId=config["OrgUnitId"])['Accounts']]        
         
    # Test the endpoint in each account of the target organizational unit
    for account_id in account_ids:
        # Request to assume the specified role in the target account
        logger.info(f"Assuming the model execution role {config['ExecutionRoleName']} in {account_id}")
        stsresponse = boto_sts.assume_role(
            RoleArn=f"arn:aws:iam::{account_id}:role/{config['ExecutionRoleName']}",
            RoleSessionName='newsession'
        )

        results = {
            "AccountId": account_id,
            "EnvironmentName": config['EnvName'],
            "EnvironmentType": config['EnvType'],
            "SageMakerProjectName": config['SageMakerProjectName'],
            "SageMakerProjectId": config['SageMakerProjectId'],
            "TestResults": test_endpoint(
                f"{config['SageMakerProjectName']}-{config['SageMakerProjectId']}-{config['EnvType']}",
                boto3.client(
                'sagemaker',
                aws_access_key_id=stsresponse["Credentials"]["AccessKeyId"],
                aws_secret_access_key=stsresponse["Credentials"]["SecretAccessKey"],
                aws_session_token=stsresponse["Credentials"]["SessionToken"])
            )
        }

        # Output results and save to the file
        logger.info(json.dumps(results, indent=2))
        with open(args.test_results_output, "a") as f:
            json.dump(results, f, indent=2)
