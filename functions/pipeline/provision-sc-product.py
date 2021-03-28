import json
import boto3
import tempfile
import zipfile
import uuid
import time

sc = boto3.client("servicecatalog")
code_pipeline = boto3.client('codepipeline')
s3 = boto3.client("s3")
sts = boto3.client("sts")
ssm = boto3.client("ssm")

def get_file(artifact, f_name):
    bucket = artifact["location"]["s3Location"]["bucketName"]
    key = artifact["location"]["s3Location"]["objectKey"]

    print(f"{bucket}/{key}")

    with tempfile.NamedTemporaryFile() as tmp_file:
        s3.download_file(bucket, key, tmp_file.name)
        with zipfile.ZipFile(tmp_file.name, 'r') as z:
            return json.loads(z.read(f_name))

def get_role_arn():
    return "/".join(sts.get_caller_identity()["Arn"].replace("assumed-role", "role").replace("sts", "iam").split("/")[0:-1])

def associated_role(portfolio_id):
    role_arn = get_role_arn()
    print(f"associating the lambda execution role {role_arn} with the portfolio {portfolio_id}")
    r = sc.associate_principal_with_portfolio(
        PortfolioId=portfolio_id,
        PrincipalARN=role_arn,
        PrincipalType='IAM'
    )
    print(r)

def provision_product(product_id, product_name, provisioning_artifact_id, provisioning_parameters):
    print(f"launching the product {product_id}")
    r = sc.provision_product(
        ProductId=product_id,
        ProvisioningArtifactId=provisioning_artifact_id,
        ProvisionedProductName=product_name.replace(" ", "_").lower() + "-" + str(uuid.uuid4()).split("-")[0],
        ProvisioningParameters=provisioning_parameters
    )
    print(r)
    print(f"ProvisionedProductId: {r['RecordDetail']['ProvisionedProductId']}")

    ssm.put_parameter(
        Name=f"/ds-product-catalog/{product_id}/provisioned-product-id",
        Description=f"Provisioned product id for product_id: {product_id}",
        Value=r['RecordDetail']['ProvisionedProductId'],
        Type="String",
        Overwrite=True
    )

def lambda_handler(event, context):
    try:
        job_id = event['CodePipeline.job']['id']
        job_data = event['CodePipeline.job']['data']

        user_param = json.loads(job_data["actionConfiguration"]["configuration"]["UserParameters"])
        data = get_file(job_data["inputArtifacts"][0], user_param.get("FileName"))
        print(user_param)

        if user_param.get("Operation") == "associate-role":
            associated_role(data["PortfolioId"])
        else:
            provision_product(
                data["ProductId"], 
                data["ProductName"],
                data["ProvisioningArtifactIds"],
                user_param["ProvisioningParameters"]
                )

        code_pipeline.put_job_success_result(jobId=job_id)
    except Exception as e:
        print(f"exception: {str(e)}")
        code_pipeline.put_job_failure_result(jobId=job_id, failureDetails={'message': str(e), 'type': 'JobFailed'})