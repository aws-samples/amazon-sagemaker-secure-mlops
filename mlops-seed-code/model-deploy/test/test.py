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
    return {"endpoint_name": endpoint_name, "success": True}


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

        # Call endpoint to handle
        return invoke_endpoint(endpoint_name, sm_client)
    except ClientError as e:
        error_message = e.response["Error"]["Message"]
        logger.error(error_message)
        raise Exception(error_message)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--log-level", type=str, default=os.environ.get("LOGLEVEL", "INFO").upper())
    parser.add_argument("--import-build-config", type=str, required=True)
    parser.add_argument("--export-test-results", type=str, required=True)
    parser.add_argument("--sagemaker-execution-role-name", type=str, required=True)
    parser.add_argument("--organizational-unit-id", type=str, required=True)
    args, _ = parser.parse_known_args()

    # Configure logging to output the line number and message
    log_format = "%(levelname)s: [%(filename)s:%(lineno)s] %(message)s"
    logging.basicConfig(format=log_format, level=args.log_level)

    # Load the build config
    with open(args.import_build_config, "r") as f:
        config = {param['ParameterKey']:param['ParameterValue'] for param in json.load(f)}

    boto_sts=boto3.client('sts')

    account_ids = [i['Id'] for i in org_client.list_accounts_for_parent(ParentId=args.organizational_unit_id)['Accounts']]
    # Request to assume the role like this, the ARN is the Role's ARN from
    # the other account you wish to assume. Not your current ARN.
    for account_id in account_ids:
        stsresponse = boto_sts.assume_role(
            RoleArn="arn:aws:iam::{}:role/{}".format(account_id, args.sagemaker_execution_role_name),
            RoleSessionName='newsession'
        )

        # Save the details from assumed role into vars
        newsession_id = stsresponse["Credentials"]["AccessKeyId"]
        newsession_key = stsresponse["Credentials"]["SecretAccessKey"]
        newsession_token = stsresponse["Credentials"]["SessionToken"]
        sm_client = boto3.client(
            'sagemaker',
            aws_access_key_id=newsession_id,
            aws_secret_access_key=newsession_key,
            aws_session_token=newsession_token
        )

        # Get the endpoint name from sagemaker project name
        
        endpoint_name = "{}-{}".format(
            config["SageMakerProjectName"], config["StageName"]
        )
        results = test_endpoint(endpoint_name, sm_client)

        # Print results and write to file
        logger.debug(json.dumps(results, indent=4))
        with open(args.export_test_results, "a") as f:
            json.dump(results, f, indent=4)
