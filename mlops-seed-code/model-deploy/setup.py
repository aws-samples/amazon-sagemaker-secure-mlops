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
    parser.add_argument("--organizational-unit-staging-id", type=str, default='')
    parser.add_argument("--organizational-unit-prod-id", type=str, default='')
    parser.add_argument("--env-name", type=str, required=True)
    parser.add_argument("--env-type", type=str, required=True)

    args, _ = parser.parse_known_args()

    # Configure logging to output the line number and message
    log_format = "%(levelname)s: [%(filename)s:%(lineno)s] %(message)s"
    logging.basicConfig(format=log_format, level=args.log_level)
    model_package_group_arn = '' 

    # Create model package group if necessary
    try:
        # check if the model package group exists
        model_package_group_arn = sm_client.describe_model_package_group(
            ModelPackageGroupName=args.sagemaker_project_name
            )['ModelPackageGroupArn']

    except ClientError as e:
        if e.response['Error']['Code'] == 'ValidationException':
            # it doesn't exist, create a new one
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

    staging_ou_id = args.organizational_unit_staging_id
    prod_ou_id = args.organizational_unit_prod_id

    if staging_ou_id and prod_ou_id:

        # finally, we need to update the model package group policy
        # Get the account principals based on staging and prod ids
        principals = ['arn:aws:iam::%s:root' % acc for acc in
                [i['Id'] for i in org_client.list_accounts_for_parent(ParentId=staging_ou_id)['Accounts']] +
                [i['Id'] for i in org_client.list_accounts_for_parent(ParentId=prod_ou_id)['Accounts']]]

        # create policy for access to the ModelPackageGroup
        sm_client.put_model_package_group_policy(
            ModelPackageGroupName=args.model_package_group_name,
            ResourcePolicy=json.dumps({
                'Version': '2012-10-17',
                'Statement': [{
                    'Sid': 'multi-account-access-model-package-group',
                    'Effect': 'Allow',
                    'Principal': {'AWS': principals},
                    'Action': ['sagemaker:DescribeModelPackageGroup'],
                    'Resource': model_package_group_arn
                },{
                    'Sid': 'multi-account-access-model',
                    'Effect': 'Allow',
                    'Principal': {'AWS': principals },
                    'Action': [ 'sagemaker:DescribeModelPackage',
                                'sagemaker:ListModelPackages',
                                'sagemaker:UpdateModelPackage,'
                                'sagemaker:CreateModel'],
                    'Resource': f"{model_package_group_arn.replace('model-package-group', 'model-package')}/*"
                }]
            })
        )
            
    
