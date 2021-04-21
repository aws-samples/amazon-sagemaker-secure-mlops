import json
import boto3
import time
import sys
clean_up_efs = __import__("clean-up-efs")


clean_up_efs.delete_efs(sys.argv[1], delete_vpc = True)
