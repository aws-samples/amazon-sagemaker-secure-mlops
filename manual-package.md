# Manual packaging of CloudFormation templates
This manual takes you in three simple steps through the process of preparing the delivered CloudFormation templates for the deployment.

## Pre-requisites
Configured AWS CLI with CloudFormation `package` and S3 bucket write/read rights, `$AWS_DEFAULT_REGION` set to the region where you are going to deploy

Unzip the delivered `cfn-templates-<region>.zip` file, `cd` into the directory with CloudFormation templates.

### Create an S3 bucket (optional)
If you have an S3 bucket in the same region where you are deploying and you have write/read rights for it, you don't need to create a new S3 bucket.

To create a new S3 bucket:
```bash
CFN_BUCKET_NAME=<your new S3 bucket name>
PROJECT_NAME=sagemaker-poc

aws s3 mb s3://${CFN_BUCKET_NAME} --region $AWS_DEFAULT_REGION
```

## 1 Replace S3 placeholder links with actual S3 path
For each of the files:
+ `core-sc-shared-portfolio.yaml` 
+ `env-sc-portfolio.yaml` 
+ `env-main.yaml`

Replace all `< S3_CFN_STAGING_BUCKET_PATH >` with `<your new bucket name>/<project name>`
```bash
atom <file>
```
or use your OS-dependent string replacement utility, e.g. for Mac OS:
```bash
sed -ie "s/< S3_CFN_STAGING_BUCKET_PATH >/<your S3 bucket name>\/<project name>/" .
```

## 2 Package CloudFormation templates
For each of the files:
+ `core-main.yaml`
+ `env-main.yaml`  

run `aws cloudformation package`:

```bash
CFN_BUCKET_NAME=<your bucket name>
FILE=core-main.yaml
PROJECT_NAME=sagemaker-poc

echo $AWS_DEFAULT_REGION

aws cloudformation package \
    --template-file $FILE \
    --s3-bucket $CFN_BUCKET_NAME \
    --s3-prefix $PROJECT_NAME \
    --output-template-file $FILE-$AWS_DEFAULT_REGION \
    --region $AWS_DEFAULT_REGION
```

```bash
CFN_BUCKET_NAME=<your bucket name>
FILE=env-main.yaml
PROJECT_NAME=sagemaker-poc

echo $AWS_DEFAULT_REGION

aws cloudformation package \
    --template-file $FILE \
    --s3-bucket $CFN_BUCKET_NAME \
    --s3-prefix $PROJECT_NAME \
    --output-template-file $FILE-packaged \
    --region $AWS_DEFAULT_REGION
```

## 3 Upload CloudFormation templates to the S3 bucket
For each of the files:
+ `core-main.yaml-packaged`
+ `env-main.yaml-packaged`
+ `env-sc-portfolio.yaml` 
+ `env-iam-target-account-roles.yaml` 
+ `env-vpc.yaml` 
+ `project-model-deploy.yaml` 
+ `project-model-build-train.yaml`

run the following commands:

```bash
FILE=<file name from the upload file list>
PROJECT_NAME=sagemaker-poc

aws s3 cp $FILE s3://$CFN_BUCKET_NAME/$PROJECT_NAME/$FILE
```

Now you can go to AWS CloudFormation console and deploy templates via S3 URLs