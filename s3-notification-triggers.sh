#!/bin/bash

set -e
set -x

# Variables
aws_account_id=$(aws sts get-caller-identity --query 'Account' --output text)
aws_region="us-east-1"
bucket_name="utkarsh-bucket-6403"  # Updated bucket name
lambda_func_name="s3-lambda-function"
role_name="s3-lambda-sns"
email_address="utkarshadsul0101@gmail.com"

echo "AWS Account ID: $aws_account_id"

# Create IAM Role
role_response=$(aws iam create-role --role-name $role_name --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Action": "sts:AssumeRole",
    "Effect": "Allow",
    "Principal": {
      "Service": [
         "lambda.amazonaws.com",
         "s3.amazonaws.com",
         "sns.amazonaws.com"
      ]
    }
  }]
}')

role_arn=$(echo "$role_response" | jq -r '.Role.Arn')
echo "Role ARN: $role_arn"

# Attach Policies to Role
aws iam attach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess
aws iam attach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess

# Create S3 Bucket
bucket_output=$(aws s3api create-bucket --bucket "$bucket_name" --region "$aws_region")
echo "Bucket creation output: $bucket_output"

# Upload File to Bucket
aws s3 cp ./example_file.txt s3://"$bucket_name"/example_file.txt

# Create Zip for Lambda Function
zip -r s3-lambda-function.zip ./s3-lambda-function

# Create Lambda Function
lambda_response=$(aws lambda create-function \
  --region "$aws_region" \
  --function-name $lambda_func_name \
  --runtime "python3.8" \
  --handler "s3-lambda-function.lambda_handler" \
  --memory-size 128 \
  --timeout 30 \
  --role $role_arn \
  --zip-file "fileb://./s3-lambda-function.zip")

lambda_arn=$(echo "$lambda_response" | jq -r '.FunctionArn')
echo "Lambda Function ARN: $lambda_arn"

# Add S3 Invoke Permission to Lambda
aws lambda add-permission \
  --function-name "$lambda_func_name" \
  --statement-id "s3-lambda-sns" \
  --action "lambda:InvokeFunction" \
  --principal s3.amazonaws.com \
  --source-arn "arn:aws:s3:::$bucket_name"

# Add S3 Event Notification
aws s3api put-bucket-notification-configuration \
  --region "$aws_region" \
  --bucket "$bucket_name" \
  --notification-configuration '{
    "LambdaFunctionConfigurations": [{
        "LambdaFunctionArn": "'"$lambda_arn"'",
        "Events": ["s3:ObjectCreated:*"]
    }]
}'

# Create SNS Topic and Subscribe
topic_arn=$(aws sns create-topic --name s3-lambda-sns --output json | jq -r '.TopicArn')
echo "SNS Topic ARN: $topic_arn"

aws sns subscribe \
  --topic-arn "$topic_arn" \
  --protocol email \
  --notification-endpoint "$email_address"

# Publish Test Message to SNS
aws sns publish \
  --topic-arn "$topic_arn" \
  --subject "A new object created in S3 bucket" \
  --message "Hello from Abhishek.Veeramalla YouTube channel, Learn DevOps Zero to Hero for Free"

