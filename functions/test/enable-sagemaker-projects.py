# Function: EnableSagemakerProjects
# Purpose:  Enables Sagemaker Projects
import json
import boto3
import cfnresponse
from botocore.exceptions import ClientError

client = boto3.client('sagemaker')
sc_client = boto3.client('servicecatalog')

def lambda_handler(event, context):
    try:
        response_status = cfnresponse.SUCCESS

        if 'RequestType' in event and event['RequestType'] == 'Create':
            enable_sm_projects(event['ResourceProperties']['ExecutionRole'])
        cfnresponse.send(event, context, response_status, {}, '')
    except ClientError as exception:
        print(exception)
        cfnresponse.send(event, context, cfnresponse.FAILED, {}, physicalResourceId=event.get('PhysicalResourceId'), reason=str(exception))

def enable_sm_projects(studio_role_arn):
    # enable Project on account level (accepts portfolio share)
    response = client.enable_sagemaker_servicecatalog_portfolio()

    # associate studio role with portfolio
    response = sc_client.list_accepted_portfolio_shares()

    portfolio_id = ''
    for portfolio in response['PortfolioDetails']:
        if portfolio['ProviderName'] == 'Amazon SageMaker':
            portfolio_id = portfolio['Id']

    response = sc_client.associate_principal_with_portfolio(
        PortfolioId=portfolio_id,
        PrincipalARN=studio_role_arn,
        PrincipalType='IAM'
    )