import json
import boto3
import time
import tempfile
import zipfile

efs = boto3.client("efs")
s3 = boto3.client("s3")
ec2 = boto3.client("ec2")
code_pipeline = boto3.client('codepipeline')
ssm = boto3.client("ssm")

def delete_efs(sm_domain_id, delete_vpc=False):
    vpc_id=""
    subnets = []

    # Get EFS which belongs to SageMaker (based on a tag)
    print(f"Get EFS file system id(s) for SageMaker domain id {sm_domain_id}")
    for id in [
        fs["FileSystemId"] for fs in efs.describe_file_systems()["FileSystems"] 
            if fs.get("Tags") and [t["Value"] for t in fs["Tags"] if t["Key"]=="ManagedByAmazonSageMakerResource"][0].split("/")[-1] == sm_domain_id
        ]:
        
        print(f"Delete mount targets for EFS file system id: {id}")
        for mt in efs.describe_mount_targets(FileSystemId=id)["MountTargets"]:
            efs.delete_mount_target(MountTargetId=mt["MountTargetId"])
            vpc_id = mt["VpcId"]
            subnets.append(mt["SubnetId"])
        
        while len(efs.describe_mount_targets(FileSystemId=id)["MountTargets"]) > 0:
            print("Wait until mount targes have been deleted")
            time.sleep(5)

        # Get all SageMaker EFS security groups (based on a tag)
        security_groups = [sg for sg in ec2.describe_security_groups(Filters=[{"Name":"vpc-id","Values":[vpc_id]}])["SecurityGroups"]
            if sg.get("Tags") and [t["Value"] for t in sg["Tags"] if t["Key"]=="ManagedByAmazonSageMakerResource"][0].split("/")[-1] == sm_domain_id
        ]
        # Remove all ingress and egress rules
        for sg in security_groups:
            if len(sg["IpPermissionsEgress"]) > 0:
                print(f"revoke egress rule for security group {sg['GroupId']}")
                ec2.revoke_security_group_egress(GroupId=sg["GroupId"], IpPermissions=sg["IpPermissionsEgress"])
            if len(sg["IpPermissions"]) > 0:
                print(f"revoke ingress rule for security group {sg['GroupId']}")
                ec2.revoke_security_group_ingress(GroupId=sg["GroupId"], IpPermissions=sg["IpPermissions"])

        # Delete all SageMaker security groups 
        for sg in security_groups:
            print(f"delete security group {sg['GroupId']}: {sg['GroupName']}")
            ec2.delete_security_group(GroupId=sg["GroupId"])

        print(f"Delete EFS file system {id}")
        efs.delete_file_system(FileSystemId=id)

    if vpc_id and delete_vpc:
        for sn in subnets:
            print(f"delete subnet {sn}")
            ec2.delete_subnet(SubnetId=sn)

        print(f"delete VPC {vpc_id}")
        ec2.delete_vpc(VpcId=vpc_id)


def get_file(artifact, f_name):
    bucket = artifact["location"]["s3Location"]["bucketName"]
    key = artifact["location"]["s3Location"]["objectKey"]

    print(f"{bucket}/{key}")

    with tempfile.NamedTemporaryFile() as tmp_file:
        s3.download_file(bucket, key, tmp_file.name)
        with zipfile.ZipFile(tmp_file.name, 'r') as z:
            return json.loads(z.read(f_name))

def lambda_handler(event, context):
    try:
        job_id = event['CodePipeline.job']['id']
        job_data = event['CodePipeline.job']['data']

        user_param = json.loads(job_data["actionConfiguration"]["configuration"]["UserParameters"])
        print(f"user parameters: {user_param}")

        if user_param.get("FileName"):
            sm_domain_id = get_file(job_data["inputArtifacts"][0], user_param.get("FileName")).get("SageMakerDomainId")
        else:
            sm_domain_id = ssm.get_parameter(Name = user_param.get("SSMParameterName"))['Parameter']['Value']

        delete_efs(sm_domain_id, user_param.get("VPC") == "delete")
        
        code_pipeline.put_job_success_result(jobId=job_id)

    except Exception as e:
        print(f"exception: {str(e)}")
        code_pipeline.put_job_failure_result(jobId=job_id, failureDetails={'message': str(e), 'type': 'JobFailed'})
