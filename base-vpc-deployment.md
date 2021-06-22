# Deployment into an existing VPC and with pre-provisioned IAM resources
This deployment option is a special case where the solution is deployed into an AWS account with an existing VPC, network resources and pre-provisioned IAM roles.

## Pre-requisites
1. You need a console access with **Administrator** or **Power User** permission to all AWS accounts of your environment: **dev**, **staging** and **production** accounts. If you use single-account deployment, you need access to the **dev** account only
2. You must install [AWS CLI](https://aws.amazon.com/cli/) if you do not have it
3. Clone the [github repository](https://github.com/aws-samples/amazon-sagemaker-secure-mlops):
```sh
git clone https://github.com/aws-samples/amazon-sagemaker-secure-mlops.git
cd amazon
```

## Prepare the CloudFormation templates
```bash
S3_BUCKET_NAME=<your S3 bucket name>
make package CFN_BUCKET_NAME=$S3_BUCKET_NAME
```

## Deploy VPC, network and IAM resources
This section provides instructions how to provision VPC, subnets, network resources, IAM resources in the dev account. It also describes how the target accounts for multi-account model deployment workflow must be set up.

### Deploy IAM resources
Deploy persona and execution IAM roles as described in [this step-by-step instructions](predeploy-iam-setup.md) in dev, staging and production accounts.

### Deploy VPC into the dev account
For VPC deployment we use the [VPC Quick Start Reference Deployment](https://fwd.aws/9VdxN).  
We deploy VPC with private and public subnets, NAT gateways in two Availability Zones into the **dev** account:

```sh
ENV_NAME=ds-team

aws cloudformation create-stack \
    --template-url https://aws-quickstart.s3.amazonaws.com/quickstart-aws-vpc/templates/aws-vpc.template.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $ENV_NAME-vpc \
    --disable-rollback \
    --parameters \
        ParameterKey=AvailabilityZones,ParameterValue=${AWS_DEFAULT_REGION}a\\,${AWS_DEFAULT_REGION}b \
        ParameterKey=NumberOfAZs,ParameterValue=2
```

### Setup target accounts
📜 If you are **not** going to use multi-account model deployment, you can skip all deployment steps in the staging and production accounts.

To setup multi-account model deployment, you must provision the following network infrastructure resources in **each** of the target accounts:
- VPC
- at least two private subnets in two AZs
- Security group for SageMaker model hosting
- Security group for the VPC endpoints
- VPC endpoints for the AWS services:
  - CloudWatch: `com.amazonaws.${AWS::Region}.logs` and `com.amazonaws.${AWS::Region}.monitoring`
  - ECR: `com.amazonaws.${AWS::Region}.ecr.dkr`
  - ECR API: `com.amazonaws.${AWS::Region}.ecr.api`
  - KMS: `com.amazonaws.${AWS::Region}.kms`
  - S3: `com.amazonaws.${AWS::Region}.s3`
  - SSM: `com.amazonaws.${AWS::Region}.ssm`
  - STS: `com.amazonaws.${AWS::Region}.sts`
  - SageMaker Runtime: `com.amazonaws.${AWS::Region}.sagemaker.runtime`
  - SageMaker API: `com.amazonaws.${AWS::Region}.sagemaker.api`

You can use the provided CloudFormation template [`env-vpc`](cfn_templates/env-vpc.yaml) or your own provisioning process.

If you use the provided template to provision the needed network infrastructure, you must run the following commands in **each of the taget accounts**. 

#### Deploy VPC into the staging and production accounts
Create a VPC with private subnets and an S3 VPC endpoint (note the parameters `CreatePublicSubnets` and `CreateNATGateways` set to `false`):
```sh
ENV_NAME=ds-team

aws cloudformation create-stack \
    --template-url https://aws-quickstart.s3.amazonaws.com/quickstart-aws-vpc/templates/aws-vpc.template.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $ENV_NAME-vpc \
    --disable-rollback \
    --parameters \
        ParameterKey=AvailabilityZones,ParameterValue=${AWS_DEFAULT_REGION}a\\,${AWS_DEFAULT_REGION}b \
        ParameterKey=NumberOfAZs,ParameterValue=2 \
        ParameterKey=CreatePublicSubnets,ParameterValue=false \
        ParameterKey=CreateNATGateways,ParameterValue=false
```

Show VPC output:
```sh
aws cloudformation describe-stacks \
    --stack-name $ENV_NAME-vpc  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"
```

#### Deploy network infrastructure into the staging and production accounts
Deploy network infrastructure for SageMaker endpoint hosting:
```sh
ENV_NAME=ds-team
ENV_TYPE=<set to 'staging' for staging accounts and 'prod' for production accounts>
VPC_ID=<set to the existing VPC id>
S3_VPCE_ID=<set to the existing S3 VPCE id>
PRIVATE_SN_IDS=<comma-delimites list of the existing private subnet ids>
PRIVATE_RT_IDS=<comma-delimites list of the existing private route table ids>
S3_BUCKET_NAME=<S3 bucket in the current account and region to copy the CFN template>

aws s3 mb s3://$S3_BUCKET_NAME

aws cloudformation deploy \
    --template-file cfn_templates/env-vpc.yaml \
    --stack-name $ENV_NAME-network \
    --s3-bucket $S3_BUCKET_NAME \
    --parameter-overrides \
      EnvName=$ENV_NAME \
      EnvType=$ENV_TYPE \
      AvailabilityZones=${AWS_DEFAULT_REGION}a\,${AWS_DEFAULT_REGION}b \
      NumberOfAZs=2 \
      CreateNATGateways=NO \
      CreateVPC=NO \
      CreatePrivateSubnets=NO \
      ExistingVPCId=$VPC_ID \
      ExistingS3VPCEndpointId=$S3_VPCE_ID \
      ExistingPrivateSubnetIds=$PRIVATE_SN_IDS \
      ExistingPrivateRouteTableIds=$PRIVATE_RT_IDS \
      CreateS3VPCEndpoint=NO \
      CreateSSMVPCEndpoint=YES \
      CreateCWVPCEndpoint=YES \
      CreateCWLVPCEndpoint=YES \
      CreateSageMakerAPIVPCEndpoint=YES \
      CreateSageMakerRuntimeVPCEndpoint=YES \
      CreateSageMakerNotebookVPCEndpoint=NO \
      CreateSTSVPCEndpoint=YES \
      CreateServiceCatalogVPCEndpoint=NO \
      CreateCodeCommitVPCEndpoint=NO \
      CreateCodeCommitAPIVPCEndpoint=NO \
      CreateCodePipelineVPCEndpoint=NO \
      CreateCodeBuildVPCEndpoint=NO \
      CreateECRAPIVPCEndpoint=YES \
      CreateECRVPCEndpoint=YES \
      CreateKMSVPCEndpoint=YES \
      DataBucketName=${ENV_NAME}-${ENV_TYPE}-${AWS_DEFAULT_REGION}-data \
      ModelBucketName=${ENV_NAME}-${ENV_TYPE}-${AWS_DEFAULT_REGION}-models
```

Show the stack output:
```sh
aws cloudformation describe-stacks \
    --stack-name $ENV_NAME-network  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"
```

#### SSM parameters in the staging and production accounts
The final step is to set the following SSM parameters in the target accounts for multi-account model deployment workflow:
- `<env-name>-<env-type>-private-subnet-ids`: comma-delimited list of private subnet ids
- `<env-name>-<env-type>-sagemaker-sg-ids`: comma-delimited list of sagemaker security groups
- `<env-name>-<env-type>-staging-kms-vpce-id`: VPC endpoint id for AWS KMS service
- `<env-name>-<env-type>-staging-s3-vpce-id`: VPC endpoint id for S3

These parameters are **created automatically** by the deployment of the `env-vpc.yaml` CloudFormation step. If you don't use the provided templated to provision the network resources, you must create these parameters manually:
```sh
ENV_NAME=ds-team
ENV_TYPE=<set to 'staging' for staging accounts and 'prod' for production accounts>

aws ssm put-parameter \
    --name $ENV_NAME-$ENV_TYPE-<parameter name> \
    --value <parameter value> \
    --type String
```

❗ Repeat all steps in each staging and production account.

Now you can move to the deployment of the data science environment in the **dev** account.

## Deploy Data Science Environment
Provide your specific parameter values for all deployment calls using `ParameterKey=<ParameterKey>,ParameterValue=<Value>` pairs in the following commands. Note, that the parameter `CreateIAMRoles` must be set to `NO` as the IAM roles are provided from outside of CloudFormation stack.

### Deploy core infrastructure
Set the parameters `DSAdministratorRoleArn`, `SecurityControlExecutionRoleArn`, and `SCLaunchRoleArn` to the role ARNs returned in the output of the `core-iam-shared-roles.yaml` stack.

```bash
ENV_NAME=ds-team
DS_ADMIN_ROLE_ARN=<set to the value of DSAdministratorRoleArn iam stack output>
DETECTIVE_CONTROL_ROLE_ARN=<set to the value of SageMakerDetectiveControlExecutionRoleArn iam stack output>
SC_LAUNCH_ROLE_ARN=<set to the value of SCLaunchRoleArn iam stack output>

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/core-main.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $ENV_NAME-core  \
    --disable-rollback \
    --parameters \
        ParameterKey=StackSetName,ParameterValue=$STACK_NAME \
        ParameterKey=CreateIAMRoles,ParameterValue=NO \
        ParameterKey=DSAdministratorRoleArn,ParameterValue=$DS_ADMIN_ROLE_ARN \
        ParameterKey=SecurityControlExecutionRoleArn,ParameterValue=$DETECTIVE_CONTROL_ROLE_ARN \
        ParameterKey=SCLaunchRoleArn,ParameterValue=$SC_LAUNCH_ROLE_ARN
```

Show the stack outputs. You need the output values for the next section "Deploy DS environment".
```sh
aws cloudformation describe-stacks \
    --stack-name $ENV_NAME-core  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"

aws cloudformation describe-stacks \
    --stack-name env-iam-roles  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"

aws cloudformation describe-stacks \
    --stack-name $ENV_NAME-vpc  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"
```

### Deploy DS environment
Provide corresponding template parameters using `ParameterKey=<ParameterKey>,ParameterValue=<Value>` pairs. All values you can find in the outputs of the previously deployed stacks.
```sh
ENV_NAME=ds-team
S3_BUCKET_NAME=<S3 bucket with CFN templates>
DS_TEAM_ADMIN_ROLE_ARN=<value of DSTeamAdministratorRoleArn>
DS_ROLE_ARN=<value of DataScientistRoleArn>
SM_EXEC_ROLE_ARN=<value of SageMakerExecutionRoleArn>
SM_PIPELINE_ROLE_ARN=<value of SageMakerPipelineExecutionRoleArn>
SM_MODEL_ROLE_NAME=<value of SageMakerModelExecutionRoleName, note this is the role name, not ARN>
LAMBDA_ROLE_ARN=<value of SetupLambdaExecutionRoleArn>
SC_PROJECT_ROLE_ARN=<value of SCProjectLaunchRoleArn>
STACKSET_ADMIN_ROLE_ARN=<value of StackSetAdministrationRoleArn>
STACKSET_ROLE_NAME=<value of StackSetExecutionRoleName>
STAGING_ACC_LIST=<comma-delimited list of staging accounts>
PROD_ACC_LIST=<comma-delimited list of production accounts>
VPC_ID=<set to the existing VPC id>
S3_VPCE_ID=<set to the existing S3 VPCE id>
PRIVATE_SN1_CIDR=<CIDR block of the private subnet 1>
PRIVATE_SN2_CIDR=<IDR block of the private subnet 1>

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/env-main.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $ENV_NAME-env \
    --disable-rollback \
    --parameters \
        ParameterKey=EnvName,ParameterValue=$ENV_NAME \
        ParameterKey=EnvType,ParameterValue=dev \
        ParameterKey=CreateEnvironmentIAMRoles,ParameterValue=NO \
        ParameterKey=DSTeamAdministratorRoleArn,ParameterValue=$DS_TEAM_ADMIN_ROLE_ARN \
        ParameterKey=DataScientistRoleArn,ParameterValue=$DS_ROLE_ARN  \
        ParameterKey=SageMakerExecutionRoleArn,ParameterValue=$SM_EXEC_ROLE_ARN \
        ParameterKey=SageMakerPipelineExecutionRoleArn,ParameterValue=$SM_PIPELINE_ROLE_ARN  \
        ParameterKey=SageMakerModelExecutionRoleName,ParameterValue=$SM_MODEL_ROLE_NAME  \
        ParameterKey=SetupLambdaExecutionRoleArn,ParameterValue=$LAMBDA_ROLE_ARN  \
        ParameterKey=SCProjectLaunchRoleArn,ParameterValue=$SC_PROJECT_ROLE_ARN \
        ParameterKey=StackSetAdministrationRoleArn,ParameterValue=$STACKSET_ADMIN_ROLE_ARN  \
        ParameterKey=StackSetExecutionRoleName,ParameterValue=$STACKSET_ROLE_NAME  \
        ParameterKey=StagingAccountList,ParameterValue=$STAGING_ACC_LIST \
        ParameterKey=ProductionAccountList,ParameterValue=$PROD_ACC_LIST  \
        ParameterKey=SetupStackSetExecutionRoleName,ParameterValue=NO \
        ParameterKey=CreateTargetAccountNetworkInfra,ParameterValue=NO \
        ParameterKey=AvailabilityZones,ParameterValue=${AWS_DEFAULT_REGION}a\\,${AWS_DEFAULT_REGION}b \
        ParameterKey=NumberOfAZs,ParameterValue=2 \
        ParameterKey=CreateS3VPCEndpoint,ParameterValue=NO \
        ParameterKey=CreateVPC,ParameterValue=NO \
        ParameterKey=CreateNATGateways,ParameterValue=NO \
        ParameterKey=CreatePrivateSubnets,ParameterValue=NO \
        ParameterKey=ExistingVPCId,ParameterValue=$VPC_ID \
        ParameterKey=ExistingS3VPCEndpointId,ParameterValue=$S3_VPCE_ID \
        ParameterKey=PrivateSubnet1ACIDR,ParameterValue=$PRIVATE_SN1_CIDR \
        ParameterKey=PrivateSubnet2ACIDR,ParameterValue=$PRIVATE_SN2_CIDR \
        ParameterKey=CreateVPCFlowLogsToCloudWatch,ParameterValue=NO \
        ParameterKey=CreateVPCFlowLogsRole,ParameterValue=NO \
        ParameterKey=SeedCodeS3BucketName,ParameterValue=$S3_BUCKET_NAME
```

## Clean-up

### Clean-up dev account
```sh
ENV_NAME=ds-team

aws cloudformation delete-stack --stack-name $ENV_NAME-env
aws cloudformation wait stack-delete-complete --stack-name $ENV_NAME-env

aws cloudformation delete-stack --stack-name $ENV_NAME-core
aws cloudformation wait stack-delete-complete --stack-name $ENV_NAME-core

aws cloudformation delete-stack --stack-name env-iam-target-account-roles
aws cloudformation wait stack-delete-complete --stack-name env-iam-target-account-roles

aws cloudformation delete-stack --stack-name env-iam-roles
aws cloudformation wait stack-delete-complete --stack-name env-iam-roles

aws cloudformation delete-stack --stack-name core-iam-shared-roles
aws cloudformation wait stack-delete-complete --stack-name core-iam-shared-roles

aws cloudformation delete-stack --stack-name core-iam-sc-sm-projects-roles
aws cloudformation wait stack-delete-complete --stack-name core-iam-sc-sm-projects-roles

aws cloudformation delete-stack --stack-name $ENV_NAME-vpc
aws cloudformation wait stack-delete-complete --stack-name $ENV_NAME-vpc
```

### Clean-up staging and production accounts
Run the following commands in **each** staging and production account:
```sh
ENV_NAME=ds-team

aws cloudformation delete-stack --stack-name $ENV_NAME-network
aws cloudformation wait stack-delete-complete --stack-name $ENV_NAME-network

aws cloudformation delete-stack --stack-name $ENV_NAME-vpc
aws cloudformation wait stack-delete-complete --stack-name $ENV_NAME-vpc

aws cloudformation delete-stack --stack-name env-iam-target-account-roles
aws cloudformation wait stack-delete-complete --stack-name env-iam-target-account-roles
```

