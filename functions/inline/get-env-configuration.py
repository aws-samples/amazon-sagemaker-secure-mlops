# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import json
import boto3
import cfnresponse
from botocore.exceptions import ClientError

sm = boto3.client("sagemaker")
ssm = boto3.client("ssm")

def get_environment(project_name):
    r = sm.describe_domain(
            DomainId=sm.describe_project(
                ProjectName=project_name
                )["CreatedBy"]["DomainId"]
        )
    del r["ResponseMetadata"]

    i = {
        **r,
        **{t["Key"]:t["Value"] 
            for t in sm.list_tags(ResourceArn=r["DomainArn"])["Tags"] 
            if t["Key"] in ["EnvironmentName", "EnvironmentType"]}
    }

    i["DataBucketName"]=ssm.get_parameter(Name=f"{i['EnvironmentName']}-{i['EnvironmentType']}-data-bucket-name")["Parameter"]["Value"]
    i["ModelBucketName"]=ssm.get_parameter(Name=f"{i['EnvironmentName']}-{i['EnvironmentType']}-model-bucket-name")["Parameter"]["Value"]

    return i
    
def lambda_handler(event, context):
    try:
        response_status = cfnresponse.SUCCESS
        r = {}

        if 'RequestType' in event and event['RequestType'] == 'Create':
            r = get_environment(event["ResourceProperties"]["SageMakerProjectName"])

        print(r)
        cfnresponse.send(event, context, response_status, r, '')

    except ClientError as exception:
        print(exception)
        cfnresponse.send(event, context, cfnresponse.FAILED, {}, physicalResourceId=event.get('PhysicalResourceId'), reason=str(exception))
