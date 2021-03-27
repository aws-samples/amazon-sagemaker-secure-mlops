import json
import boto3
import tempfile
import zipfile
import uuid

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

def terminate_product(portfolio_id, product_name):

    provisioned_product_id = ssm.get_parameter(Name=f"/{product_name}/provisioned_product_id")["Parameter"]["Value"]

    print(sc.describe_provisioned_product(Id=provisioned_product_id))
    
    try:
        print(f"terminating the provisioned product {provisioned_product_id}")
        r = sc.terminate_provisioned_product(
            ProvisionedProductId=provisioned_product_id,
            TerminateToken=str(uuid.uuid4())
        )
        print(r)
    except Exception as e:
        print(f"exception in terminate_provisioned_product: {str(e)}")

    print(f"disassociating the lambda execution role with the portfolio {portfolio_id}")
    sc.disassociate_principal_from_portfolio(
        PortfolioId=portfolio_id,
        PrincipalARN=get_role_arn()
    )
    print(r)

def lambda_handler(event, context):
    try:
        job_id = event['CodePipeline.job']['id']
        job_data = event['CodePipeline.job']['data']

        user_param = json.loads(job_data["actionConfiguration"]["configuration"]["UserParameters"])
        print(user_param)
        data = get_file(job_data["inputArtifacts"][0], user_param.get("FileName"))

        terminate_product(data["PortfolioId"], data["ProductName"])

        code_pipeline.put_job_success_result(jobId=job_id)
    except Exception as e:
        print(f"exception: {str(e)}")
        code_pipeline.put_job_failure_result(jobId=job_id, failureDetails={'message': str(e), 'type': 'JobFailed'})