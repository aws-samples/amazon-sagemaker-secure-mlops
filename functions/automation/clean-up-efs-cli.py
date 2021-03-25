import json
import boto3
import time
import sys
ssm = boto3.client("ssm")
clean_up_efs = __import__("clean-up-efs")

SSM_PARAMETER_NAME="sagemaker-domain-id"

r = ssm.describe_parameters(
    ParameterFilters=[
        {
            "Key":"Name",
            "Option":"Contains",
            "Values":[SSM_PARAMETER_NAME]
        }
    ]
)

if len(r["Parameters"]) != 1:
    print(f"cannot find any SSM parameter with sagemaker-domain-id: {r}")
else:
    sm_domain_id = ssm.get_parameter(Name=r['Parameters'][0]['Name'])["Parameter"]["Value"]
    print(f"Deleting EFS and VPC for the SageMaker domain id {sm_domain_id}")

    clean_up_efs.delete_efs(sm_domain_id, delete_vpc = True)
