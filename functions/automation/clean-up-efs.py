import json
import boto3
import time

efs = boto3.client("efs")
s3 = boto3.client("s3")
ec2 = boto3.client("ec2")

def lambda_handler(event, context):

    if not event:
        return
        
    bucket = event["CodePipeline.job"]["data"]["inputArtifacts"][0]["location"]["s3Location"]["bucketName"]
    key = event["CodePipeline.job"]["data"]["inputArtifacts"][0]["location"]["s3Location"]["objectKey"]
    user_param = event["CodePipeline.job"]["data"]["actionConfiguration"]["configuration"]["UserParameters"]
    
    print(f"{bucket}/{key}")
    print(f"{user_param}")

    # read output from the CloudFormation stack to get the SageMaker domain id
    obj = s3.get_object(Bucket = bucket, Key = key)
    msg = json.loads(obj['Body'].read().decode('utf-8'))
    
    print(f"object body: {msg}")

    sm_domain_id = msg.get("SageMakerDomainId")
    vpc_id=""

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
        
        while len(efs.describe_mount_targets(FileSystemId=id)["MountTargets"]) > 0:
            print("Wait until mount targes have been deleted")
            time.sleep(5)

        # Delete SageMaker EFS security groups (based on a tag)
        for sg in [sg for sg in ec2.describe_security_groups(Filters=[{"Name":"vpc-id","Values":[vpc_id]}])["SecurityGroups"]
            if sg.get("Tags") and [t["Value"] for t in sg["Tags"] if t["Key"]=="ManagedByAmazonSageMakerResource"][0].split("/")[-1] == sm_domain_id
        ]:
            if len(sg["IpPermissionsEgress"]) > 0:
                ec2.revoke_security_group_egress(GroupId=sg["GroupId"], IpPermissions=sg["IpPermissionsEgress"])
            if len(sg["IpPermissions"]) > 0:
                ec2.revoke_security_group_ingress(GroupId=sg["GroupId"], IpPermissions=sg["IpPermissions"])
            ec2.delete_security_group(GroupId=sg["GroupId"])

        print(f"Delete EFS file system {id}")
        efs.delete_file_system(FileSystemId=id)

    if vpc_id and user_param.split(":")[0] == "VPC" and user_param.split(":")[1] == "delete":
        ec2.delete_vpc(VpcId=vpc_id)