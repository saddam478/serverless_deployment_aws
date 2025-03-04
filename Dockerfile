# Use Amazon Linux as base image optimized for AWS Lambda
FROM public.ecr.aws/lambda/python:3.13

# Set the working directory
WORKDIR /app

# Copy application files
COPY app/ .

# Install dependencies
#RUN pip install --no-cache-dir -r requirements.txt

# Set the command to run the Lambda function
CMD ["lambda_function.lambda_handler"]
