# Use AWS official Lambda base image for Python 3.12
FROM public.ecr.aws/lambda/python:3.12

# Copy requirements and install
COPY requirements.txt ${LAMBDA_TASK_ROOT}
RUN pip install -r requirements.txt

# Copy logic files
COPY lambda_function.py ${LAMBDA_TASK_ROOT}
COPY gen_text.py ${LAMBDA_TASK_ROOT}
COPY gen_image.py ${LAMBDA_TASK_ROOT}

# Set the CMD to your handler
CMD [ "lambda_function.lambda_handler" ]