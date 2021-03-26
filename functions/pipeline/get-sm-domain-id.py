import json
import boto3
import cfnresponse

ssm = boto3.client("ssm")

def lambda_handler(event, context):
    try:
        r = {}

        if 'RequestType' in event and event['RequestType'] == 'Create':
            r["SageMakerDomainId"] = ssm.get_parameter(
                Name=event['ResourceProperties']['SSMParameterName']
                )["Parameter"]["Value"]

        cfnresponse.send(event, context, cfnresponse.SUCCESS, r, '')

    except Exception as e:
        print(f"exception: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {}, physicalResourceId=event.get('PhysicalResourceId'), reason=str(e))
