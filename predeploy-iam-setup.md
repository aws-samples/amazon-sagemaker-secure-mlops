# Pre-deployment IAM setup

This document provides step-by-step instructions how to prepare your AWS environment for the solution deployment.

## Pre-requsites
1. You need a console access with **Administrator** or **Power User** permission to all AWS accounts of your environment: **dev**, **staging** and **production** accounts. If you use single-account deployment, you need access to the **dev** account only
2. You must install [AWS CLI](https://aws.amazon.com/cli/) if you do not have it
3. Clone the [github repository](https://github.com/aws-samples/amazon-sagemaker-secure-mlops):
```sh
git clone https://github.com/aws-samples/amazon-sagemaker-secure-mlops.git
cd amazon-sagemaker-secure-mlops
```

## Deployment

### Delete the previous deployment stacks

#### Delete the data science environment and core infrastructure CloudFormation stacks
Delete the both the data science environmetn and the core infrastructure CloudFormation stacks starting with the data science environment:
```sh
aws cloudformation delete-stack --stack-name <DS enviroment stack name>
aws cloudformation wait stack-delete-complete --stack-name <DS enviroment stack name>

aws cloudformation delete-stack --stack-name <core stack name>
aws cloudformation wait stack-delete-complete --stack-name <core stack name>
```

#### Delete previous IAM CloudFormation stacks
Delete the previous deployment of IAM principals if exists:
```sh
aws cloudformation delete-stack --stack-name env-iam-target-account-roles
aws cloudformation wait stack-delete-complete --stack-name env-iam-target-account-roles

aws cloudformation delete-stack --stack-name env-iam-roles
aws cloudformation wait stack-delete-complete --stack-name env-iam-roles

aws cloudformation delete-stack --stack-name core-iam-shared-roles
aws cloudformation wait stack-delete-complete --stack-name core-iam-shared-roles

aws cloudformation delete-stack --stack-name core-iam-sc-sm-projects-roles
aws cloudformation wait stack-delete-complete --stack-name core-iam-sc-sm-projects-roles

aws cloudformation delete-stack --stack-name ds-team-setup-stackset-execution-role
aws cloudformation wait stack-delete-complete --stack-name ds-team-setup-stackset-execution-role
```

#### Delete SageMaker service catalog product roles
❗ If you have SageMaker service catalog project roles `AmazonSageMakerServiceCatalogProductsLaunchRole` and `AmazonSageMakerServiceCatalogProductsLaunchRole` already in your **dev** AWS account, you must delete them before deployment:

You can remove the roles from AWS console or using the following CLI script:
```sh
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
```

### Dev account deployment

Run the follwing steps in the **dev** account. Dev account is the account where the SageMaker Studio environment will be deployed.

#### Step 0
Deploy the setup stack set execution role in each of the **staging** and **target** accounts. This step is only needed if:
1. You are going to use multi-account model deployment option
2. You want that the deployment process of the data science environment provisions the network infrastructure and IAM roles in the target accounts.

```sh
ENV_NAME=ds-team
ADMIN_ACCOUNT_ID=<id of the dev account where SageMaker Studio will be deployed>
SETUP_STACKSET_ROLE_NAME=$ENV_NAME-setup-stackset-role
ENV_TYPE=<set staging for staging accounts and prod for production accounts>

aws cloudformation deploy \
      --template-file cfn_templates/env-iam-setup-stackset-role.yaml \
      --stack-name $ENV_NAME-setup-stackset-execution-role \
      --capabilities CAPABILITY_NAMED_IAM \
      --parameter-overrides \
      EnvName=$ENV_NAME \
      EnvType=$ENV_TYPE \
      StackSetExecutionRoleName=$SETUP_STACKSET_ROLE_NAME \
      AdministratorAccountId=$ADMIN_ACCOUNT_ID
```

#### Step 1
Deploy the SageMaker service catalog project roles:
```sh
aws cloudformation deploy \
    --template-file cfn_templates/core-iam-sc-sm-projects-roles.yaml \
    --stack-name core-iam-sc-sm-projects-roles \
    --capabilities CAPABILITY_NAMED_IAM 
```

#### Step 2
Deploy core IAM shared roles.
Set the parameter `DSAdministratorRoleName` to `$STACK_SET_NAME-$AWS_DEFAULT_REGION-DataScienceAdministrator` if you want to create a user IAM role, otherwise leave it empty if you create all user roles outside of this process:
```sh
STACK_SET_NAME=ds-team

aws cloudformation deploy \
    --template-file cfn_templates/core-iam-shared-roles.yaml \
    --stack-name core-iam-shared-roles \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
        DSAdministratorRoleName="" \
        SageMakerDetectiveControlExecutionRoleName=$STACK_SET_NAME-$AWS_DEFAULT_REGION-DSSageMakerDetectiveControlRole \
        SCLaunchRoleName=$STACK_SET_NAME-$AWS_DEFAULT_REGION-DSServiceCatalogLaunchRole
```

#### Step 3
Deploy environment IAM roles.
Set the parameter `CreateIAMUserRoles` to `YES` if you want to create the user IAM roles, otherwise leave it `NO` if you create all user roles outside of this process:
```sh
ENV_NAME=ds-team

aws cloudformation deploy \
    --template-file cfn_templates/env-iam.yaml \
    --stack-name env-iam-roles \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
    EnvName=$ENV_NAME \
    CreateIAMUserRoles=NO
```

#### Step 4
Deploy target account roles (for a trival single-account deployment use case):
```sh
ADMIN_ACCOUNT_ID=<id of the dev account where SageMaker Studio will be deployed>

aws cloudformation deploy \
    --template-file cfn_templates/env-iam-target-account-roles.yaml \
    --stack-name env-iam-target-account-roles \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
    EnvName=$ENV_NAME \
    AdministratorAccountId=$ADMIN_ACCOUNT_ID \
    ModelS3KMSKeyArn="*" \
    ModelBucketName="*$AWS_DEFAULT_REGION-models"
```

#### Show the IAM roles ARNs
Please save the output of the following commands:
```sh
aws cloudformation describe-stacks \
    --stack-name core-iam-shared-roles  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"

aws cloudformation describe-stacks \
    --stack-name env-iam-roles  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"

aws cloudformation describe-stacks \
    --stack-name env-iam-target-account-roles  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"
```

### Staging and production accounts deployment
For multi-account model deployment use case you must deploy the execution roles in **each** of the staging and production accounts.  
❗ Now you must set two stack parameters `SageMakerModelExecutionRoleName` and `StackSetExecutionRoleName` to the values of the role names returned in the output of `env-iam-target-account-roles` stack which you have deployed in the dev account in the Step 4.

Log in the **dev account** and get the output of the `env-iam-target-account-roles` stack:
```sh
aws cloudformation describe-stacks \
    --stack-name env-iam-target-account-roles  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"
```

**You must log in in each of the staging and production accounts and run the following CLI command**:
```sh
ADMIN_ACCOUNT_ID=<id of the dev account where SageMaker Studio will be deployed>
ENV_TYPE=<set staging for staging accounts and prod for production accounts>
MODEL_ROLE_NAME=<set to the value of SageMakerModelExecutionRoleName in env-iam-target-account-roles stack output>
STACKSET_ROLE_NAME=<set to the value of StackSetExecutionRoleName in env-iam-target-account-roles stack output>

aws cloudformation deploy \
    --template-file cfn_templates/env-iam-target-account-roles.yaml \
    --stack-name env-iam-target-account-roles \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
    EnvName=$ENV_NAME \
    EnvType=$ENV_TYPE \
    AdministratorAccountId=$ADMIN_ACCOUNT_ID \
    ModelS3KMSKeyArn="*" \
    ModelBucketName="*$AWS_DEFAULT_REGION-models" \
    SageMakerModelExecutionRoleName=$MODEL_ROLE_NAME \
    StackSetExecutionRoleName=$STACKSET_ROLE_NAME
```

