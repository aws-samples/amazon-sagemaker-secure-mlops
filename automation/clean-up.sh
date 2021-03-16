PROJECT_NAME="sagemaker-secure-mlops"

aws cloudformation deploy \
    --template-file automation/automation-lambda-functions.yaml \
    --stack-name ${PROJECT_NAME}-automation \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
        ProjectName=${PROJECT_NAME}

# Invoke lambda to delete the left-over EFS file system
FUNC_NAME=${PROJECT_NAME}-Automation-CleanUpEFS 

aws lambda invoke \
    --invocation-type RequestResponse \
    --function-name ${FUNC_NAME} \
    --cli-binary-format raw-in-base64-out \
    --payload '{ "SageMakerDomainId": "test123" }' \
    --log-type Tail \
    ${PROJECT_NAME}-CleanUpEFS-response.json





