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

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/env-main.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME \
    --disable-rollback \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=EnvName,ParameterValue=$ENV_NAME \
        ParameterKey=EnvType,ParameterValue=dev \
        ParameterKey=AvailabilityZones,ParameterValue=${AWS_DEFAULT_REGION}a\,${AWS_DEFAULT_REGION}b \
        ParameterKey=NumberOfAZs,ParameterValue=2 \
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

# Set variables of the environment
ENV_STACK_NAME="sm-mlops-env"
CORE_STACK_NAME="sm-mlops-core"
ENV_NAME="sm-mlops-dev"
MLOPS_PROJECT_NAME_LIST=("test42" "test43")
MLOPS_PROJECT_ID_LIST=("p-he10tojepvsm" "p-rygwtspxn6yy")
SM_DOMAIN_ID="d-vduglhpqpacm"
STACKSET_NAME="sagemaker-test43-p-rygwtspxn6yy-deploy-staging"
ACCOUNT_IDS="949335012047"

echo "Delete stack instances"
aws cloudformation delete-stack-instances \
    --stack-set-name $STACKSET_NAME \
    --regions $AWS_DEFAULT_REGION \
    --no-retain-stacks \
    --accounts $ACCOUNT_IDS

echo "Delete StackSet $STACKSET_NAME"
aws cloudformation delete-stack-set --stack-set-name $STACKSET_NAME

echo "Clean up SageMaker project(s): ${MLOPS_PROJECT_NAME_LIST}"
for p in ${MLOPS_PROJECT_NAME_LIST[@]};
do
    echo "Delete project $p"
    aws sagemaker delete-project --project-name $p

    for pid in ${MLOPS_PROJECT_ID_LIST[@]};
    do
        echo "Delete S3 bucket: sm-mlops-cp-$p-$pid"
        aws s3 rb s3://sm-mlops-cp-$p-$pid --force
    done
done

echo "Remove VPC-only access policy from the data and model S3 buckets"
aws s3api delete-bucket-policy --bucket $ENV_NAME-${AWS_DEFAULT_REGION}-data
aws s3api delete-bucket-policy --bucket $ENV_NAME-${AWS_DEFAULT_REGION}-models

echo "Empty data S3 buckets"
aws s3 rm s3://$ENV_NAME-$AWS_DEFAULT_REGION-data --recursive
aws s3 rm s3://$ENV_NAME-$AWS_DEFAULT_REGION-models --recursive

# Delete KernelGateway if StartKernelGatewayApps parameter was set to NO

# The following commands are only for manual test (not with CI/CD pipelines)
echo "Delete data science stack"
aws cloudformation delete-stack --stack-name $ENV_STACK_NAME

echo "Wait till $ENV_STACK_NAME stack delete completion"
aws cloudformation wait stack-delete-complete --stack-name $ENV_STACK_NAME

echo "Delete SageMaker EFS"
python3 functions/pipeline/clean-up-efs-cli.py $SM_DOMAIN_ID

echo "Full clean up of the Data Science environment is completed"

# read -n 1 -s -r -p "Press any key to continue"

# *************************************************************** #
# --------- Stop here if you delete only DS environment --------- #
# *************************************************************** #
echo "Delete core stack"
aws cloudformation delete-stack --stack-name $CORE_STACK_NAME

echo "Wait till $CORE_STACK_NAME stack deletion"
aws cloudformation wait stack-delete-complete --stack-name $CORE_STACK_NAME

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