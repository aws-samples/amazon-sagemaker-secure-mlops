#!/bin/bash

# Copyright 2019 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#############################################################################################
# 2nd level-templates 
# These templates contain nested templates and need packaging via `aws cloudformation package`
# To deploy the 2nd level-templates we call `aws cloudformation create-stack`
#
# This scrip contains commands to provision a data science environment via deployment of two 
# CloudFormation stacks: core-main.yaml and env-main.yaml
#############################################################################################
# Package templates
S3_BUCKET_NAME=ilyiny-cfn-artefacts-$AWS_DEFAULT_REGION
make package CFN_BUCKET_NAME=$S3_BUCKET_NAME DEPLOYMENT_REGION=$AWS_DEFAULT_REGION

# ONE-OFF SETUP - ONLY NEEDED IF YOU ARE GOING TO USE MULTI-ACCOUNT MODEL DEPLOYMENT --------

# STEP 1 one-off setup:
# SELF_MANAGED stack set permission model:
# Deploy a stack set execution role to EACH of the target accounts
# This stack set execution role used to deploy the target account roles stack set in env-main.yaml
ENV_NAME="sm-mlops"
ENV_TYPE="staging"
STACK_NAME=$ENV_NAME-setup-stackset-role
ADMIN_ACCOUNT_ID=#Data science account with SageMaker Studio
SETUP_STACKSET_ROLE_NAME=$ENV_NAME-setup-stackset-execution-role

# Delete stack if it exists
aws cloudformation delete-stack --stack-name $STACK_NAME

aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/env-iam-setup-stackset-role.yaml \
                --stack-name $STACK_NAME \
                --capabilities CAPABILITY_NAMED_IAM \
                --parameter-overrides \
                EnvName=$ENV_NAME \
                EnvType=$ENV_TYPE \
                StackSetExecutionRoleName=$SETUP_STACKSET_ROLE_NAME \
                AdministratorAccountId=$ADMIN_ACCOUNT_ID

aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"

# STEP 2 one-off setup:
# Register a delegated administrator to enable AWS Organizations API permission for non-management account
# Must be run in under administrator in the AWS Organizations _management account_
aws organizations register-delegated-administrator \
    --service-principal=member.org.stacksets.cloudformation.amazonaws.com \
    --account-id=$ADMIN_ACCOUNT_ID

aws organizations list-delegated-administrators  \
    --service-principal=member.org.stacksets.cloudformation.amazonaws.com
# END OF ONE-OFF SETUP ----------------------------------------------------------------------

# Data Science environment deployment
# PART 1: core-main.yaml
STACK_NAME="sm-mlops-core"

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/core-main.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME  \
    --disable-rollback \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=StackSetName,ParameterValue=$STACK_NAME

    # Parameter block if CreateIAMRoles = NO (the IAM role ARNs must be provided)
    ParameterKey=CreateIAMRoles,ParameterValue=NO \
    ParameterKey=DSAdministratorRoleArn,ParameterValue= \
    ParameterKey=SCLaunchRoleArn,ParameterValue= 

# PART 2: env-main.yaml
STACK_NAME="sm-mlops-env"
ENV_NAME="sm-mlops"
STAGING_OU_ID="ou-fi18-56v340tb"
PROD_OU_ID="ou-fi18-9fex2edg"
SETUP_STACKSET_ROLE_NAME=$ENV_NAME-setup-stackset-execution-role

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/env-main.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME \
    --disable-rollback \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=EnvName,ParameterValue=$ENV_NAME \
        ParameterKey=EnvType,ParameterValue=dev \
        ParameterKey=AvailabilityZones,ParameterValue=${AWS_DEFAULT_REGION}a\\,${AWS_DEFAULT_REGION}b \
        ParameterKey=NumberOfAZs,ParameterValue=2 \
        ParameterKey=StartKernelGatewayApps,ParameterValue=YES \
        # This parameter block is only needed for multi-account model deployment
        ParameterKey=OrganizationalUnitStagingId,ParameterValue=$STAGING_OU_ID \
        ParameterKey=OrganizationalUnitProdId,ParameterValue=$PROD_OU_ID \
        ParameterKey=SetupStackSetExecutionRoleName,ParameterValue=$SETUP_STACKSET_ROLE_NAME


#####################################################################################################################
# Clean up - *** THIS IS A DESTRUCTIVE ACTION - ALL SAGEMAKER DATA, NOTEBOOKS, PROJECTS, ARTIFACTS WILL BE DELETED***
#####################################################################################################################

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
MLOPS_PROJECT_NAME_LIST=("test3-deploy" "test4-train" "test4-deploy")
MLOPS_PROJECT_ID_LIST=("p-mc3zkgsbl8v3" "p-uode4b0qf2un" "p-y1iloulknggg")
SM_DOMAIN_ID="d-hlnftwb2ywkw"
STACKSET_NAME_LIST=("sagemaker-test4-deploy-p-y1iloulknggg-deploy-staging" "sagemaker-test4-deploy-p-y1iloulknggg-deploy-prod")
ACCOUNT_IDS="949335012047"

# This works only for single-account deployment
echo "Delete stack instances"
for ss in ${STACKSET_NAME_LIST[@]};
do
    echo "delete stack instances for $ss"
    aws cloudformation delete-stack-instances \
        --stack-set-name $ss \
        --regions $AWS_DEFAULT_REGION \
        --no-retain-stacks \
        --accounts $ACCOUNT_IDS
    
    sleep 180

    echo "delete stack set $ss"
    aws cloudformation delete-stack-set --stack-set-name $ss
done

# For multi-account deployment get the list of stack instances
for ss in ${STACKSET_NAME_LIST[@]};
do
    aws cloudformation list-stack-instances \
        --stack-set-name $ss
done

# delete stack instances for all accounts returned by the previous call
ACCOUNT_IDS="" #comma-delimited account list
aws cloudformation delete-stack-instances \
    --stack-set-name "" \
    --regions $AWS_DEFAULT_REGION \
    --no-retain-stacks \
    --accounts $ACCOUNT_IDS

aws cloudformation delete-stack-set --stack-set-name ""
# end multi-account clean-up

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
aws sagemaker list-apps

aws sagemaker delete-app \
    --domain-id $SM_DOMAIN_ID \
    --user-profile-name $ENV_NAME-${AWS_DEFAULT_REGION}-user-profile \
    --app-type KernelGateway \
    --app-name 

# The following commands are only for manual deployment (not with CI/CD pipelines)
echo "Delete data science stack"
aws cloudformation delete-stack --stack-name $ENV_STACK_NAME

echo "Wait till $ENV_STACK_NAME stack delete completion"
aws cloudformation wait stack-delete-complete --stack-name $ENV_STACK_NAME

echo "Delete SageMaker EFS"
python3 functions/pipeline/clean-up-efs-cli.py $SM_DOMAIN_ID

echo "**********************************************************"
echo "Full clean up of the Data Science environment is completed"

# read -n 1 -s -r -p "Press any key to continue"

#*************************************************************** #
#--------- Stop here if you delete only DS environment --------- #
#*************************************************************** #
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

aws cloudformation delete-stack --stack-name sm-mlops-setup-stackset-role

# Must be run in under administrator in the AWS Organizations management account
aws organizations deregister-delegated-administrator \
    --service-principal=member.org.stacksets.cloudformation.amazonaws.com \
    --account-id=$ADMIN_ACCOUNT_ID