function ecr-login
    # Load AWS credentials from 1Password and authenticate with ECR
    op run --env-file ~/.config/fish/docker-ecr.env -- bash -c 'aws ecr get-login-password --region $ECR_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY_URL'
end
