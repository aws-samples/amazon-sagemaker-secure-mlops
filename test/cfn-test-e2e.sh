#!/bin/bash

# Copyright 2019 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#############################################################################################
# 2nd level-templates 
# These templates contain nested templates and need packaging via `aws cloudformation package`
# To deploy the 2nd level-templates we call `aws cloudformation create-stack`
#############################################################################################
# Package templates
S3_BUCKET_NAME=ilyiny-demo-cfn-artefacts-$AWS_DEFAULT_REGION
make package CFN_BUCKET_NAME=$S3_BUCKET_NAME DEPLOYMENT_REGION=$AWS_DEFAULT_REGION

# core-main.yaml
STACK_NAME="sm-mlops-core"

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/core-main.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME  \
    --disable-rollback \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=StackSetName,ParameterValue=$STACK_NAME

    # Parameter block if CreateIAMRoles = NO (the IAM role ARNs must be provided)
    ParameterKey=CreateIAMRoles,ParameterValue=NO
    ParameterKey=DSAdministratorRoleArn,ParameterValue=
    ParameterKey=SCLaunchRoleArn,ParameterValue=
    ParameterKey=SecurityControlExecutionRoleArn,ParameterValue=

# env-main.yaml
STACK_NAME="sm-mlops-env"
ENV_NAME="sm-mlops"
AVAILABILITY_ZONES=${AWS_DEFAULT_REGION}a

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/env-main.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME \
    --disable-rollback \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=EnvName,ParameterValue=$ENV_NAME \
        ParameterKey=EnvType,ParameterValue=dev \
        ParameterKey=AvailabilityZones,ParameterValue=$AVAILABILITY_ZONES \
        ParameterKey=NumberOfAZs,ParameterValue=1 \
        ParameterKey=StartKernelGatewayApps,ParameterValue=YES


#####################################################################################################################
# Clean up - *** THIS IS A DESTRUCTIVE ACTION - ALL SAGEMAKER DATA, NOTEBOOKS, PROJECTS, ARTIFACTS WILL BE DELETED***

# Get SageMaker domain id
aws cloudformation describe-stacks \
    --stack-name sm-mlops-core  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"

aws cloudformation describe-stacks \
    --stack-name sm-mlops-env  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"

pipenv shell

ENV_STACK_NAME="sm-mlops-env"
CORE_STACK_NAME="sm-mlops-core"
ENV_NAME="sm-mlops-dev"
MLOPS_PROJECT_NAME="test38"
MLOPS_PROJECT_ID="p-jrlwvpb9ukeo"
SM_DOMAIN_ID="d-fkup4t4etdtv"

echo "Delete SageMaker project(s)"
aws sagemaker delete-project --project-name $MLOPS_PROJECT_NAME

echo "Remove VPC-only access policy from the data S3 bucket"
aws s3api delete-bucket-policy --bucket $ENV_NAME-${AWS_DEFAULT_REGION}-data

echo "Empty data S3 bucket"
aws s3 rm s3://$ENV_NAME-$AWS_DEFAULT_REGION-data --recursive

echo "Delete MLOps project pipeline S3 bucket"
aws s3 rb s3://sm-mlops-cp-$MLOPS_PROJECT_NAME-$MLOPS_PROJECT_ID --force

# Delete KernelGateway if StartKernelGatewayApps parameter was set to NO

# The following commands are only for manual test (not with CI/CD pipelines)
echo "Delete data science stack"
aws cloudformation delete-stack --stack-name $ENV_STACK_NAME

# wait till stack deletion
# ...

echo "Delete SageMaker EFS"
python3 functions/pipeline/clean-up-efs-cli.py $SM_DOMAIN_ID

echo "Delete core stack"
aws cloudformation delete-stack --stack-name $CORE_STACK_NAME

echo "Delete Service Catalog SageMaker Project roles"
aws iam detach-role-policy \
    --role-name AmazonSageMakerServiceCatalogProductsLaunchRole \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

aws iam detach-role-policy \
    --role-name AmazonSageMakerServiceCatalogProductsLaunchRole \
    --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"

aws iam delete-role-policy \
    --role-name AmazonSageMakerServiceCatalogProductsLaunchRole \
    --policy-name "AmazonSageMakerServiceCatalogProductsLaunchRolePolicy"

aws iam delete-role --role-name AmazonSageMakerServiceCatalogProductsLaunchRole

aws iam detach-role-policy \
    --role-name AmazonSageMakerServiceCatalogProductsUseRole \
    --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"

aws iam delete-role-policy \
    --role-name AmazonSageMakerServiceCatalogProductsUseRole \
    --policy-name "AmazonSageMakerServiceCatalogProductsUseRolePolicy"

aws iam delete-role --role-name AmazonSageMakerServiceCatalogProductsUseRole