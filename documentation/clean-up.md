# Clean up
---

You must clean up provisioned resources to avoid charges in your AWS account.
The solution provides a [clean up notebook](../sm-notebooks/99-clean-up.ipynb) with a full clean up script. You can run this script after you have finished experimenting with your data science environment. This is the **recommended** way of doing clean up.  

❗ You don't need to perform the following steps if you use the clean up notebook.

If you don't use the clean up notebook, follow the CLI-based clean up instructions below.

## Step 1: Clean up MLOps projects
If you created any SageMaker projects, you must clean up resources as described in the [Clean up after working with MLOps project templates](mlops.md#clean-up-after-working-with-project-templates) section.

To delete resources of the multiple projects, you can use the provided [shell script](../test/cfn-test-e2e.sh).

## Step 2: Empty data and model S3 buckets
CloudFormation `delete-stack` doesn't remove any non-empty S3 bucket. You must empty data science environment S3 buckets for data and models before you can delete the data science environment stack.

Set `AWS_ACCOUNT_ID` variable. You must be logged in the terminal under the same account where the data science environment installed:
```sh
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
```

First, remove VPC-only access policy from the data and model bucket to be able to delete objects from a CLI terminal.
```sh
ENV_NAME=<use default name `sm-mlops` or your data science environment name you chosen when you created the stack>
aws s3api delete-bucket-policy --bucket $ENV_NAME-dev-${AWS_DEFAULT_REGION}-${AWS_ACCOUNT_ID}-data
aws s3api delete-bucket-policy --bucket $ENV_NAME-dev-${AWS_DEFAULT_REGION}-${AWS_ACCOUNT_ID}-models
```

❗ **This is a destructive action. The following command will delete all files in the data and models S3 buckets** ❗  

Now you can empty the buckets:
```sh
aws s3 rm s3://$ENV_NAME-dev-$AWS_DEFAULT_REGION-${AWS_ACCOUNT_ID}-data --recursive
aws s3 rm s3://$ENV_NAME-dev-$AWS_DEFAULT_REGION-${AWS_ACCOUNT_ID}-models --recursive
```

## Step 3: Delete data science environment CloudFormation stacks
Depending on the [deployment type](deployment.md#deployment-options), you must delete the corresponding CloudFormation stacks. The following commands use the default stack names. If you customized the stack names, adjust the commands correspondingly with your stack names.

### Delete data science environment quickstart
```sh
aws cloudformation delete-stack --stack-name ds-quickstart
aws cloudformation wait stack-delete-complete --stack-name ds-quickstart
aws cloudformation delete-stack --stack-name sagemaker-mlops-package-cfn
```

### Delete two-step deployment via CloudFormation
```sh
aws cloudformation delete-stack --stack-name sm-mlops-env
aws cloudformation wait stack-delete-complete --stack-name sm-mlops-env
aws cloudformation delete-stack --stack-name sm-mlops-core 
aws cloudformation wait stack-delete-complete --stack-name sm-mlops-core
aws cloudformation delete-stack --stack-name sagemaker-mlops-package-cfn
```

### Delete two-step deployment via CloudFormation and AWS Service Catalog
1. Assume DS Administrator IAM role via link in the CloudFormation output.
```sh
aws cloudformation describe-stacks \
    --stack-name sm-mlops-core  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"
```

2. In AWS Service Catalog console go to the [_Provisioned Products_](https://console.aws.amazon.com/servicecatalog/home?#provisioned-products), select your product and click **Terminate** from the **Action** button. Wait until the delete process ends.

![terminate-product](../img/terminate-product.png)

![product-terminate](../img/product-terminate.png)

3. Delete the core infrastructure CloudFormation stack:
```sh
aws cloudformation delete-stack --stack-name sm-mlops-core
aws cloudformation wait stack-delete-complete --stack-name sm-mlops-core
aws cloudformation delete-stack --stack-name sagemaker-mlops-package-cfn
```

## Step 4: Delete EFS
The deployment of Studio creates a new EFS in your account. This EFS is shared with all users of Studio and contains home directories for Studio users and may contain your data. When you delete the data science environment stack, the Studio domain, user profile and Apps are also deleted. However, the EFS **is not deleted** and kept "as is" in your account. Additional resources are created by Studio and retained upon deletion together with the EFS:
- EFS mounting points in each private subnet of your VPC
- ENI for each mounting point
- Security groups for EFS inbound and outbound traffic

❗ To delete the EFS and EFS-related resources in your AWS account created by the deployment of this solution, do the following steps **after** running `delete-stack` commands.

❗ **This is a destructive action. All data on the EFS will be deleted (SageMaker home directories). You may want to backup the EFS before deletion.** ❗ 
  
**From AWS console**  
Got to the [EFS console](https://console.aws.amazon.com/efs/home?#/file-systems) and delete the SageMaker EFS. You may want to backup the EFS before deletion.

  To find the SageMaker EFS, click on the file system ID and then on the Tags tab. You see a tag with the Tag Key ManagedByAmazonSageMakerResource. Its Tag Value contains the SageMaker domain ID:
![efs-tags](../img/efs-tags.png)

  Click on the Delete button to delete this EFS.

- Go to the [VPC console](https://console.aws.amazon.com/vpc/home?#vpcs) and delete the data science VPC

**AWS CLI**  
Alternatively, you can remove EFS using the following AWS CLI commands:

1. List SageMaker domain IDs for all EFS with SageMaker tag:
```sh
aws efs describe-file-systems \
  --query 'FileSystems[].Tags[?Key==`ManagedByAmazonSageMakerResource`].Value[]'
```

❗ If you have multiple EFS, double check that you copy the correct domain ID ❗ 

2. Copy the SageMaker domain ID and run the following script from the solution directory:  

❗ This script deletes the EFS ❗ 
```sh
SM_DOMAIN_ID=#SageMaker domain id
pipenv run python3 functions/pipeline/clean-up-efs-cli.py $SM_DOMAIN_ID
```

For the full clean up scrip please refer to the `Clean up` section in the delivered [shell script](../test/cfn-test-e2e.sh) and instructions in [MLOps section](mlops.md#clean-up-after-working-with-project-templates).

---

[Back to README](../README.md)

---

Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
SPDX-License-Identifier: MIT-0
